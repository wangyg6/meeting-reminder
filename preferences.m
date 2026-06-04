#import <Cocoa/Cocoa.h>

@class AppDelegate;

@interface AppDelegate : NSObject
- (void)reloadConfig:(id)sender;
@end

@interface PreferencesWindowController : NSWindowController
@property (assign) AppDelegate *appDelegate;
@property (copy) NSString *configPath;
@property (copy) NSString *defaultConfigPath;

@property (strong) NSTextField *reminderMinutesField;
@property (strong) NSTextField *pollIntervalField;
@property (strong) NSTextField *bannerDurationField;
@property (strong) NSButton *onlyMeetingsCheck;
@property (strong) NSButton *requireLocationCheck;
@property (strong) NSTextField *titleKeywordsField;
@property (strong) NSTextField *excludeKeywordsField;
@property (strong) NSTextField *calendarNamesField;

- (instancetype)initWithConfigPath:(NSString *)configPath
                       defaultPath:(NSString *)defaultPath;
- (void)showPreferences;
@end

static NSTextField *labeledField(NSString *label, NSView *parent, CGFloat *y) {
    NSTextField *title = [NSTextField labelWithString:label];
    title.frame = NSMakeRect(20, *y, 440, 18);
    [parent addSubview:title];
    *y -= 26;

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(20, *y, 440, 24)];
    field.bezeled = YES;
    field.editable = YES;
    field.selectable = YES;
    [parent addSubview:field];
    *y -= 34;
    return field;
}

static NSButton *labeledCheck(NSString *label, NSView *parent, CGFloat *y) {
    NSButton *check = [[NSButton alloc] initWithFrame:NSMakeRect(20, *y, 440, 22)];
    check.buttonType = NSButtonTypeSwitch;
    check.title = label;
    check.state = NSControlStateValueOff;
    [parent addSubview:check];
    *y -= 30;
    return check;
}

static NSString *joinArray(id value) {
    if (![value isKindOfClass:[NSArray class]]) return @"";
    return [(NSArray *)value componentsJoinedByString:@", "];
}

static NSArray<NSString *> *splitList(NSString *text) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *part in [text componentsSeparatedByString:@","]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [items addObject:trimmed];
    }
    return items;
}

@implementation PreferencesWindowController

- (instancetype)initWithConfigPath:(NSString *)configPath
                       defaultPath:(NSString *)defaultPath {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 560)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"偏好设置"];
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        _configPath = [configPath copy];
        _defaultConfigPath = [defaultPath copy];
        [self buildUI];
        [self loadFromDisk];
    }
    return self;
}

- (void)buildUI {
    NSView *content = self.window.contentView;
    CGFloat y = 520;

    NSTextField *header = [NSTextField labelWithString:@"提醒"];
    header.font = [NSFont boldSystemFontOfSize:13];
    header.frame = NSMakeRect(20, y, 200, 20);
    [content addSubview:header];
    y -= 28;

    self.reminderMinutesField = labeledField(@"提前提醒（分钟）", content, &y);
    self.pollIntervalField = labeledField(@"扫描间隔（秒）", content, &y);

    NSTextField *bannerHeader = [NSTextField labelWithString:@"横幅"];
    bannerHeader.font = [NSFont boldSystemFontOfSize:13];
    bannerHeader.frame = NSMakeRect(20, y, 200, 20);
    [content addSubview:bannerHeader];
    y -= 28;

    self.bannerDurationField = labeledField(@"飘过速度（秒，越大越慢）", content, &y);

    NSTextField *filterHeader = [NSTextField labelWithString:@"会议筛选"];
    filterHeader.font = [NSFont boldSystemFontOfSize:13];
    filterHeader.frame = NSMakeRect(20, y, 200, 20);
    [content addSubview:filterHeader];
    y -= 28;

    self.onlyMeetingsCheck = labeledCheck(@"仅提醒会议（过滤个人日程）", content, &y);
    self.requireLocationCheck = labeledCheck(@"必须有会议室/地点才提醒", content, &y);
    self.titleKeywordsField = labeledField(@"标题包含关键词（逗号分隔）", content, &y);
    self.excludeKeywordsField = labeledField(@"排除关键词（逗号分隔）", content, &y);
    self.calendarNamesField = labeledField(@"指定日历（留空=全部，逗号分隔）", content, &y);

    NSButton *saveBtn = [NSButton buttonWithTitle:@"保存并生效"
                                           target:self
                                           action:@selector(save:)];
    saveBtn.frame = NSMakeRect(280, 16, 110, 32);
    saveBtn.bezelStyle = NSBezelStyleRounded;
    saveBtn.keyEquivalent = @"\r";
    [content addSubview:saveBtn];

    NSButton *cancelBtn = [NSButton buttonWithTitle:@"取消"
                                             target:self
                                             action:@selector(cancel:)];
    cancelBtn.frame = NSMakeRect(390, 16, 70, 32);
    cancelBtn.bezelStyle = NSBezelStyleRounded;
    cancelBtn.keyEquivalent = @"\e";
    [content addSubview:cancelBtn];
}

- (NSMutableDictionary *)readJSONAtPath:(NSString *)path fallback:(NSString *)fallbackPath {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length && fallbackPath.length) {
        data = [NSData dataWithContentsOfFile:fallbackPath];
    }
    if (!data.length) {
        return [@{
            @"poll_interval_seconds": @60,
            @"reminder_minutes_before": @5,
            @"banner_duration_seconds": @12,
            @"only_meetings": @YES,
            @"require_location": @NO,
            @"title_keywords": @[@"会议", @"Meeting"],
            @"exclude_keywords": @[@"生日", @"健身"],
            @"calendar_names": @[]
        } mutableCopy];
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    if ([json isKindOfClass:[NSDictionary class]]) {
        return [json mutableCopy];
    }
    return [NSMutableDictionary dictionary];
}

- (void)loadFromDisk {
    NSMutableDictionary *cfg = [self readJSONAtPath:self.configPath fallback:self.defaultConfigPath];
    self.reminderMinutesField.stringValue = [NSString stringWithFormat:@"%@", cfg[@"reminder_minutes_before"] ?: @5];
    self.pollIntervalField.stringValue = [NSString stringWithFormat:@"%@", cfg[@"poll_interval_seconds"] ?: @60];
    self.bannerDurationField.stringValue = [NSString stringWithFormat:@"%@", cfg[@"banner_duration_seconds"] ?: @12];
    self.onlyMeetingsCheck.state = [cfg[@"only_meetings"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.requireLocationCheck.state = [cfg[@"require_location"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.titleKeywordsField.stringValue = joinArray(cfg[@"title_keywords"]);
    self.excludeKeywordsField.stringValue = joinArray(cfg[@"exclude_keywords"]);
    self.calendarNamesField.stringValue = joinArray(cfg[@"calendar_names"]);
}

- (BOOL)validateFields:(int *)outReminder
                 poll:(int *)outPoll
               banner:(int *)outBanner
                 error:(NSString **)error {
    int reminder = self.reminderMinutesField.stringValue.intValue;
    int poll = self.pollIntervalField.stringValue.intValue;
    int banner = self.bannerDurationField.stringValue.intValue;

    if (reminder < 1 || reminder > 60) {
        *error = @"提前提醒需在 1–60 分钟之间";
        return NO;
    }
    if (poll < 15 || poll > 600) {
        *error = @"扫描间隔需在 15–600 秒之间";
        return NO;
    }
    if (banner < 4 || banner > 60) {
        *error = @"横幅速度需在 4–60 秒之间";
        return NO;
    }
    *outReminder = reminder;
    *outPoll = poll;
    *outBanner = banner;
    return YES;
}

- (void)save:(id)sender {
    int reminder, poll, banner;
    NSString *error = nil;
    if (![self validateFields:&reminder poll:&poll banner:&banner error:&error]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"配置无效";
        alert.informativeText = error;
        [alert runModal];
        return;
    }

    NSMutableDictionary *cfg = [self readJSONAtPath:self.configPath fallback:self.defaultConfigPath];
    cfg[@"reminder_minutes_before"] = @(reminder);
    cfg[@"poll_interval_seconds"] = @(poll);
    cfg[@"banner_duration_seconds"] = @(banner);
    cfg[@"only_meetings"] = @(self.onlyMeetingsCheck.state == NSControlStateValueOn);
    cfg[@"require_location"] = @(self.requireLocationCheck.state == NSControlStateValueOn);
    cfg[@"title_keywords"] = splitList(self.titleKeywordsField.stringValue);
    cfg[@"exclude_keywords"] = splitList(self.excludeKeywordsField.stringValue);
    cfg[@"calendar_names"] = splitList(self.calendarNamesField.stringValue);

    NSString *dir = [self.configPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSData *data = [NSJSONSerialization dataWithJSONObject:cfg
                                                     options:NSJSONWritingPrettyPrinted
                                                       error:nil];
    if (![data writeToFile:self.configPath atomically:YES]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"保存失败";
        alert.informativeText = @"无法写入配置文件";
        [alert runModal];
        return;
    }

    [self.window orderOut:sender];
    if (self.appDelegate) {
        [self.appDelegate reloadConfig:sender];
    }
}

- (void)cancel:(id)sender {
    [self.window orderOut:sender];
}

- (void)showPreferences {
    [self loadFromDisk];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

@end
