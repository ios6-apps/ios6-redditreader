#include "RRMux.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* ---- growable byte buffer ---- */

typedef struct { uint8_t *p; size_t n, cap; } Buf;

static void bput(Buf *b, const void *d, size_t n) {
    if (b->n + n > b->cap) { b->cap = (b->n + n) * 2 + 256; b->p = realloc(b->p, b->cap); }
    if (n) memcpy(b->p + b->n, d, n);
    b->n += n;
}
static void b8(Buf *b, unsigned v) { uint8_t c = (uint8_t)v; bput(b, &c, 1); }
static void b16(Buf *b, unsigned v) { b8(b, v >> 8); b8(b, v); }
static void b32(Buf *b, uint32_t v) { b16(b, v >> 16); b16(b, v & 0xffff); }
static void btag(Buf *b, const char *t) { bput(b, t, 4); }
static void bzero_(Buf *b, size_t n) { while (n--) b8(b, 0); }

static size_t box_open(Buf *b, const char *t) { size_t at = b->n; b32(b, 0); btag(b, t); return at; }
static void box_close(Buf *b, size_t at) { uint32_t s = (uint32_t)(b->n - at); b->p[at] = s >> 24; b->p[at+1] = s >> 16; b->p[at+2] = s >> 8; b->p[at+3] = s; }

static uint32_t rd32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }
static uint64_t rd64(const uint8_t *p) { return ((uint64_t)rd32(p) << 32) | rd32(p + 4); }
static void wr32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
static void wr64(uint8_t *p, uint64_t v) { wr32(p, (uint32_t)(v >> 32)); wr32(p + 4, (uint32_t)v); }

/* ---- one track read from a fragmented file ---- */

typedef struct {
    uint32_t size, dur, cts;     /* cts is the composition offset */
    int sync;
} Sample;

typedef struct {
    uint8_t *tkhd, *mdhd, *hdlr, *mhd, *dinf, *stsd;    /* raw boxes copied from the input moov */
    uint32_t tkhdN, mdhdN, hdlrN, mhdN, dinfN, stsdN;
    uint32_t timescale, trackId;
    uint32_t defDur, defSize, defFlags;
    Sample *s; size_t n, cap;
    uint64_t *off; size_t noff;  /* file offset of each sample's data */
    int video;
    uint64_t duration;           /* in track timescale */
    FILE *f;
    uint64_t mdatStart;          /* where this track's data begins in the output mdat */
    uint64_t bytes;
} Track;

static uint8_t *dup(const uint8_t *p, uint32_t n) { uint8_t *d = malloc(n); memcpy(d, p, n); return d; }

static int find_box(const uint8_t *p, size_t n, const char *t, const uint8_t **out, uint32_t *outN) {
    size_t at = 0;
    while (at + 8 <= n) {
        uint32_t s = rd32(p + at);
        if (s < 8 || at + s > n) return 0;
        if (!memcmp(p + at + 4, t, 4)) { *out = p + at; *outN = s; return 1; }
        at += s;
    }
    return 0;
}

static int parse_moov(Track *t, const uint8_t *moov, size_t n) {
    const uint8_t *trak, *mdia, *minf, *stbl, *x; uint32_t trakN, mdiaN, minfN, stblN, xN;
    if (!find_box(moov + 8, n - 8, "trak", &trak, &trakN)) return -1;
    if (!find_box(trak + 8, trakN - 8, "tkhd", &x, &xN)) return -1; t->tkhd = dup(x, xN); t->tkhdN = xN;
    t->trackId = rd32(x + 8 + (x[8] == 1 ? 20 : 12));
    if (!find_box(trak + 8, trakN - 8, "mdia", &mdia, &mdiaN)) return -1;
    if (!find_box(mdia + 8, mdiaN - 8, "mdhd", &x, &xN)) return -1; t->mdhd = dup(x, xN); t->mdhdN = xN;
    t->timescale = rd32(x + 8 + (x[8] == 1 ? 20 : 12));
    if (!find_box(mdia + 8, mdiaN - 8, "hdlr", &x, &xN)) return -1; t->hdlr = dup(x, xN); t->hdlrN = xN;
    t->video = !memcmp(x + 16, "vide", 4);
    if (!find_box(mdia + 8, mdiaN - 8, "minf", &minf, &minfN)) return -1;
    if (!find_box(minf + 8, minfN - 8, t->video ? "vmhd" : "smhd", &x, &xN)) return -1; t->mhd = dup(x, xN); t->mhdN = xN;
    if (!find_box(minf + 8, minfN - 8, "dinf", &x, &xN)) return -1; t->dinf = dup(x, xN); t->dinfN = xN;
    if (!find_box(minf + 8, minfN - 8, "stbl", &stbl, &stblN)) return -1;
    if (!find_box(stbl + 8, stblN - 8, "stsd", &x, &xN)) return -1; t->stsd = dup(x, xN); t->stsdN = xN;
    {   /* defaults from mvex/trex */
        const uint8_t *mvex; uint32_t mvexN;
        if (find_box(moov + 8, n - 8, "mvex", &mvex, &mvexN) && find_box(mvex + 8, mvexN - 8, "trex", &x, &xN) && xN >= 32) {
            t->defDur = rd32(x + 20); t->defSize = rd32(x + 24); t->defFlags = rd32(x + 28);
        }
    }
    return 0;
}

static int add_sample(Track *t, uint32_t size, uint32_t dur, uint32_t cts, int sync, uint64_t off) {
    if (t->n == t->cap) {
        t->cap = t->cap ? t->cap * 2 : 4096;
        t->s = realloc(t->s, t->cap * sizeof(Sample));
        t->off = realloc(t->off, t->cap * sizeof(uint64_t));
        if (!t->s || !t->off) return -1;
    }
    t->s[t->n].size = size; t->s[t->n].dur = dur; t->s[t->n].cts = cts; t->s[t->n].sync = sync;
    t->off[t->n] = off; t->n++;
    t->duration += dur;
    return 0;
}

static int parse_moof(Track *t, const uint8_t *moof, size_t n, uint64_t moofPos) {
    const uint8_t *traf; uint32_t trafN;
    size_t at = 0;
    (void)moofPos;
    while (at + 8 <= n) {
        uint32_t s = rd32(moof + at);
        if (s < 8 || at + s > n) return -1;
        if (!memcmp(moof + at + 4, "traf", 4)) {
            traf = moof + at; trafN = s;
            uint32_t defDur = t->defDur, defSize = t->defSize, defFlags = t->defFlags;
            uint64_t base = moofPos, next = 0; int haveNext = 0;
            size_t k = 8;
            while (k + 8 <= trafN) {
                uint32_t bs = rd32(traf + k);
                const uint8_t *b = traf + k;
                if (bs < 8 || k + bs > trafN) return -1;
                if (!memcmp(b + 4, "tfhd", 4)) {
                    uint32_t fl = rd32(b + 8) & 0xffffff;
                    size_t q = 16;                                  /* after version/flags and track id */
                    if (fl & 0x1) { base = rd64(b + q); q += 8; }
                    if (fl & 0x2) q += 4;
                    if (fl & 0x8) { defDur = rd32(b + q); q += 4; }
                    if (fl & 0x10) { defSize = rd32(b + q); q += 4; }
                    if (fl & 0x20) { defFlags = rd32(b + q); q += 4; }
                } else if (!memcmp(b + 4, "trun", 4)) {
                    uint32_t ver = b[8], fl = rd32(b + 8) & 0xffffff, cnt = rd32(b + 12);
                    size_t q = 16;
                    uint64_t pos;
                    uint32_t firstFlags = defFlags; int haveFirst = 0;
                    if (fl & 0x1) { pos = base + (int32_t)rd32(b + q); q += 4; }
                    else pos = haveNext ? next : base;
                    if (fl & 0x4) { firstFlags = rd32(b + q); haveFirst = 1; q += 4; }
                    for (uint32_t i = 0; i < cnt; i++) {
                        uint32_t d = defDur, sz = defSize, f = defFlags, c = 0;
                        if (fl & 0x100) { d = rd32(b + q); q += 4; }
                        if (fl & 0x200) { sz = rd32(b + q); q += 4; }
                        if (fl & 0x400) { f = rd32(b + q); q += 4; }
                        else if (i == 0 && haveFirst) f = firstFlags;
                        if (fl & 0x800) { c = rd32(b + q); q += 4; if (ver == 0 || (int32_t)c < 0) { if ((int32_t)c < 0) c = 0; } }
                        if (add_sample(t, sz, d, c, !(f & 0x10000), pos) != 0) return -1;
                        pos += sz;
                    }
                    next = pos; haveNext = 1;
                }
                k += bs;
            }
        }
        at += s;
    }
    return 0;
}

static int read_track(Track *t, const char *path, char *err, int errLen) {
    t->f = fopen(path, "rb");
    if (!t->f) { snprintf(err, errLen, "cannot open %s", path); return -1; }
    FILE *f = t->f;
    uint8_t h[16];
    uint64_t pos = 0;
    int gotMoov = 0;
    for (;;) {
        if (fseeko(f, (off_t)pos, SEEK_SET) != 0 || fread(h, 1, 8, f) != 8) break;
        uint64_t size = rd32(h);
        if (size == 1) { if (fread(h + 8, 1, 8, f) != 8) break; size = rd64(h + 8); }
        else if (size == 0) { fseeko(f, 0, SEEK_END); size = (uint64_t)ftello(f) - pos; }
        if (size < 8) break;
        if (!memcmp(h + 4, "moov", 4) || !memcmp(h + 4, "moof", 4)) {
            if (size > 32u << 20) { snprintf(err, errLen, "box too big"); return -2; }
            uint8_t *buf = malloc(size);
            fseeko(f, (off_t)pos, SEEK_SET);
            if (fread(buf, 1, size, f) != size) { free(buf); snprintf(err, errLen, "short read"); return -2; }
            int r;
            if (h[4] == 'm' && h[5] == 'o' && h[6] == 'o' && h[7] == 'v') { r = parse_moov(t, buf, size); gotMoov = 1; }
            else r = gotMoov ? parse_moof(t, buf + 8, size - 8, pos) : -1;
            free(buf);
            if (r != 0) { snprintf(err, errLen, "unsupported MP4 layout"); return -3; }
        }
        pos += size;
    }
    if (!gotMoov || !t->n) { snprintf(err, errLen, "no media in %s", path); return -4; }
    return 0;
}

/* ---- writing ---- */

static void put_stbl(Buf *o, Track *t, uint64_t chunkOffset) {
    size_t stbl = box_open(o, "stbl");
    bput(o, t->stsd, t->stsdN);
    size_t at = box_open(o, "stts");
    b32(o, 0);
    size_t cnt = o->n; b32(o, 0);
    uint32_t runs = 0;
    for (size_t i = 0; i < t->n;) { size_t j = i; while (j < t->n && t->s[j].dur == t->s[i].dur) j++; b32(o, (uint32_t)(j - i)); b32(o, t->s[i].dur); runs++; i = j; }
    wr32(o->p + cnt, runs);
    box_close(o, at);
    int anyCts = 0;
    for (size_t i = 0; i < t->n; i++) if (t->s[i].cts) { anyCts = 1; break; }
    if (anyCts) {
        at = box_open(o, "ctts");
        b32(o, 0);
        cnt = o->n; b32(o, 0); runs = 0;
        for (size_t i = 0; i < t->n;) { size_t j = i; while (j < t->n && t->s[j].cts == t->s[i].cts) j++; b32(o, (uint32_t)(j - i)); b32(o, t->s[i].cts); runs++; i = j; }
        wr32(o->p + cnt, runs);
        box_close(o, at);
    }
    if (t->video) {
        at = box_open(o, "stss");
        b32(o, 0);
        cnt = o->n; b32(o, 0); runs = 0;
        for (size_t i = 0; i < t->n; i++) if (t->s[i].sync) { b32(o, (uint32_t)(i + 1)); runs++; }
        wr32(o->p + cnt, runs);
        box_close(o, at);
    }
    at = box_open(o, "stsc"); b32(o, 0); b32(o, 1); b32(o, 1); b32(o, (uint32_t)t->n); b32(o, 1); box_close(o, at);
    at = box_open(o, "stsz"); b32(o, 0); b32(o, 0); b32(o, (uint32_t)t->n);
    for (size_t i = 0; i < t->n; i++) b32(o, t->s[i].size);
    box_close(o, at);
    at = box_open(o, "stco"); b32(o, 0); b32(o, 1); b32(o, (uint32_t)chunkOffset); box_close(o, at);
    box_close(o, stbl);
}

static void put_trak(Buf *o, Track *t, uint32_t id, uint32_t movieMs, uint64_t chunkOffset) {
    size_t trak = box_open(o, "trak");
    size_t at = o->n;
    bput(o, t->tkhd, t->tkhdN);                      /* patched copy: enabled + in movie, new id, duration in ms */
    uint8_t *k = o->p + at;
    if (k[8] == 1) { k[11] = 3; wr32(k + 8 + 4 + 16, id); wr64(k + 8 + 4 + 16 + 8, movieMs); }
    else { k[11] = 3; wr32(k + 12 + 8, id); wr32(k + 12 + 8 + 8, movieMs); }
    if (t->video) {   /* hide the start delay that composition offsets create */
        uint32_t first = t->s[0].cts;
        for (size_t i = 0; i < t->n && i < 32; i++) if (t->s[i].cts < first) first = t->s[i].cts;
        if (first) {
            size_t e = box_open(o, "edts");
            size_t l = box_open(o, "elst");
            b32(o, 0); b32(o, 1); b32(o, movieMs); b32(o, first); b16(o, 1); b16(o, 0);
            box_close(o, l); box_close(o, e);
        }
    }
    size_t mdia = box_open(o, "mdia");
    at = o->n;
    bput(o, t->mdhd, t->mdhdN);
    k = o->p + at;
    if (k[8] == 1) wr64(k + 8 + 4 + 8 + 8 + 4, t->duration); else wr32(k + 12 + 4 + 4 + 4, (uint32_t)t->duration);
    bput(o, t->hdlr, t->hdlrN);
    size_t minf = box_open(o, "minf");
    bput(o, t->mhd, t->mhdN);
    bput(o, t->dinf, t->dinfN);
    put_stbl(o, t, chunkOffset);
    box_close(o, minf); box_close(o, mdia); box_close(o, trak);
}

static void build_moov(Buf *o, Track **tr, int n, uint32_t movieMs, uint64_t *chunk) {
    size_t moov = box_open(o, "moov");
    size_t mvhd = box_open(o, "mvhd");
    b32(o, 0); b32(o, 0); b32(o, 0); b32(o, 1000); b32(o, movieMs);
    b32(o, 0x00010000); b16(o, 0x0100); bzero_(o, 10);
    { static const uint32_t m[9] = { 0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000 }; for (int i = 0; i < 9; i++) b32(o, m[i]); }
    bzero_(o, 24); b32(o, (uint32_t)n + 1);
    box_close(o, mvhd);
    for (int i = 0; i < n; i++) put_trak(o, tr[i], (uint32_t)i + 1, movieMs, chunk[i]);
    box_close(o, moov);
}

static void free_track(Track *t) {
    free(t->tkhd); free(t->mdhd); free(t->hdlr); free(t->mhd); free(t->dinf); free(t->stsd); free(t->s); free(t->off);
    if (t->f) fclose(t->f);
}

int rr_mux(const char *videoPath, const char *audioPath, const char *outPath, char *err, int errLen) {
    Track v, a;
    memset(&v, 0, sizeof v); memset(&a, 0, sizeof a);
    Track *tr[2]; int n = 0, rc = 0;
    FILE *out = NULL;
    Buf moov = { 0 };
    err[0] = 0;
    if ((rc = read_track(&v, videoPath, err, errLen)) != 0) goto done;
    if (!v.video) { snprintf(err, errLen, "first file has no video"); rc = -5; goto done; }
    tr[n++] = &v;
    if (audioPath && read_track(&a, audioPath, err, errLen) == 0 && !a.video) { tr[n++] = &a; err[0] = 0; }
    else err[0] = 0;

    uint32_t movieMs = 0;
    for (int i = 0; i < n; i++) { uint32_t ms = (uint32_t)(tr[i]->duration * 1000ULL / (tr[i]->timescale ? tr[i]->timescale : 1)); if (ms > movieMs) movieMs = ms; }

    uint64_t total = 0;
    for (int i = 0; i < n; i++) { tr[i]->mdatStart = total; for (size_t k = 0; k < tr[i]->n; k++) total += tr[i]->s[k].size; tr[i]->bytes = total - tr[i]->mdatStart; }

    static const uint8_t ftyp[] = { 0,0,0,0x18, 'f','t','y','p', 'm','p','4','2', 0,0,0,0, 'm','p','4','2', 'i','s','o','m' };
    uint64_t chunk[2] = { 0, 0 };
    build_moov(&moov, tr, n, movieMs, chunk);            /* first pass only measures the size */
    uint64_t dataStart = sizeof ftyp + moov.n + 8;
    for (int i = 0; i < n; i++) chunk[i] = dataStart + tr[i]->mdatStart;
    moov.n = 0;
    build_moov(&moov, tr, n, movieMs, chunk);
    if (dataStart + total > 0xffffffffULL) { snprintf(err, errLen, "clip too large"); rc = -6; goto done; }

    out = fopen(outPath, "wb");
    if (!out) { snprintf(err, errLen, "cannot write %s", outPath); rc = -7; goto done; }
    fwrite(ftyp, 1, sizeof ftyp, out);
    fwrite(moov.p, 1, moov.n, out);
    {
        uint8_t mh[8]; wr32(mh, (uint32_t)(total + 8)); memcpy(mh + 4, "mdat", 4);
        fwrite(mh, 1, 8, out);
    }
    {
        uint8_t *buf = malloc(1 << 20);
        for (int i = 0; i < n; i++) {
            Track *t = tr[i];
            for (size_t k = 0; k < t->n; k++) {
                uint32_t left = t->s[k].size;
                if (left > (1u << 20)) { buf = realloc(buf, left); }
                fseeko(t->f, (off_t)t->off[k], SEEK_SET);
                if (fread(buf, 1, left, t->f) != left) { free(buf); snprintf(err, errLen, "truncated download"); rc = -8; goto done; }
                fwrite(buf, 1, left, out);
            }
        }
        free(buf);
    }
    if (fflush(out) != 0) { snprintf(err, errLen, "disk full"); rc = -9; }
done:
    if (out) fclose(out);
    if (rc) remove(outPath);
    free(moov.p);
    free_track(&v); free_track(&a);
    return rc;
}
