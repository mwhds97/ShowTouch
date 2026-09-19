// Pure decision rules shared by the UIKit runtime and the host regression test.
#ifndef P9_SHOWTOUCH_OWNERSHIP_H
#define P9_SHOWTOUCH_OWNERSHIP_H
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

typedef struct {
    bool springBoard;
    bool foregroundKnown;
    bool foreignAppForeground;
} STTouchOwnership;

static inline bool STTouchOwnershipAllows(STTouchOwnership owner, bool systemUI) {
    if (!owner.springBoard || !owner.foregroundKnown) return true;
    return !owner.foreignAppForeground || systemUI;
}

static inline bool STTouchIsSystemUIClass(const char *name) {
    if (!name) return false;
    while (*name == '_') ++name;
    // Do not allow generic SB/FB hosts, home-screen or switcher containers here:
    // these can also host/observe touches whose actual destination is an app.
    static const char *const prefixes[] = {
        "CCUI", "SBControlCenter", "CSCoverSheet", "CSMainPage",
        "SBCoverSheet", "SBDashBoard", "SBLockScreen", "SBNotificationCenter",
        "NCNotification", "UIStatusBar", "SBStatusBar", "SBMainStatusBar",
        "UIAlert", "SBAlert", "SBVolume", "SBHUD"
    };
    for (size_t i = 0; i < sizeof(prefixes) / sizeof(prefixes[0]); ++i)
        if (strncmp(name, prefixes[i], strlen(prefixes[i])) == 0) return true;
    return false;
}
#endif
