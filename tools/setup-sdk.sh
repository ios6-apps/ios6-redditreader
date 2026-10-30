#!/bin/bash
# Fetches the public iOS 9.3 SDK from theos/sdks and patches it so armv7 apps link with a current Xcode.
# Usage: tools/setup-sdk.sh [directory]      (default: ./.sdk, which is git-ignored)
# Then:  export SDK93="$(pwd)/.sdk/iPhoneOS9.3.sdk"
#
# Why the patches: the SDK only has .tbd stubs. Current ld64 wants /usr/lib/system/liblaunch.dylib, which the stub
# set does not list, and the memcpy/str* family is missing from libsystem_platform.tbd. We only link against the
# stubs; the real libraries on the device are used at run time. The SDK stays Apple's property (Xcode and Apple SDKs
# Agreement), so it is downloaded here and never committed.
set -euo pipefail
DEST="${1:-.sdk}"
REPO="${THEOS_SDKS_REPO:-https://github.com/theos/sdks.git}"
SDK="$DEST/iPhoneOS9.3.sdk"
mkdir -p "$DEST"
if [ ! -d "$DEST/sdks/.git" ] && [ ! -d "$SDK" ]; then
    git clone --depth 1 --filter=blob:none --sparse "$REPO" "$DEST/sdks"
    git -C "$DEST/sdks" sparse-checkout set iPhoneOS9.3.sdk
    mv "$DEST/sdks/iPhoneOS9.3.sdk" "$SDK"
    rm -rf "$DEST/sdks"
fi
LIB="$SDK/usr/lib/system"
cat > "$LIB/liblaunch.tbd" <<'TBD'
--- !tapi-tbd-v3
archs: [ armv7, armv7s, arm64 ]
platform: ios
install-name: /usr/lib/system/liblaunch.dylib
current-version: 1
compatibility-version: 1
exports:
  - archs: [ armv7, armv7s, arm64 ]
    symbols: [ ]
...
TBD
if ! grep -q '_memcpy,' "$LIB/libsystem_platform.tbd"; then
    perl -0pi -e 's/(symbols:\s+\[ )(_MKGetTimeBaseInfo)/$1_memcmp, _memchr, _memmove, _strcpy, _strncpy, _strcat, _strncat, _bzero, _strrchr, _strncasecmp, _strcasecmp, _memcpy, _memset, _strchr, _strcmp, _strncmp, $2/' "$LIB/libsystem_platform.tbd"
fi
echo "export SDK93=\"$(cd "$SDK" && pwd)\""
