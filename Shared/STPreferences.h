#import <UIKit/UIKit.h>
#define ST_PREFERENCES_NOTIFICATION "com.p-x9.showtouch.prefschanged"
FOUNDATION_EXPORT NSDictionary<NSString *, id> *STPreferenceDefaults(void);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *STLoadPreferences(void);
FOUNDATION_EXPORT BOOL STWritePreferences(NSDictionary<NSString *, id> *changes, NSError **error);
FOUNDATION_EXPORT UIColor *STPreferenceColor(NSString *rgba);
FOUNDATION_EXPORT NSString *STPreferenceHexColor(UIColor *color);
