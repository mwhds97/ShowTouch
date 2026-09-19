#import <ControlCenterUIKit/CCUIToggleModule.h>
#import <notify.h>
#import "STPreferences.h"

@interface P9ShowTouchControlCenterToggle : CCUIToggleModule
@property(nonatomic) int notificationToken;
@property(nonatomic) BOOL observing;
@end

@implementation P9ShowTouchControlCenterToggle
- (instancetype)init {
    if ((self = [super init])) {
        __weak P9ShowTouchControlCenterToggle *weakSelf = self;
        int token;
        if (notify_register_dispatch(ST_PREFERENCES_NOTIFICATION, &token, dispatch_get_main_queue(), ^(int token) {
            [weakSelf refreshState];
        }) == NOTIFY_STATUS_OK) {
            _notificationToken = token;
            _observing = YES;
        }
    }
    return self;
}
- (void)dealloc { if (_observing) notify_cancel(_notificationToken); }
- (UIImage *)iconGlyph {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightBold];
    return [UIImage systemImageNamed:@"hand.tap" withConfiguration:configuration];
}
- (UIColor *)selectedColor { return UIColor.blackColor; }
- (BOOL)isSelected { return [STLoadPreferences()[@"isEnabled"] boolValue]; }
- (void)setSelected:(BOOL)selected {
    NSError *error = nil;
    if (!STWritePreferences(@{@"isEnabled": @(selected)}, &error))
        NSLog(@"[ShowTouch] Could not save Control Center toggle: %@", error.localizedDescription);
    [self refreshState];
}
@end
