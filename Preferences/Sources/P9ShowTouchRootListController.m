#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import <math.h>
#import "STPreferences.h"

@interface P9ShowTouchRootListController : PSListController <UIColorPickerViewControllerDelegate>
@property(nonatomic, copy) NSDictionary *values;
@property(nonatomic, copy) NSString *colorKey;
@property(nonatomic, copy) NSString *offsetKey;
@property(nonatomic, strong) UIAlertController *offsetAlert;
@property(nonatomic) int notificationToken;
@property(nonatomic) BOOL observing;
@end

@implementation P9ShowTouchRootListController
- (NSMutableArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ShowTouch";
    if (!self.values) self.values = STLoadPreferences();
    __weak P9ShowTouchRootListController *weakSelf = self;
    int token;
    if (notify_register_dispatch(ST_PREFERENCES_NOTIFICATION, &token, dispatch_get_main_queue(), ^(int token) {
        [weakSelf refreshPreferences];
    }) == NOTIFY_STATUS_OK) {
        self.notificationToken = token;
        self.observing = YES;
    }
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshPreferences];
}
- (void)dealloc { if (_observing) notify_cancel(_notificationToken); }
- (void)refreshPreferences {
    NSDictionary *previous = self.values;
    self.values = STLoadPreferences();
    if (!self.isViewLoaded || !previous) return;
    for (NSString *key in STPreferenceDefaults()) {
        // Our own writes already updated values. Do not rebuild a slider mid-drag.
        if (![previous[key] isEqual:self.values[key]]) [self reloadSpecifierID:key animated:NO];
    }
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    if (!self.values) self.values = STLoadPreferences();
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return nil;
    id value = self.values[key];
    if ([[specifier propertyForKey:@"stEditor"] isEqualToString:@"point"])
        return [NSString stringWithFormat:@"x: %@, y: %@", value[0], value[1]];
    if ([[specifier propertyForKey:@"stEditor"] isEqualToString:@"color"])
        return [@"#" stringByAppendingString:value];
    return value;
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key && value) [self saveValue:value forKey:key];
}
- (BOOL)saveValue:(id)value forKey:(NSString *)key {
    NSError *error = nil;
    BOOL success = STWritePreferences(@{key: value}, &error);
    self.values = STLoadPreferences();
    if (!success) {
        [self reloadSpecifierID:key animated:NO];
        if (!self.presentedViewController) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn’t Save Setting"
                message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        } else {
            NSLog(@"[ShowTouch] Could not save setting: %@", error.localizedDescription);
        }
    }
    return success;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([specifier propertyForKey:@"stEditor"] || [specifier propertyForKey:@"stURL"]) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *editor = [specifier propertyForKey:@"stEditor"];
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *url = [specifier propertyForKey:@"stURL"];
    if (editor || url) [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([editor isEqualToString:@"color"]) {
        self.colorKey = key;
        UIColorPickerViewController *picker = [UIColorPickerViewController new];
        picker.title = specifier.name;
        picker.supportsAlpha = YES;
        picker.selectedColor = STPreferenceColor(self.values[key]);
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    } else if ([editor isEqualToString:@"point"]) {
        [self editOffset:key title:specifier.name];
    } else if (url) {
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
    } else {
        [super tableView:tableView didSelectRowAtIndexPath:indexPath];
    }
}
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    NSString *hex = STPreferenceHexColor(viewController.selectedColor);
    if (self.colorKey && hex && [self saveValue:hex forKey:self.colorKey])
        [self reloadSpecifierID:self.colorKey animated:NO];
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    self.colorKey = nil;
}

static BOOL STParseOffset(NSString *text, double *value) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    for (NSLocale *locale in @[NSLocale.currentLocale, [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]]) {
        NSScanner *scanner = [NSScanner scannerWithString:trimmed];
        scanner.locale = locale;
        double number;
        if ([scanner scanDouble:&number] && scanner.isAtEnd && isfinite(number) &&
            number >= -10000 && number <= 10000) {
            *value = number;
            return YES;
        }
    }
    return NO;
}
- (NSArray *)editedOffset {
    if (self.offsetAlert.textFields.count != 2) return nil;
    double x, y;
    if (!STParseOffset(self.offsetAlert.textFields[0].text, &x) ||
        !STParseOffset(self.offsetAlert.textFields[1].text, &y)) return nil;
    return @[@(x), @(y)];
}
- (void)offsetChanged:(UITextField *)sender {
    self.offsetAlert.preferredAction.enabled = [self editedOffset] != nil;
}
- (void)editOffset:(NSString *)key title:(NSString *)title {
    self.offsetKey = key;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:@"Enter x and y in points (−10000 to 10000)." preferredStyle:UIAlertControllerStyleAlert];
    self.offsetAlert = alert;
    NSArray *point = self.values[key];
    __weak P9ShowTouchRootListController *weakSelf = self;
    for (NSUInteger index = 0; index < 2; ++index) {
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = index == 0 ? @"x" : @"y";
            field.accessibilityLabel = field.placeholder;
            field.text = [point[index] stringValue];
            field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            [field addTarget:weakSelf action:@selector(offsetChanged:) forControlEvents:UIControlEventEditingChanged];
        }];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        weakSelf.offsetAlert = nil;
        weakSelf.offsetKey = nil;
    }]];
    UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        P9ShowTouchRootListController *controller = weakSelf;
        NSArray *value = [controller editedOffset];
        NSString *editedKey = controller.offsetKey;
        controller.offsetAlert = nil;
        controller.offsetKey = nil;
        if (value && editedKey && [controller saveValue:value forKey:editedKey])
            [controller reloadSpecifierID:editedKey animated:NO];
    }];
    [alert addAction:save];
    alert.preferredAction = save;
    [self offsetChanged:nil];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
