# ShowTouch 0.3.7

`Modified by ChatGPT 6.0 Astra`

A jailbreak tweak that displays touch markers. For rootful iOS 14.x, including
iPhone SE (2020) on iOS 14.8 with unc0ver. All executables support arm64 and arm64e.

Version 0.3.7 addresses the remaining duplicate starting dot inside apps.
SpringBoard now checks which app is in front before rendering a touch. When a
separate app is in front, SpringBoard only draws touches targeted at recognized
local system controls. Normal apps retain the application-level tracking from
0.3.6. This targets a possible second renderer in SpringBoard; the precise
source of the user's extra dot still needs confirmation on the phone.

An optional **Show renderer source** switch, off by default, identifies the
process, window, touch and version drawing each marker. It makes a remaining
duplicate traceable in a screen recording.

Settings and Control Center are native Objective-C. No component requires
Swift, SwiftUI or Orion. All 13 original settings, their defaults and the
preference path are preserved; the diagnostic switch is an additional option.
The disabled-state and Kingdom Rush compatibility changes remain in place.

See INSTALL.md, CHANGELOG.md and VALIDATION.md. Original project and resources
by p-x9, under the included MIT license.
