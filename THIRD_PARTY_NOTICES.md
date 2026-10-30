# Third-party notices

RedditReader itself is MIT licensed (see `LICENSE`). It includes or uses the following.

## Mbed TLS 3.6.4

`third_party/mbedtls/` - https://github.com/Mbed-TLS/mbedtls
Copyright The Mbed TLS Contributors. Dual-licensed under Apache-2.0 OR GPL-2.0-or-later; RedditReader uses it under the
Apache License 2.0. The licence text is in `third_party/mbedtls/LICENSE`.

## Mozilla CA certificate bundle

`res/cacert.pem` - extracted from the Mozilla root store by the curl project, https://curl.se/docs/caextract.html
Licensed under the Mozilla Public License 2.0 (https://www.mozilla.org/MPL/2.0/). The file is included as provided by curl.se.

## Not included

- The iOS 9.3 SDK that `tools/setup-sdk.sh` downloads from https://github.com/theos/sdks is Apple's property and subject to the
  Xcode and Apple SDKs Agreement. It is fetched on the builder's machine and never stored in this repository.
- Reddit content (feeds, pictures, videos) is fetched from Reddit and the sites it links to at run time; none of it is stored in this repository.
