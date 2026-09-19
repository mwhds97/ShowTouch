# ShowTouch 0.3.7

1. Install `com.p-x9.showtouch_0.3.7_iphoneos-arm.deb` with Zebra. It upgrades
   the existing package and preserves saved preferences.
2. Respring. Force-close Notes, Settings and Kingdom Rush from the app switcher,
   then reopen them. Running app processes must load the new runtime.
3. Drag inside Notes and pause before lifting. Check that one dot follows the
   finger without another dot remaining at the starting point. Repeat on the
   Home Screen, then inside another app and with Control Center over that app.
4. Hold one finger still while dragging another. Both real fingers should have
   markers. Test Kingdom Rush with Enabled off and then on.

If the extra dot remains, open Settings → showtouch → Troubleshooting and turn
on **Show renderer source**. Record another short drag with both labels visible.
Each label gives the loaded version, process name/PID, window and touch identity.
This identifies whether the duplicate comes from SpringBoard, the app, separate
windows/touches, or an older renderer. Turn the option off afterwards.

No component requires Swift, SwiftUI or Orion. The runtime uses the jailbreak's
Substrate-compatible hooking API. This installer targets rootful iOS 14.x;
iOS 15+ and rootless jailbreaks are not covered. Device testing is still needed.

## Build

Configure Theos, an iOS SDK, a native compiler/linker/signing toolchain and
Python 3. No Swift compiler or support-tool bootstrap is used.

```sh
make clean
make -j2 FINALPACKAGE=1 package
```

The Linux helper runs the same build: `bash scripts/build-linux.sh -j2`.
Keep both arm64 and arm64e in every Makefile. The supplied build uses the
legacy arm64e ABI for rootful iOS 14, without header retagging or ABI conversion.

The portable ownership test runs the same decision rules as the runtime:

```sh
cc -std=c11 -Wall -Wextra -Werror -pedantic tests/touch-ownership.c -o /tmp/st-ownership
/tmp/st-ownership
```

Validate the extracted installer with:

```sh
dpkg-deb -x packages/com.p-x9.showtouch_0.3.7_iphoneos-arm.deb /tmp/showtouch-verify
python3 scripts/verify-binaries.py /tmp/showtouch-verify
```
