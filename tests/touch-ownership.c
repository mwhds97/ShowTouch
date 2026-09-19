#include <assert.h>
#include <stdio.h>
#include "../Sources/STTouchOwnership.h"

int main(void) {
    const STTouchOwnership app = {false, false, false};
    const STTouchOwnership home = {true, true, false};
    const STTouchOwnership overApp = {true, true, true};
    const STTouchOwnership unknown = {true, false, false};

    // The same physical touch observed by app and SpringBoard has one renderer.
    assert(STTouchOwnershipAllows(app, false));
    assert(!STTouchOwnershipAllows(overApp, false));
    assert(STTouchOwnershipAllows(app, false) + STTouchOwnershipAllows(overApp, false) == 1);
    assert(STTouchOwnershipAllows(home, false));
    assert(STTouchOwnershipAllows(home, true));

    const char *controls[] = {"CCUIModularControlCenterOverlayViewController",
        "SBControlCenterWindow", "CSCoverSheetViewController", "_UIStatusBarModern",
        "UIAlertController"};
    for (size_t i = 0; i < sizeof(controls) / sizeof(controls[0]); ++i) {
        assert(STTouchIsSystemUIClass(controls[i]));
        assert(STTouchOwnershipAllows(overApp, STTouchIsSystemUIClass(controls[i])));
    }

    // Hosts and home-screen ancestors cannot opt an app touch back into drawing.
    const char *hosts[] = {"SBSystemGestureWindow", "FBSystemGestureWindow",
        "SBDeviceApplicationSceneView", "SBApplicationSceneViewController",
        "_UIRemoteView", "SBHomeScreenWindow", "SBIconView",
        "SBFluidSwitcherViewController", "UIWindow", "UIView", "SpringBoard", ""};
    for (size_t i = 0; i < sizeof(hosts) / sizeof(hosts[0]); ++i) {
        assert(!STTouchIsSystemUIClass(hosts[i]));
        assert(!STTouchOwnershipAllows(overApp, STTouchIsSystemUIClass(hosts[i])));
    }
    assert(!STTouchIsSystemUIClass(NULL));
    assert(STTouchOwnershipAllows(unknown, false));

    // The same gate prunes an old home marker when the foreground becomes an app.
    bool markerVisible = STTouchOwnershipAllows(home, false);
    markerVisible = markerVisible && STTouchOwnershipAllows(overApp, false);
    assert(!markerVisible);
    assert(STTouchOwnershipAllows(home, false));
    puts("PASS: app/SpringBoard ownership, forwarding hosts, local system controls, transitions and unknown-API fallback");
    return 0;
}
