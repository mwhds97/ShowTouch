// ShowTouch 0.3.7 compatibility runtime. Original project: p-x9 (MIT).
// Draw only with layers. Never insert a tracking UIView into an app window,
// create marker UIWindows, change a root controller, or poll with a display link.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <math.h>
#import <unistd.h>
#import "STTouchOwnership.h"

// Read-only SpringBoard selector declared in the Theos SpringBoard headers.
// Query it only in SpringBoard, after checking availability; no extra hook.
@interface UIApplication (P9ShowTouchSpringBoardState)
- (id)_accessibilityFrontMostApplication;
@end

@protocol P9ShowTouchApplicationIdentity
- (NSString *)bundleIdentifier;
@end

static NSString *const STPrefsPath = @"/var/mobile/Library/Preferences/com.p-x9.showtouch.pref.plist";
static CFStringRef const STPrefsChanged = CFSTR("com.p-x9.showtouch.prefschanged");

typedef struct {
    BOOL enabled, bordered, shadow, coordinates;
    CGFloat radius, borderWidth, shadowRadius;
    CGPoint offset, shadowOffset;
    uint32_t color, borderColor, shadowColor;
    NSInteger displayMode;
} STSettings;

// This state and all rendering are used exclusively on the main thread.
static STSettings STConfig = { YES, NO, YES, NO, 20, 1, 3, {0, -10}, {0, 0},
                              0xAA0000FF, 0x000000FF, 0x000000FF, 0 };
static BOOL STHookInstalled;
static BOOL STHandlingEvent;
static BOOL STSpringBoardProcess;
static BOOL STShowRendererSource;
static NSUInteger STEventGeneration;
static void (*STOriginalSendEvent)(UIApplication *, SEL, UIEvent *);

// Copy positions before UIKit routes the event through individual windows.
// Do not keep UIEvent objects or strong touch/window references after dispatch.
@interface P9ShowTouchSample : NSObject
@property(nonatomic, weak) UITouch *touch;
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic) CGPoint location;
@end

@implementation P9ShowTouchSample
@end

@interface STTouchMarker : NSObject
@property(nonatomic, weak) UITouch *touch;
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic) CGPoint location;
@property(nonatomic, strong) CAShapeLayer *dot;
@property(nonatomic, strong) CATextLayer *label;
- (void)remove;
@end

@implementation STTouchMarker
- (instancetype)init {
    if ((self = [super init])) {
        _dot = [CAShapeLayer layer];
        _dot.name = @"com.p-x9.showtouch.dot";
        _dot.zPosition = 1000000;
        _label = [CATextLayer layer];
        _label.name = @"com.p-x9.showtouch.coordinates";
        _label.zPosition = 1000001;
        _label.fontSize = 10;
        _label.alignmentMode = kCAAlignmentCenter;
    }
    return self;
}
- (void)remove {
    [_dot removeFromSuperlayer];
    [_label removeFromSuperlayer];
}
- (void)dealloc {
    // The window owns its sublayers independently of this marker object.
    // Never leave a dot or coordinate label behind if a marker is discarded.
    [_dot removeFromSuperlayer];
    [_label removeFromSuperlayer];
}
@end

static NSMutableDictionary<NSValue *, STTouchMarker *> *STMarkers;

static CGFloat STNumber(id value, CGFloat fallback, CGFloat low, CGFloat high) {
    if (![value isKindOfClass:NSNumber.class]) return fallback;
    double number = [value doubleValue];
    return isfinite(number) ? (CGFloat)fmin(fmax(number, low), high) : fallback;
}

static BOOL STBool(id value, BOOL fallback) {
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}

static CGPoint STPoint(id value, CGPoint fallback) {
    // Swift's CGPoint Codable format is [x, y]. Also accept explicit x/y keys.
    id x = nil, y = nil;
    if ([value isKindOfClass:NSArray.class] && [value count] == 2) {
        x = value[0]; y = value[1];
    } else if ([value isKindOfClass:NSDictionary.class]) {
        x = value[@"x"]; y = value[@"y"];
    }
    return CGPointMake(STNumber(x, fallback.x, -10000, 10000),
                       STNumber(y, fallback.y, -10000, 10000));
}

static uint32_t STHex(id value, uint32_t fallback) {
    if (![value isKindOfClass:NSString.class]) return fallback;
    NSString *hex = [value hasPrefix:@"#"] ? [value substringFromIndex:1] : value;
    if (hex.length != 6 && hex.length != 8) return fallback;
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
    if ([hex rangeOfCharacterFromSet:bad].location != NSNotFound) return fallback;
    unsigned long long number = 0;
    if (![[NSScanner scannerWithString:hex] scanHexLongLong:&number]) return fallback;
    return hex.length == 6 ? ((uint32_t)number << 8) | 0xFF : (uint32_t)number;
}

static UIColor *STColor(uint32_t rgba) {
    return [UIColor colorWithRed:((rgba >> 24) & 0xFF) / 255.0
                           green:((rgba >> 16) & 0xFF) / 255.0
                            blue:((rgba >> 8) & 0xFF) / 255.0
                           alpha:(rgba & 0xFF) / 255.0];
}

static void STReadPreferences(void) {
    NSDictionary *values = [NSDictionary dictionaryWithContentsOfFile:STPrefsPath];
    if (![values isKindOfClass:NSDictionary.class]) return; // retain last valid state
    // Decode fields independently: malformed styling must never reset Enabled.
    STConfig.enabled = STBool(values[@"isEnabled"], STConfig.enabled);
    STConfig.radius = STNumber(values[@"radius"], STConfig.radius, 0, 50);
    STConfig.color = STHex(values[@"color"], STConfig.color);
    STConfig.offset = STPoint(values[@"offset"], STConfig.offset);
    STConfig.bordered = STBool(values[@"isBordered"], STConfig.bordered);
    STConfig.borderColor = STHex(values[@"borderColor"], STConfig.borderColor);
    STConfig.borderWidth = STNumber(values[@"borderWidth"], STConfig.borderWidth, 0, 10);
    STConfig.shadow = STBool(values[@"isDropShadow"], STConfig.shadow);
    STConfig.shadowColor = STHex(values[@"shadowColor"], STConfig.shadowColor);
    STConfig.shadowRadius = STNumber(values[@"shadowRadius"], STConfig.shadowRadius, 0, 10);
    STConfig.shadowOffset = STPoint(values[@"shadowOffset"], STConfig.shadowOffset);
    STConfig.coordinates = STBool(values[@"isShowLocation"], STConfig.coordinates);
    STShowRendererSource = STBool(values[@"showRendererSource"], STShowRendererSource);
    id mode = values[@"displayMode"];
    if ([mode isKindOfClass:NSNumber.class]) {
        NSInteger raw = [mode integerValue];
        if (raw >= 0 && raw <= 2) STConfig.displayMode = raw;
    }
}

static BOOL STShouldDisplay(UIWindow *window) {
    if (!STConfig.enabled || !window || window.hidden ||
        UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) return NO;
    if (STConfig.displayMode == 2) return window.screen.isCaptured;
    if (STConfig.displayMode == 1) {
#if DEBUG
        return YES;
#else
        return NO;
#endif
    }
    return YES;
}

static STTouchOwnership STCurrentOwnership(void) {
    STTouchOwnership owner = { STSpringBoardProcess, false, false };
    if (!owner.springBoard) return owner;
    UIApplication *application = UIApplication.sharedApplication;
    if (![application respondsToSelector:@selector(_accessibilityFrontMostApplication)]) {
        static BOOL reported;
        if (!reported) {
            reported = YES;
            NSLog(@"[ShowTouch 0.3.7] SpringBoard foreground query is unavailable.");
        }
        return owner;
    }
    owner.foregroundKnown = true;
    id<P9ShowTouchApplicationIdentity, NSObject> foreground = [application _accessibilityFrontMostApplication];
    owner.foreignAppForeground = foreground != nil;
    if ([foreground respondsToSelector:@selector(bundleIdentifier)] &&
        [[foreground bundleIdentifier] isEqualToString:@"com.apple.springboard"])
        owner.foreignAppForeground = false;
    return owner;
}

static BOOL STObjectIsSystemUI(id object) {
    for (Class type = object_getClass(object); type; type = class_getSuperclass(type))
        if (STTouchIsSystemUIClass(class_getName(type))) return YES;
    return NO;
}

static BOOL STTouchTargetsSystemUI(UITouch *touch, UIWindow *window) {
    if (STObjectIsSystemUI(window)) return YES;
    UIResponder *responder = touch.view;
    // Bound the traversal, including a defensive check for a self-loop.
    for (NSUInteger depth = 0; responder && depth < 64; ++depth) {
        if (STObjectIsSystemUI(responder)) return YES;
        UIResponder *next = responder.nextResponder;
        if (next == responder) break;
        responder = next;
    }
    return NO;
}

static BOOL STMayDrawTouch(UITouch *touch, UIWindow *window, STTouchOwnership owner) {
    if (!touch || !window || touch.window != window || !STShouldDisplay(window)) return NO;
    if (STTouchOwnershipAllows(owner, false)) return YES;
    return STTouchOwnershipAllows(owner, STTouchTargetsSystemUI(touch, window));
}

static void STRemoveKey(NSValue *key) {
    [STMarkers[key] remove];
    [STMarkers removeObjectForKey:key];
}

static void STClearMarkers(void) {
    // An interruption during event delivery invalidates its pending drawing.
    ++STEventGeneration;
    for (STTouchMarker *marker in STMarkers.allValues) [marker remove];
    [STMarkers removeAllObjects];
}

static void STPruneMarkers(void) {
    STTouchOwnership owner = STCurrentOwnership();
    for (NSValue *key in STMarkers.allKeys) {
        STTouchMarker *marker = STMarkers[key];
        UITouch *touch = marker.touch;
        UIWindow *window = marker.window;
        if (!STMayDrawTouch(touch, window, owner) ||
            touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
            STRemoveKey(key);
        }
    }
}

static void STDrawMarker(STTouchMarker *marker) {
    UIWindow *window = marker.window;
    if (!window) return;
    CGFloat radius = STConfig.radius;
    CGPoint center = CGPointMake(marker.location.x + STConfig.offset.x,
                                 marker.location.y + STConfig.offset.y);
    CGRect bounds = CGRectMake(0, 0, radius * 2, radius * 2);
    CAShapeLayer *dot = marker.dot;
    dot.bounds = bounds;
    dot.position = center;
    dot.path = [UIBezierPath bezierPathWithOvalInRect:bounds].CGPath;
    dot.fillColor = STColor(STConfig.color).CGColor;
    dot.strokeColor = STConfig.bordered ? STColor(STConfig.borderColor).CGColor : NULL;
    dot.lineWidth = STConfig.borderWidth;
    // Core Animation ignores shadowColor's alpha, so transfer it to opacity.
    dot.shadowColor = [STColor(STConfig.shadowColor) colorWithAlphaComponent:1].CGColor;
    dot.shadowOpacity = STConfig.shadow ? (STConfig.shadowColor & 0xFF) / 255.0f : 0;
    dot.shadowRadius = STConfig.shadowRadius;
    dot.shadowOffset = CGSizeMake(STConfig.shadowOffset.x, STConfig.shadowOffset.y);
    dot.shadowPath = dot.path;
    dot.contentsScale = window.screen.scale;
    if (dot.superlayer != window.layer) [window.layer addSublayer:dot];

    CATextLayer *label = marker.label;
    if (STConfig.coordinates || STShowRendererSource) {
        label.contentsScale = window.screen.scale;
        label.foregroundColor = [UIColor.labelColor resolvedColorWithTraitCollection:window.traitCollection].CGColor;
        if (STShowRendererSource) {
            NSString *source = [NSString stringWithFormat:@"0.3.7 %@ (%d)\n%@ %p\ntouch %p",
                NSProcessInfo.processInfo.processName, getpid(), NSStringFromClass(window.class),
                (__bridge void *)window, (__bridge void *)marker.touch];
            if (STConfig.coordinates) source = [source stringByAppendingFormat:@"\nx: %.1f  y: %.1f",
                marker.location.x, marker.location.y];
            label.string = source;
            label.fontSize = 9;
            label.wrapped = YES;
            label.backgroundColor = [[UIColor.secondarySystemBackgroundColor
                resolvedColorWithTraitCollection:window.traitCollection] colorWithAlphaComponent:0.9].CGColor;
            CGFloat width = fmin(320, CGRectGetWidth(window.bounds));
            CGFloat height = fmin(STConfig.coordinates ? 74 : 60, CGRectGetHeight(window.bounds));
            CGFloat x = fmax(CGRectGetMinX(window.bounds), fmin(center.x - width / 2,
                CGRectGetMaxX(window.bounds) - width));
            CGFloat y = fmax(CGRectGetMinY(window.bounds), fmin(center.y - radius - height - 4,
                CGRectGetMaxY(window.bounds) - height));
            label.frame = CGRectMake(x, y, width, height);
        } else {
            label.string = [NSString stringWithFormat:@"x: %.1f\ny: %.1f", marker.location.x, marker.location.y];
            label.fontSize = 10;
            label.wrapped = NO;
            label.backgroundColor = NULL;
            label.frame = CGRectMake(center.x - 55, center.y - radius - STConfig.shadowRadius - 28, 110, 28);
        }
        if (label.superlayer != window.layer) [window.layer addSublayer:label];
    } else {
        [label removeFromSuperlayer];
    }
}

static NSDictionary<NSValue *, P9ShowTouchSample *> *STCaptureTouches(UIEvent *event) {
    NSSet<UITouch *> *touches = event.allTouches;
    if (!touches) return nil; // No authoritative touch data in this event.
    NSMutableDictionary *samples = [NSMutableDictionary new];
    for (UITouch *touch in touches) {
        if (touch.phase != UITouchPhaseBegan && touch.phase != UITouchPhaseMoved &&
            touch.phase != UITouchPhaseStationary) continue;
        UIWindow *window = touch.window;
        if (!window) continue;
        CGPoint location = [touch locationInView:window];
        if (!isfinite(location.x) || !isfinite(location.y)) continue;
        P9ShowTouchSample *sample = [P9ShowTouchSample new];
        sample.touch = touch;
        sample.window = window;
        sample.location = location;
        samples[[NSValue valueWithPointer:(__bridge const void *)touch]] = sample;
    }
    return samples;
}

static void STRenderTouches(NSDictionary<NSValue *, P9ShowTouchSample *> *samples) {
    // Query after original dispatch: opening an app can change foreground owner.
    STTouchOwnership owner = STCurrentOwnership();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    // Reconcile every window against one application-level touch snapshot.
    // Per-window callbacks must not leave an independent marker at touch-down.
    for (NSValue *key in STMarkers.allKeys) {
        STTouchMarker *marker = STMarkers[key];
        P9ShowTouchSample *sample = samples[key];
        if (!sample || !sample.touch || !sample.window ||
            marker.touch != sample.touch || marker.window != sample.window ||
            !STMayDrawTouch(sample.touch, sample.window, owner)) STRemoveKey(key);
    }
    for (NSValue *key in samples) {
        P9ShowTouchSample *sample = samples[key];
        UITouch *touch = sample.touch;
        UIWindow *window = sample.window;
        if (!STMayDrawTouch(touch, window, owner)) continue;
        STTouchMarker *marker = STMarkers[key];
        if (!marker) {
            marker = [STTouchMarker new];
            marker.touch = touch;
            marker.window = window;
            if (!STMarkers) STMarkers = [NSMutableDictionary new];
            STMarkers[key] = marker;
        }
        marker.location = sample.location;
        STDrawMarker(marker);
    }
    [CATransaction commit];
}

static void STSendEvent(UIApplication *application, SEL selector, UIEvent *event) {
    if (!NSThread.isMainThread || !STConfig.enabled ||
        event.type != UIEventTypeTouches || STHandlingEvent) {
        STOriginalSendEvent(application, selector, event);
        return;
    }
    NSUInteger generation = ++STEventGeneration;
    STHandlingEvent = YES;
    NSDictionary *samples = STCaptureTouches(event);
    STHandlingEvent = NO;

    // Deliver the original event exactly once; never replace or synthesize input.
    STOriginalSendEvent(application, selector, event);

    // UIKit or another hook may dispatch a newer event, disable the tweak, or
    // interrupt the app synchronously. Never paint an older snapshot over it.
    if (!samples || !STConfig.enabled || generation != STEventGeneration) return;
    STHandlingEvent = YES;
    STRenderTouches(samples);
    STHandlingEvent = NO;
}

static void STApplySettings(void) {
    if (!STConfig.enabled) { STClearMarkers(); return; }
    if (!STHookInstalled) {
        // Substrate preserves the hook chain; do not exchange method selectors.
        MSHookMessageEx(UIApplication.class, @selector(sendEvent:), (IMP)STSendEvent, (IMP *)&STOriginalSendEvent);
        STHookInstalled = YES;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    STPruneMarkers();
    for (STTouchMarker *marker in STMarkers.allValues) STDrawMarker(marker);
    [CATransaction commit];
}

static void STPreferencesChanged(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        STReadPreferences();
        STApplySettings();
    });
}

__attribute__((constructor)) static void STInitialize(void) {
    STSpringBoardProcess = [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                   STPreferencesChanged, STPrefsChanged, NULL,
                                   CFNotificationSuspensionBehaviorDeliverImmediately);
    dispatch_async(dispatch_get_main_queue(), ^{
        STReadPreferences();
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        // These process-lifetime observers hold no views or controllers.
        for (NSNotificationName name in @[UIApplicationWillResignActiveNotification,
                UIApplicationDidEnterBackgroundNotification,
                UIDeviceOrientationDidChangeNotification,
                UIScreenCapturedDidChangeNotification]) {
            [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                            usingBlock:^(NSNotification *note) { STClearMarkers(); }];
        }
        [center addObserverForName:UIWindowDidBecomeHiddenNotification object:nil
                             queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            for (NSValue *key in STMarkers.allKeys) {
                if (STMarkers[key].window == note.object) STRemoveKey(key);
            }
        }];
        STApplySettings();
    });
}
