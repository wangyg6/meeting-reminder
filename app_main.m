#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSTask *monitorTask;
@property (strong) NSStatusItem *statusItem;
@property (strong) NSMenuItem *statusMenuItem;
@property (strong) id preferencesController;
- (void)reloadConfig:(id)sender;
@end

@interface PreferencesWindowController : NSWindowController
@property (weak) AppDelegate *appDelegate;
- (instancetype)initWithConfigPath:(NSString *)configPath
                       defaultPath:(NSString *)defaultPath;
- (void)showPreferences;
@end

@implementation AppDelegate

- (NSString *)resourcesPath {
    return [[NSBundle mainBundle] resourcePath];
}

- (NSString *)configPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Application Support/MeetingReminder/config.json"];
}

- (NSString *)defaultConfigPath {
    return [[self resourcesPath] stringByAppendingPathComponent:@"config.default.json"];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSString *dir = [[self configPath] stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    if (![[NSFileManager defaultManager] fileExistsAtPath:[self configPath]]) {
        [[NSFileManager defaultManager] copyItemAtPath:[self defaultConfigPath]
                                                toPath:[self configPath]
                                                 error:nil];
    }

    self.preferencesController = [[PreferencesWindowController alloc]
        initWithConfigPath:[self configPath]
               defaultPath:[self defaultConfigPath]];
    ((PreferencesWindowController *)self.preferencesController).appDelegate = self;

    [self setupStatusBarIcon];
    [self setupStatusBar];
    [self startMonitor];
}

- (NSImage *)scaledStatusBarIcon:(NSImage *)source size:(CGFloat)size {
    NSImage *scaled = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [scaled lockFocus];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    NSSize src = source.size;
    CGFloat scale = MIN(size / src.width, size / src.height);
    CGFloat w = src.width * scale;
    CGFloat h = src.height * scale;
    CGFloat x = (size - w) / 2.0;
    CGFloat y = (size - h) / 2.0;
    [source drawInRect:NSMakeRect(x, y, w, h)
              fromRect:NSZeroRect
             operation:NSCompositingOperationCopy
              fraction:1.0
        respectFlipped:YES
                 hints:nil];
    [scaled unlockFocus];
    scaled.template = NO;
    return scaled;
}

- (void)setupStatusBarIcon {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSImage *icon = [NSImage imageNamed:@"AppIcon"];
    if (!icon) {
        NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
        if (iconPath) icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
    }
    if (icon) {
        self.statusItem.button.image = [self scaledStatusBarIcon:icon size:18.0];
        self.statusItem.button.imagePosition = NSImageLeading;
    } else {
        self.statusItem.button.title = @"🐬";
    }
    if (@available(macOS 10.14, *)) {
        self.statusItem.button.toolTip = @"Meeting Reminder";
    }
}

- (void)setupStatusBar {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Meeting Reminder"];

    self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"状态：启动中..."
                                                     action:nil
                                              keyEquivalent:@""];
    self.statusMenuItem.enabled = NO;
    [menu addItem:self.statusMenuItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *prefs = [[NSMenuItem alloc] initWithTitle:@"偏好设置..."
                                                    action:@selector(openPreferences:)
                                             keyEquivalent:@","];
    prefs.target = self;
    [menu addItem:prefs];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *scanNow = [[NSMenuItem alloc] initWithTitle:@"立即扫描日历"
                                                     action:@selector(scanNow:)
                                              keyEquivalent:@"r"];
    scanNow.target = self;
    [menu addItem:scanNow];

    NSMenuItem *testBanner = [[NSMenuItem alloc] initWithTitle:@"测试横幅"
                                                        action:@selector(testBanner:)
                                                 keyEquivalent:@"b"];
    testBanner.target = self;
    [menu addItem:testBanner];

    NSMenuItem *testCal = [[NSMenuItem alloc] initWithTitle:@"测试日历权限"
                                                     action:@selector(testCalendar:)
                                              keyEquivalent:@""];
    testCal.target = self;
    [menu addItem:testCal];

    NSMenuItem *openLog = [[NSMenuItem alloc] initWithTitle:@"打开日志"
                                                     action:@selector(openLog:)
                                              keyEquivalent:@"l"];
    openLog.target = self;
    [menu addItem:openLog];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出"
                                                  action:@selector(quitApp:)
                                           keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];

    self.statusItem.menu = menu;

    // App menu: Preferences standard shortcut
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Meeting Reminder"];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    appMenuItem.submenu = appMenu;
    [appMenu addItemWithTitle:@"偏好设置..."
                       action:@selector(openPreferences:)
                keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"退出 Meeting Reminder"
                       action:@selector(quitApp:)
                keyEquivalent:@"q"];

    NSMenu *mainMenu = [[NSMenu alloc] init];
    [mainMenu addItem:appMenuItem];
    [NSApp setMainMenu:mainMenu];
}

- (void)configureTask:(NSTask *)task withArgs:(NSArray<NSString *> *)extraArgs {
    NSString *script = [[self resourcesPath] stringByAppendingPathComponent:@"meeting_reminder.py"];
    NSMutableArray *args = [NSMutableArray arrayWithObject:script];
    [args addObjectsFromArray:extraArgs];

    task.launchPath = @"/usr/bin/python3";
    task.arguments = args;
    task.currentDirectoryPath = [self resourcesPath];

    NSMutableDictionary *env = [[[NSProcessInfo processInfo] environment] mutableCopy];
    env[@"MEETING_REMINDER_RESOURCES"] = [self resourcesPath];
    task.environment = env;

    NSString *logPath = @"/tmp/meeting-reminder.log";
    if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
    }
    NSFileHandle *logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    [logHandle seekToEndOfFile];
    task.standardOutput = logHandle;
    task.standardError = logHandle;
}

- (void)startMonitor {
    if (self.monitorTask && self.monitorTask.isRunning) {
        self.statusMenuItem.title = @"状态：监控中";
        return;
    }

    self.monitorTask = [[NSTask alloc] init];
    [self configureTask:self.monitorTask withArgs:@[]];

    @try {
        [self.monitorTask launch];
        self.statusMenuItem.title = @"状态：监控中";
    } @catch (NSException *exception) {
        self.statusMenuItem.title = @"状态：启动失败";
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法启动监控";
        alert.informativeText = exception.reason ?: @"未知错误";
        [alert runModal];
    }
}

- (void)stopMonitor {
    if (self.monitorTask && self.monitorTask.isRunning) {
        [self.monitorTask terminate];
        [self.monitorTask waitUntilExit];
    }
    self.monitorTask = nil;
    self.statusMenuItem.title = @"状态：已停止";
}

- (void)runPythonAsync:(NSArray<NSString *> *)args {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        [self configureTask:task withArgs:args];
        @try {
            [task launch];
            [task waitUntilExit];
        } @catch (NSException *exception) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"操作失败";
                alert.informativeText = exception.reason ?: @"未知错误";
                [alert runModal];
            });
        }
    });
}

- (void)openPreferences:(id)sender {
    [(PreferencesWindowController *)self.preferencesController showPreferences];
}

- (void)reloadConfig:(id)sender {
    [self stopMonitor];
    [self startMonitor];
}

- (void)scanNow:(id)sender {
    [self runPythonAsync:@[@"--scan-once"]];
}

- (void)testBanner:(id)sender {
    [self runPythonAsync:@[@"--test-banner"]];
}

- (void)testCalendar:(id)sender {
    [self runPythonAsync:@[@"--test-calendar"]];
}

- (void)openLog:(id)sender {
    NSString *logPath = @"/tmp/meeting-reminder.log";
    if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
    }
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:logPath]];
}

- (void)quitApp:(id)sender {
    [self stopMonitor];
    [NSApp terminate:nil];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self openPreferences:sender];
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self stopMonitor];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
