/* Tests for src/RRMux.c: builds two tiny fragmented MP4 files (a video and an audio track, several fragments each),
   joins them, and checks the sample tables and the media data of the result. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "../src/RRMux.h"

static int fails;
#define CHECK(cond, ...) do { if (!(cond)) { fails++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

/* ---- building input files ---- */

typedef struct { uint8_t *p; size_t n, cap; } Buf;
static void put(Buf *b, const void *d, size_t n) {
    if (b->n + n > b->cap) { b->cap = (b->n + n) * 2 + 64; b->p = realloc(b->p, b->cap); }
    memcpy(b->p + b->n, d, n); b->n += n;
}
static void u8(Buf *b, unsigned v) { uint8_t c = (uint8_t)v; put(b, &c, 1); }
static void u16(Buf *b, unsigned v) { u8(b, v >> 8); u8(b, v); }
static void u32(Buf *b, uint32_t v) { u16(b, v >> 16); u16(b, v & 0xffff); }
static void zeros(Buf *b, size_t n) { while (n--) u8(b, 0); }
static size_t open_box(Buf *b, const char *t) { size_t at = b->n; u32(b, 0); put(b, t, 4); return at; }
static void close_box(Buf *b, size_t at) { uint32_t s = (uint32_t)(b->n - at); for (int i = 0; i < 4; i++) b->p[at + i] = s >> (24 - 8 * i); }

typedef struct { uint32_t size, dur, cts; int sync; } Smp;

static void moov(Buf *b, int video, uint32_t timescale) {
    size_t m = open_box(b, "moov");
    size_t x = open_box(b, "mvhd"); zeros(b, 100); close_box(b, x);
    x = open_box(b, "mvex"); size_t t = open_box(b, "trex");
    u32(b, 0); u32(b, 1); u32(b, 1); u32(b, 0); u32(b, 0); u32(b, 0x10000);   /* track 1, default sample flags: not a sync sample */
    close_box(b, t); close_box(b, x);
    size_t trak = open_box(b, "trak");
    x = open_box(b, "tkhd"); u32(b, 7); u32(b, 0); u32(b, 0); u32(b, 1); zeros(b, 68); close_box(b, x);
    size_t mdia = open_box(b, "mdia");
    x = open_box(b, "mdhd"); u32(b, 0); u32(b, 0); u32(b, 0); u32(b, timescale); u32(b, 0); u32(b, 0); close_box(b, x);
    x = open_box(b, "hdlr"); u32(b, 0); u32(b, 0); put(b, video ? "vide" : "soun", 4); zeros(b, 13); close_box(b, x);
    size_t minf = open_box(b, "minf");
    x = open_box(b, video ? "vmhd" : "smhd"); zeros(b, 8); close_box(b, x);
    x = open_box(b, "dinf"); size_t d = open_box(b, "dref"); u32(b, 0); u32(b, 0); close_box(b, d); close_box(b, x);
    size_t stbl = open_box(b, "stbl");
    x = open_box(b, "stsd"); u32(b, 0); u32(b, 0); close_box(b, x);
    close_box(b, stbl); close_box(b, minf); close_box(b, mdia); close_box(b, trak); close_box(b, m);
}

/* one fragment: moof with a trun that carries duration, size, flags and (optionally) composition offsets, then an mdat */
static void fragment(Buf *b, const Smp *s, int n, int cts, uint8_t fill) {
    Buf f = { 0 };
    size_t moof = open_box(&f, "moof");
    size_t x = open_box(&f, "mfhd"); u32(&f, 0); u32(&f, 1); close_box(&f, x);
    size_t traf = open_box(&f, "traf");
    x = open_box(&f, "tfhd"); u32(&f, 0); u32(&f, 1); close_box(&f, x);
    x = open_box(&f, "trun");
    u32(&f, 0x000301 | 0x400 | (cts ? 0x800 : 0)); u32(&f, (uint32_t)n);
    size_t offAt = f.n; u32(&f, 0);                       /* data offset, patched below */
    for (int i = 0; i < n; i++) { u32(&f, s[i].dur); u32(&f, s[i].size); u32(&f, s[i].sync ? 0 : 0x10000); if (cts) u32(&f, s[i].cts); }
    close_box(&f, x); close_box(&f, traf); close_box(&f, moof);
    uint32_t off = (uint32_t)f.n + 8;
    for (int i = 0; i < 4; i++) f.p[offAt + i] = off >> (24 - 8 * i);
    put(b, f.p, f.n); free(f.p);
    size_t total = 0; for (int i = 0; i < n; i++) total += s[i].size;
    u32(b, (uint32_t)total + 8); put(b, "mdat", 4);
    for (int i = 0; i < n; i++) for (uint32_t k = 0; k < s[i].size; k++) u8(b, fill + i);
}

static void write_file(const char *path, Buf *b) { FILE *f = fopen(path, "wb"); fwrite(b->p, 1, b->n, f); fclose(f); free(b->p); b->p = NULL; b->n = b->cap = 0; }

/* ---- reading the output ---- */

static uint32_t rd32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }
static const uint8_t *child(const uint8_t *box, const char *t, int nth) {
    uint32_t size = rd32(box);
    for (size_t at = 8; at + 8 <= size;) {
        uint32_t s = rd32(box + at);
        if (!memcmp(box + at + 4, t, 4) && nth-- == 0) return box + at;
        at += s;
    }
    return NULL;
}
static uint8_t *slurp(const char *path, size_t *n) {
    FILE *f = fopen(path, "rb"); if (!f) return NULL;
    fseek(f, 0, SEEK_END); *n = (size_t)ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t *p = malloc(*n); if (fread(p, 1, *n, f) != *n) { free(p); p = NULL; }
    fclose(f); return p;
}

static const Smp VIDEO1[] = { { 10, 1000, 2000, 1 }, { 20, 1000, 1000, 0 } };
static const Smp VIDEO2[] = { { 15, 1000, 1000, 0 }, { 5, 1000, 2000, 1 } };
static const Smp AUDIO[] = { { 7, 1024, 0, 1 }, { 7, 1024, 0, 1 }, { 9, 1024, 0, 1 } };

int main(void) {
    const char *vp = "mux_test_video.mp4", *ap = "mux_test_audio.mp4", *op = "mux_test_out.mp4";
    char err[200];
    Buf b = { 0 };
    static const uint8_t ftyp[] = { 0,0,0,16, 'f','t','y','p', 'i','s','o','6', 0,0,0,0 };

    put(&b, ftyp, sizeof ftyp); moov(&b, 1, 30000); fragment(&b, VIDEO1, 2, 1, 0x10); fragment(&b, VIDEO2, 2, 1, 0x20); write_file(vp, &b);
    put(&b, ftyp, sizeof ftyp); moov(&b, 0, 44100); fragment(&b, AUDIO, 3, 0, 0xA0); write_file(ap, &b);

    /* video + audio */
    int rc = rr_mux(vp, ap, op, err, sizeof err);
    CHECK(rc == 0, "rr_mux rc=%d %s", rc, err);
    size_t n = 0; uint8_t *o = slurp(op, &n);
    CHECK(o != NULL, "output missing");
    if (o) {
        CHECK(n > 24 && !memcmp(o + 4, "ftyp", 4), "starts with ftyp");
        const uint8_t *moovBox = o + rd32(o);
        CHECK(!memcmp(moovBox + 4, "moov", 4), "moov follows ftyp");
        const uint8_t *mdat = moovBox + rd32(moovBox);
        CHECK(!memcmp(mdat + 4, "mdat", 4), "mdat follows moov");
        CHECK(rd32(mdat) == 8 + 50 + 23, "mdat holds %u bytes, expected %d", rd32(mdat) - 8, 50 + 23);   /* 10+20+15+5, 7+7+9 */
        CHECK((size_t)(mdat - o) + rd32(mdat) == n, "no trailing bytes");

        const uint8_t *vt = child(moovBox, "trak", 0), *at = child(moovBox, "trak", 1);
        CHECK(vt && at && !child(moovBox, "trak", 2), "two tracks");
        if (vt && at) {
            const uint8_t *vst = child(child(child(child(vt, "mdia", 0), "minf", 0), "stbl", 0), "stts", 0);
            CHECK(vst && rd32(vst + 12) == 1 && rd32(vst + 16) == 4 && rd32(vst + 20) == 1000, "video stts: one run of 4 x 1000");
            const uint8_t *vstbl = child(child(child(vt, "mdia", 0), "minf", 0), "stbl", 0);
            const uint8_t *stss = child(vstbl, "stss", 0);
            CHECK(stss && rd32(stss + 12) == 2 && rd32(stss + 16) == 1 && rd32(stss + 20) == 4, "video sync samples are 1 and 4");
            const uint8_t *ctts = child(vstbl, "ctts", 0);
            CHECK(ctts && rd32(ctts + 12) == 3, "video ctts has 3 runs (2000, 1000 x2, 2000)");
            const uint8_t *stsz = child(vstbl, "stsz", 0);
            CHECK(stsz && rd32(stsz + 16) == 4 && rd32(stsz + 20) == 10 && rd32(stsz + 24) == 20 && rd32(stsz + 28) == 15 && rd32(stsz + 32) == 5, "video sample sizes 10 20 15 5");
            const uint8_t *edts = child(vt, "edts", 0);
            CHECK(edts != NULL, "video edit list hides the composition delay");
            if (edts) { const uint8_t *elst = child(edts, "elst", 0); CHECK(elst && rd32(elst + 20) == 1000, "edit list starts at media time 1000"); }
            const uint8_t *vco = child(vstbl, "stco", 0);
            const uint8_t *astbl = child(child(child(at, "mdia", 0), "minf", 0), "stbl", 0);
            const uint8_t *aco = child(astbl, "stco", 0);
            CHECK(!child(astbl, "stss", 0) && !child(astbl, "ctts", 0), "audio has neither stss nor ctts");
            CHECK(vco && aco, "chunk offsets present");
            if (vco && aco) {
                uint32_t vo = rd32(vco + 16), ao = rd32(aco + 16);
                CHECK(vo == (uint32_t)(mdat - o) + 8 && ao == vo + 50, "video data first, audio right after (video %u audio %u)", vo, ao);
                CHECK(vo + 73 <= n && o[vo] == 0x10 && o[vo + 10] == 0x11 && o[vo + 30] == 0x20 && o[vo + 45] == 0x21, "video bytes come through in order");
                CHECK(ao + 23 <= n && o[ao] == 0xA0 && o[ao + 7] == 0xA1 && o[ao + 14] == 0xA2, "audio bytes come through in order");
            }
            const uint8_t *mdhd = child(child(at, "mdia", 0), "mdhd", 0);
            CHECK(mdhd && rd32(mdhd + 20) == 44100 && rd32(mdhd + 24) == 3 * 1024, "audio mdhd: timescale 44100, duration 3072");
        }
        free(o);
    }

    /* video only */
    rc = rr_mux(vp, NULL, op, err, sizeof err);
    CHECK(rc == 0, "video-only rc=%d %s", rc, err);
    o = slurp(op, &n);
    if (o) { const uint8_t *m = o + rd32(o); CHECK(child(m, "trak", 0) && !child(m, "trak", 1), "video-only output has one track"); free(o); }

    /* an unreadable audio file just gives a silent clip */
    rc = rr_mux(vp, "does-not-exist.mp4", op, err, sizeof err);
    CHECK(rc == 0, "missing audio should not fail: rc=%d %s", rc, err);

    /* failures */
    remove(op);
    rc = rr_mux("does-not-exist.mp4", NULL, op, err, sizeof err);
    CHECK(rc < 0 && strstr(err, "cannot open"), "missing video: rc=%d %s", rc, err);
    rc = rr_mux(ap, NULL, op, err, sizeof err);
    CHECK(rc < 0 && strstr(err, "no video"), "audio passed as video: rc=%d %s", rc, err);
    { Buf g = { 0 }; for (int i = 0; i < 64; i++) u8(&g, 0x55); write_file("mux_test_junk.mp4", &g); }
    rc = rr_mux("mux_test_junk.mp4", NULL, op, err, sizeof err);
    CHECK(rc < 0, "garbage input rejected: rc=%d %s", rc, err);
    FILE *f = fopen(op, "rb"); CHECK(f == NULL, "no output file left behind after a failure"); if (f) fclose(f);

    remove(vp); remove(ap); remove(op); remove("mux_test_junk.mp4");
    printf(fails ? "mux_test: %d FAILED\n" : "mux_test: all ok\n", fails);
    return fails != 0;
}
