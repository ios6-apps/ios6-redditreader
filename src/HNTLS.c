#include "HNTLS.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <netdb.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <dispatch/dispatch.h>
#include "mbedtls/ssl.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/error.h"
#include "mbedtls/platform_time.h"

/* iOS 6 has no clock_gettime(), so mbedTLS is built with MBEDTLS_PLATFORM_MS_TIME_ALT */
mbedtls_ms_time_t mbedtls_ms_time(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (mbedtls_ms_time_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

struct HNConn {
    int fd;
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context drbg;
};

static mbedtls_x509_crt roots;
static int rootsLoaded;

int hn_tls_set_roots(const char *pem, size_t len) {
    if (rootsLoaded) return 0;
    mbedtls_x509_crt_init(&roots);
    unsigned char *copy = malloc(len + 1);
    if (!copy) return -1;
    memcpy(copy, pem, len); copy[len] = 0;
    /* a positive result is the number of certificates that failed to parse; the rest are still loaded */
    int r = mbedtls_x509_crt_parse(&roots, copy, len + 1);
    free(copy);
    if (r < 0) return r;
    rootsLoaded = 1;
    int n = 0;
    for (mbedtls_x509_crt *c = &roots; c && c->raw.p; c = c->next) n++;
    return n;
}

static int net_send(void *ctx, const unsigned char *buf, size_t len) {
    int fd = *(int *)ctx;
    ssize_t n = send(fd, buf, len, 0);
    if (n >= 0) return (int)n;
    if (errno == EINTR) return MBEDTLS_ERR_SSL_WANT_WRITE;
    if (errno == EAGAIN || errno == EWOULDBLOCK) return MBEDTLS_ERR_SSL_TIMEOUT;
    return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
}

static int net_recv(void *ctx, unsigned char *buf, size_t len) {
    int fd = *(int *)ctx;
    ssize_t n = recv(fd, buf, len, 0);
    if (n >= 0) return (int)n;
    if (errno == EINTR) return MBEDTLS_ERR_SSL_WANT_READ;
    if (errno == EAGAIN || errno == EWOULDBLOCK) return MBEDTLS_ERR_SSL_TIMEOUT;
    return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
}

static int tcp_connect(const char *host, int port, int timeout, char *err, size_t errLen) {
    char portStr[16];
    snprintf(portStr, sizeof portStr, "%d", port);
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    int gai = getaddrinfo(host, portStr, &hints, &res);
    if (gai != 0 || !res) { snprintf(err, errLen, "cannot resolve %s", host); return -1; }
    int fd = -1, lastErr = 0, lastFam = 0, tried = 0;
    for (struct addrinfo *a = res; a; a = a->ai_next) {
        tried++; lastFam = a->ai_family;
        fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
        if (fd < 0) { lastErr = errno; continue; }
        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
        int r = connect(fd, a->ai_addr, a->ai_addrlen);
        if (r < 0 && errno == EINPROGRESS) {
            fd_set w; FD_ZERO(&w); FD_SET(fd, &w);
            struct timeval tv = { timeout, 0 };
            if (select(fd + 1, NULL, &w, NULL, &tv) > 0) {
                int soerr = 0; socklen_t sl = sizeof soerr;
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &sl);
                r = soerr ? -1 : 0; if (soerr) lastErr = soerr;
            } else { r = -1; lastErr = ETIMEDOUT; }
        } else if (r < 0) lastErr = errno;
        if (r == 0) {
            fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK);
            struct timeval tv = { timeout, 0 };
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
            break;
        }
        close(fd); fd = -1;
    }
    freeaddrinfo(res);
    if (fd < 0) snprintf(err, errLen, "cannot connect to %s (errno %d, last family %d, %d tried)", host, lastErr, lastFam, tried);
    return fd;
}

/* a page pulls in dozens of files at once; setting up that many handshakes together starves the phone, so queue them */
static dispatch_semaphore_t openGate;
static dispatch_once_t openGateOnce;

static HNConn *open_locked(const char *host, int port, int timeout, char *err, size_t errLen);

HNConn *hn_tls_open(const char *host, int port, int timeout, char *err, size_t errLen) {
    dispatch_once(&openGateOnce, ^{ openGate = dispatch_semaphore_create(4); });
    dispatch_semaphore_wait(openGate, DISPATCH_TIME_FOREVER);
    HNConn *c = open_locked(host, port, timeout, err, errLen);
    if (!c && !strncmp(err, "cannot connect", 14)) { usleep(400000); c = open_locked(host, port, timeout, err, errLen); }   /* one retry */
    dispatch_semaphore_signal(openGate);
    return c;
}

static HNConn *open_locked(const char *host, int port, int timeout, char *err, size_t errLen) {
    if (!rootsLoaded) { snprintf(err, errLen, "no root certificates"); return NULL; }
    HNConn *c = calloc(1, sizeof *c);
    if (!c) return NULL;
    mbedtls_ssl_init(&c->ssl); mbedtls_ssl_config_init(&c->conf);
    mbedtls_entropy_init(&c->entropy); mbedtls_ctr_drbg_init(&c->drbg);
    char msg[160];
    int r;
    c->fd = tcp_connect(host, port, timeout, err, errLen);
    if (c->fd < 0) goto fail;
    if ((r = mbedtls_ctr_drbg_seed(&c->drbg, mbedtls_entropy_func, &c->entropy, (const unsigned char *)"hn", 2)) != 0) goto tlsfail;
    if ((r = mbedtls_ssl_config_defaults(&c->conf, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT)) != 0) goto tlsfail;
    mbedtls_ssl_conf_rng(&c->conf, mbedtls_ctr_drbg_random, &c->drbg);
    mbedtls_ssl_conf_authmode(&c->conf, MBEDTLS_SSL_VERIFY_REQUIRED);
    mbedtls_ssl_conf_ca_chain(&c->conf, &roots, NULL);
    mbedtls_ssl_conf_read_timeout(&c->conf, 0);
    if ((r = mbedtls_ssl_setup(&c->ssl, &c->conf)) != 0) goto tlsfail;
    if ((r = mbedtls_ssl_set_hostname(&c->ssl, host)) != 0) goto tlsfail;
    mbedtls_ssl_set_bio(&c->ssl, &c->fd, net_send, net_recv, NULL);
    while ((r = mbedtls_ssl_handshake(&c->ssl)) != 0) {
        if (r != MBEDTLS_ERR_SSL_WANT_READ && r != MBEDTLS_ERR_SSL_WANT_WRITE) {
            if (r == MBEDTLS_ERR_X509_CERT_VERIFY_FAILED) {
                char vb[160];
                mbedtls_x509_crt_verify_info(vb, sizeof vb, "", mbedtls_ssl_get_verify_result(&c->ssl));
                snprintf(err, errLen, "certificate not trusted: %s", vb);
                goto fail;
            }
            goto tlsfail;
        }
    }
    return c;
tlsfail:
    mbedtls_strerror(r, msg, sizeof msg);
    snprintf(err, errLen, "TLS: %s (-0x%04x)", msg, (unsigned)-r);
fail:
    hn_tls_close(c);
    return NULL;
}

int hn_tls_read(HNConn *c, unsigned char *buf, size_t len) {
    for (;;) {
        int r = mbedtls_ssl_read(&c->ssl, buf, len);
        if (r == MBEDTLS_ERR_SSL_WANT_READ || r == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        if (r == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) return 0;
        /* many servers close the socket without close_notify; treat it as the end of the stream */
        if (r == MBEDTLS_ERR_SSL_CONN_EOF || r == MBEDTLS_ERR_SSL_INTERNAL_ERROR) return 0;
        return r;
    }
}

int hn_tls_write(HNConn *c, const unsigned char *buf, size_t len) {
    size_t done = 0;
    while (done < len) {
        int r = mbedtls_ssl_write(&c->ssl, buf + done, len - done);
        if (r == MBEDTLS_ERR_SSL_WANT_READ || r == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        if (r < 0) return r;
        done += (size_t)r;
    }
    return 0;
}

void hn_tls_cancel(HNConn *c) { if (c && c->fd >= 0) shutdown(c->fd, SHUT_RDWR); }

void hn_tls_close(HNConn *c) {
    if (!c) return;
    if (c->fd >= 0) { mbedtls_ssl_close_notify(&c->ssl); close(c->fd); }
    mbedtls_ssl_free(&c->ssl); mbedtls_ssl_config_free(&c->conf);
    mbedtls_ctr_drbg_free(&c->drbg); mbedtls_entropy_free(&c->entropy);
    free(c);
}
