#import "STPreferences.h"
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>
#import <fcntl.h>
#import <sys/file.h>
#import <unistd.h>
#import <errno.h>

static NSString *const STPath = @"/var/mobile/Library/Preferences/com.p-x9.showtouch.pref.plist";

NSDictionary<NSString *, id> *STPreferenceDefaults(void) {
    static NSDictionary *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = @{
            @"isEnabled": @YES, @"radius": @20, @"color": @"AA0000FF",
            @"offset": @[@0, @-10], @"isBordered": @NO,
            @"borderColor": @"000000FF", @"borderWidth": @1,
            @"isDropShadow": @YES, @"shadowColor": @"000000FF",
            @"shadowRadius": @3, @"shadowOffset": @[@0, @0],
            @"isShowLocation": @NO, @"displayMode": @0, @"showRendererSource": @NO
        };
    });
    return defaults;
}

static NSNumber *STFiniteNumber(id value, double low, double high) {
    if (![value isKindOfClass:NSNumber.class]) return nil;
    double number = [value doubleValue];
    return isfinite(number) ? @(fmin(fmax(number, low), high)) : nil;
}

static NSString *STNormalizeHex(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *hex = [value hasPrefix:@"#"] ? [value substringFromIndex:1] : value;
    if (hex.length != 6 && hex.length != 8) return nil;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
    if ([hex rangeOfCharacterFromSet:invalid].location != NSNotFound) return nil;
    return hex.length == 6 ? [hex.uppercaseString stringByAppendingString:@"FF"] : hex.uppercaseString;
}

static id STValidatedValue(NSString *key, id value) {
    if ([key isEqualToString:@"isEnabled"] || [key isEqualToString:@"isBordered"] ||
        [key isEqualToString:@"isDropShadow"] || [key isEqualToString:@"isShowLocation"] ||
        [key isEqualToString:@"showRendererSource"])
        return [value isKindOfClass:NSNumber.class] ? @([value boolValue]) : nil;
    if ([key isEqualToString:@"radius"]) return STFiniteNumber(value, 0, 50);
    if ([key isEqualToString:@"borderWidth"] || [key isEqualToString:@"shadowRadius"])
        return STFiniteNumber(value, 0, 10);
    if ([key isEqualToString:@"color"] || [key isEqualToString:@"borderColor"] ||
        [key isEqualToString:@"shadowColor"]) return STNormalizeHex(value);
    if ([key isEqualToString:@"displayMode"]) {
        if (![value isKindOfClass:NSNumber.class]) return nil;
        double mode = [value doubleValue];
        return mode == 0 || mode == 2 ? @((NSInteger)mode) : nil;
    }
    if ([key isEqualToString:@"offset"] || [key isEqualToString:@"shadowOffset"]) {
        id x = nil, y = nil;
        if ([value isKindOfClass:NSArray.class] && [value count] == 2) {
            x = value[0]; y = value[1];
        } else if ([value isKindOfClass:NSDictionary.class]) {
            x = value[@"x"]; y = value[@"y"];
        }
        x = STFiniteNumber(x, -10000, 10000);
        y = STFiniteNumber(y, -10000, 10000);
        return x && y ? @[x, y] : nil;
    }
    return nil;
}

NSDictionary<NSString *, id> *STLoadPreferences(void) {
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:STPath];
    NSMutableDictionary *result = [stored isKindOfClass:NSDictionary.class] ?
        [stored mutableCopy] : [NSMutableDictionary new];
    NSDictionary *defaults = STPreferenceDefaults();
    for (NSString *key in defaults) {
        // Invalid styling must not reset a valid Enabled=false value.
        result[key] = STValidatedValue(key, result[key]) ?: defaults[key];
    }
    return [result copy];
}

BOOL STWritePreferences(NSDictionary<NSString *, id> *changes, NSError **error) {
    NSMutableDictionary *validated = [NSMutableDictionary new];
    for (NSString *key in changes) {
        id value = STValidatedValue(key, changes[key]);
        if (!value) {
            if (error) *error = [NSError errorWithDomain:@"com.p-x9.showtouch.preferences" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"The setting has an invalid value."}];
            return NO;
        }
        validated[key] = value;
    }
    // Serialize Settings/Control Center writes and merge only edited keys.
    NSString *lockPath = [STPath stringByAppendingString:@".lock"];
    int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
    if (fd < 0 || flock(fd, LOCK_EX) != 0) {
        int failure = errno;
        if (fd >= 0) close(fd);
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:failure userInfo:nil];
        return NO;
    }
    NSMutableDictionary *merged = [STLoadPreferences() mutableCopy];
    [merged addEntriesFromDictionary:validated];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:merged
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    BOOL success = data && [data writeToFile:STPath options:NSDataWritingAtomic error:error];
    flock(fd, LOCK_UN);
    close(fd);
    if (success) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(ST_PREFERENCES_NOTIFICATION), NULL, NULL, true);
    return success;
}

UIColor *STPreferenceColor(NSString *rgba) {
    NSString *hex = STNormalizeHex(rgba) ?: @"AA0000FF";
    unsigned long long value = 0;
    [[NSScanner scannerWithString:hex] scanHexLongLong:&value];
    return [UIColor colorWithRed:((value >> 24) & 255) / 255.0
        green:((value >> 16) & 255) / 255.0 blue:((value >> 8) & 255) / 255.0
        alpha:(value & 255) / 255.0];
}

NSString *STPreferenceHexColor(UIColor *color) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorRef converted = CGColorCreateCopyByMatchingToColorSpace(space,
        kCGRenderingIntentDefault, color.CGColor, NULL);
    CGColorSpaceRelease(space);
    if (!converted) return nil;
    NSString *result = nil;
    if (CGColorGetNumberOfComponents(converted) == 4) {
        const CGFloat *rgba = CGColorGetComponents(converted);
        unsigned int bytes[4];
        BOOL valid = YES;
        for (int i = 0; i < 4; ++i) {
            if (!isfinite(rgba[i])) { valid = NO; break; }
            bytes[i] = (unsigned int)lround(fmin(fmax(rgba[i], 0), 1) * 255);
        }
        if (valid) result = [NSString stringWithFormat:@"%02X%02X%02X%02X", bytes[0], bytes[1], bytes[2], bytes[3]];
    }
    CGColorRelease(converted);
    return result;
}
