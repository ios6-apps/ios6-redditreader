/* A small TLS 1.2 client built on mbedTLS, with its own CA bundle. iOS 6's Secure Transport only trusts 2013-era roots, so the app brings its own. */
#ifndef HNTLS_H
#define HNTLS_H
#include <stddef.h>

typedef struct HNConn HNConn;

/* parses a PEM bundle once; returns the number of certificates loaded, or <0 on error */
int hn_tls_set_roots(const char *pem, size_t len);

/* connects and handshakes; on failure returns NULL and fills err */
HNConn *hn_tls_open(const char *host, int port, int timeoutSeconds, char *err, size_t errLen);
/* > 0: bytes, 0: clean end of stream, < 0: error */
int hn_tls_read(HNConn *c, unsigned char *buf, size_t len);
/* writes everything; returns 0 on success */
int hn_tls_write(HNConn *c, const unsigned char *buf, size_t len);
/* aborts a blocked read/write from another thread */
void hn_tls_cancel(HNConn *c);
void hn_tls_close(HNConn *c);

#endif
