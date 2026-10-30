# Third-party code

| Path | What | Version | Upstream | Licence |
|---|---|---|---|---|
| `mbedtls/` | TLS and X.509 library (`include/` and `library/` only) | 3.6.4 | https://github.com/Mbed-TLS/mbedtls | Apache-2.0 OR GPL-2.0-or-later (used under Apache-2.0) |
| `hn_mbedtls_config.h` | Build configuration for mbedTLS | derived from 3.6.4 `mbedtls_config.h` | - | same as mbedTLS |
| `../res/cacert.pem` | Root certificate bundle | Mozilla roots as of 20 Oct 2026 | https://curl.se/docs/caextract.html | MPL-2.0 |

## mbedTLS

The tree is a trimmed copy of the 3.6.4 release: only the `include/` and `library/` directories and the licence file are kept.
`build.sh` compiles every `library/*.c`.

### hn_mbedtls_config.h

This is the stock `include/mbedtls/mbedtls_config.h` of 3.6.4 with the following changes (each disabled option is replaced
by a `/* disabled: ... */` comment, so `diff` against the stock file shows exactly these lines):

- Disabled because the app is a TLS 1.2 client only: `MBEDTLS_SSL_PROTO_TLS1_3` and its three key-exchange modes and compatibility mode,
  `MBEDTLS_SSL_PROTO_DTLS` with `MBEDTLS_SSL_DTLS_*`, `MBEDTLS_SSL_SESSION_TICKETS`, `MBEDTLS_SSL_SRV_C`, `MBEDTLS_SSL_CACHE_C`,
  `MBEDTLS_SSL_COOKIE_C`, `MBEDTLS_SSL_TICKET_C`.
- Disabled because they need facilities that are not wanted or not available on iOS 6: `MBEDTLS_FS_IO`, `MBEDTLS_NET_C`, `MBEDTLS_TIMING_C`,
  `MBEDTLS_PSA_CRYPTO_STORAGE_C`, `MBEDTLS_PSA_ITS_FILE_C`.
- Added at the end: `MBEDTLS_PLATFORM_MS_TIME_ALT`. iOS 6 has no `clock_gettime()`, which mbedTLS 3.6 uses for its millisecond clock,
  so `src/HNTLS.c` provides `mbedtls_ms_time()` instead.

### Updating

1. Download a release from the upstream repository and copy its `include/` and `library/` directories and `LICENSE` over `mbedtls/`
   (delete the upstream `.gitignore` and `CMakeLists.txt` files).
2. Re-apply the changes above to the new `include/mbedtls/mbedtls_config.h` and save it as `hn_mbedtls_config.h`.
3. Run `./build.sh device` and `./build.sh sim`, then open a few feeds, pictures and a video post with the simulator build.

## cacert.pem

`res/cacert.pem` is the Mozilla CA bundle as converted by the curl project (the header of the file gives the date and source).
The app trusts exactly these roots and nothing else, so refresh it from time to time:

    curl -o res/cacert.pem https://curl.se/ca/cacert.pem

An out-of-date bundle makes sites that switched to a newer root fail with "secure connection failed".
