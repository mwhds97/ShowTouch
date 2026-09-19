# Build and validation — 0.3.7

The user reports that 0.3.6 fixed Home Screen dragging, while the initial marker
still remains in every app. The earlier Notes recording showed a stationary
origin marker plus a moving marker, both disappearing when the finger lifts.
It did not identify the process or window drawing either marker.

0.3.7 targets a possible second renderer in SpringBoard. Its per-process touch
map could not remove a duplicate produced in another process. SpringBoard now
uses a guarded frontmost-app query, then permits its markers over an app only
for recognized local system controls. Ordinary apps make no private foreground
queries. The production ownership rules are isolated in STTouchOwnership.h;
both new markers and existing-marker cleanup use them after original dispatch.

Evidence and limits:
- tests/touch-ownership.c passed with C11 and strict compiler warnings. It covers
  app versus SpringBoard rendering, forwarding-host exclusion, recognized local
  controls, foreground transitions and the unknown-query fallback. It tests the
  actual decision header, not UIKit delivery or the real private API result.
- Clang static analysis of the runtime and shared preference storage completed
  with zero diagnostics for arm64e targeting iOS 14.0.
- Re-extracting the final Debian installer and running verify-binaries.py passed
  all six Mach-O slices, deployment minima, code-signature page hashes, native
  principal-class exports, bundle versions and preference defaults.
- All 13 original preference specifiers are unchanged. The new renderer source
  switch defaults off. Native Settings and Control Center controller sources
  are byte-identical to 0.3.6; shared storage accepts the additional boolean.
- No executable links Swift, SwiftUI or Orion. No new event hook, marker view,
  marker window, display link or input synthesis was added.
- No connected iPhone was available. The foreground selector's availability and
  result, the private system-control class families and the visual fix remain
  unverified on the device. If the selector is unavailable, the runtime logs once
  and retains the previous behavior. Source labels help identify a remaining dot.

Build environment:
- Theos: 5280bd038207e14f8bd76f5417aa2fe641c03228.
- iPhoneOS 14.5 SDK: theos/sdks 0222fd5413cf4b9af096f37b4621afa2688572f7.
- Clang 13.0.0: Apple LLVM f0fb631dd1a3a2988b23ba5057cd9106713cd0b4.
- ld64 609, TAPI 11.0.0 and ldid from the native portion of
  kabiroberai/swift-toolchain-linux v2.3.0, Ubuntu 22.04 x86_64 archive.
- Toolchain archive SHA256:
  836280038efc4fcc7195019cf9e2cd21b188200a38a47bbda5d26c4d0e9dee82.

Every executable has arm64 and legacy arm64e (subtype 0x00000002), matching the
previous iOS 14 build. The linker's legacy-arm64e warning remains. No headers
were retagged and no ABI conversion was performed. This package targets rootful
iOS 14.x, not iOS 15+ or rootless jailbreaks.

Device checks after respring and reopening the apps:
1. Drag and pause inside Notes, Settings and another app: only one marker follows
   each real finger; no dot stays at the origin. Repeat on the Home Screen.
2. Test Control Center, the cover sheet, status bar and alerts over an app.
3. Hold one finger still while dragging another; keep both genuine touch markers.
4. Lift, cancel, disable the tweak or switch apps; obsolete layers disappear.
5. Test Kingdom Rush with Enabled off and on; open the native Settings pane.
6. If a duplicate remains, enable Show renderer source and record both labels.
   The version, process/PID, window and touch identities distinguish renderers.

The foreground selector is declared in the checked-out primary Theos header:
[SpringBoard.h](https://github.com/theos/headers/blob/13c1f17176d7efe6871551cd69a75b71ac4eeaf1/SpringBoard/SpringBoard.h).
The declaration documents its existence, not its behavior on the user's phone.
