# 0.3.7 — give foreground apps ownership of their touch markers

The user reports that 0.3.6 fixed the Home Screen but not apps. The earlier video
shows a stationary origin dot and a moving dot, both disappearing on release.
This difference suggests SpringBoard may be drawing a copy of an app touch;
per-process touch deduplication cannot remove a marker in another process.
This remains a diagnosis to verify, not an observed device trace.

- Query the frontmost app only in SpringBoard, using an availability-guarded,
  read-only selector. Do not make private foreground queries in normal apps.
- While another app is in front, suppress SpringBoard markers for generic
  touch hosts. Keep markers for recognized local controls such as Control
  Center, the cover sheet, status bar and alerts.
- Apply the ownership check to both new and existing markers after original
  event delivery, so a Home Screen marker can be removed when an app opens.
- Preserve normal app tracking, stationary real fingers, disabled behavior,
  original event forwarding and layer-only rendering.
- Add optional renderer source labels, off by default. Labels identify version,
  process/PID, window and touch. Preserve every original preference and default.
- Add a portable regression test for the production ownership rules, including
  forwarding hosts, local controls, transitions and an unavailable-query fallback.

If the private foreground selector is unavailable, retain the previous rendering
behavior and log once rather than assuming the screen belongs to another app.
The system-control class list and actual foreground state need device validation.

# 0.3.6 — one touch snapshot per application event

The user reported that 0.3.5 still produced a duplicate dot in every app.
The supplied Notes recording shows one stationary dot at the initial position
and one moving dot; both disappear on the same frame at the end of the drag.
The old stale-object cleanup did not address that behavior.

- Move the single Substrate hook from UIWindow.sendEvent: to UIApplication.sendEvent:.
- Copy active touch identities, owning windows and positions before UIKit
  dispatches the event to individual windows; render after original dispatch.
- Reconcile all marker windows together against the active snapshot.
- Retain stationary fingers and update the existing marker for each touch.
- Reject an older snapshot after nested event delivery, disabling, backgrounding
  or other marker-clearing interruptions during the original call.
- Keep original input delivery exactly once, layers only, native preferences,
  saved settings, both architectures, and no Swift/SwiftUI/Orion dependencies.

This is a correction to the event-observation path based on the supplied video
and source review. The clip does not identify the process or window owning each
dot; the updated binary still requires verification on the user's phone.

# 0.3.5 — remove stale starting markers during dragging

- Reconcile existing markers against the current event for the receiving
  window. A touch that disappears from the event can no longer leave a dot
  at its initial position just because its old object still has an active phase.
- Preserve stationary fingers that remain in the event, and leave markers in
  other windows alone when checking event membership.
- Detach both the dot and coordinate label when a marker is deallocated.
- Keep the existing UIWindow event hook, immediate position updates, native
  preferences, disabled-state behavior and architecture settings.

This fixes a cleanup gap found in the source. The reported device sequence
has not been reproduced here, so on-device drag testing is still required.

# 0.3.4 — native preference pane

The user reported an immediate Settings crash when opening the 0.3.3 pane.
Its architecture and signature checks passed, but these did not validate
Swift/SwiftUI initialization on the device. No Settings crash report was
provided; the exact exception remains unconfirmed.

- Replace SwiftUI hosting with an Objective-C PSListController and native
  preference controls; replace the Swift CC module with CCUIToggleModule.
- Remove all Swift source, runtime compatibility linking, Swift observer
  pointer casts and fatal color-conversion paths.
- Update exported principal classes and the PreferenceLoader entry.
- Preserve all 13 keys, defaults, the existing plist path and notifications.
- Validate each setting independently, preserving Enabled=false when a style
  field is invalid. Merge changed keys under a file lock and write atomically.
- Observe changes on the main queue with cancellable, weak subscriptions.
- Retain color/opacity, offsets, sliders, display mode and the About links.
- Keep the previous touch runtime behavior unchanged.
- Verify native class exports, both architectures, signatures, metadata,
  defaults and absence of Swift/Orion links in all three binaries.

This replaces the failing initialization path. Device testing is still needed
and a crash report is required to confirm the exact cause of the old crash.

# 0.3.3 — fix Settings bundle loading on A12/A13

0.3.2 mistakenly shipped arm64-only executables. An arm64e system process
cannot load an arm64-only bundle; Settings reported `incompatible cpu-subtype:
0x00000000` on the iPhone SE (2020). This was a packaging regression, unrelated
to removing Orion.

- Compile the runtime, preference bundle and Control Center module for both
  arm64 and arm64e, preserving the existing Swift preference UI.
- Fail packaging if any executable is missing either architecture, its
  signature, its bundle metadata, or has an unexpected deployment minimum.
- Keep Linux-built Swift bundles free of newer-ABI compatibility archives.
  They use iOS 14 APIs and no Swift concurrency.
- Retain the 0.3.2 event-driven runtime and disabled-state fixes unchanged.
- Limit this rootful release to iOS 14.x. The supplied Linux build uses the
  legacy arm64e ABI supported by iOS 14 rootful jailbreaks; it is not a build
  for iOS 15+ rootless jailbreaks.
- No Orion dependency. The injected runtime uses Objective-C/Substrate;
  Settings and Control Center continue to use Swift.

The earlier validation document incorrectly stated that an arm64 slice was
sufficient in arm64e system processes. That claim is withdrawn.

# 0.3.2 — compatibility update

The old Enabled switch suppressed rendering but still installed view-controller
hooks, inserted a hidden tracking view at window subview index 0, swizzled window
event delivery and created a CADisplayLink with a strong target cycle.
These are confirmed defects in the supplied source. The exact Kingdom Rush
exception is not confirmed because no crash report was supplied.

This update replaces that runtime with a small Objective-C implementation:
- No UIViewController hooks or inserted tracking UIViews.
- No marker UIWindows, root-controller changes or private keyboard-scene calls.
- Event-driven CALayer markers; no CADisplayLink or retained UITouch objects.
- No event hook installed when a process starts with Enabled off.
- Once installed, the hook only forwards normal input when disabled; disabling
  immediately removes all markers. It is not unswizzled across other tweaks.
- Settings and Control Center keep the existing preference path and format.
- Independent, bounded settings decoding and atomic preference writes.
- Marker cleanup on touch end/cancel, window hiding, interruption and capture
  changes. The next touch event recreates applicable markers.
- Adapted the preference pane to the iOS 14 SwiftUI initializers and corrected
  case-sensitive source paths and the Control Center principal class name.
- No Swift/Orion dependency in the injected runtime. The preference pane and
  Control Center module still use their original Swift implementations.

Markers now draw in the receiving window. They do not use private keyboard
window embedding to appear above unrelated windows. Runtime testing on the
actual Kingdom Rush installation remains required.
