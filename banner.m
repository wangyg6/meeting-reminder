#import <Cocoa/Cocoa.h>

static const NSTimeInterval kDefaultFlyDuration = 12.0;
static const CGFloat kSceneHeight = 130.0;
static const CGFloat kDolphinW = 118.0;
static const CGFloat kDolphinH = 86.0;
static const CGFloat kRopeLen = 14.0;

static void fillPath(NSBezierPath *path, NSColor *top, NSColor *bottom) {
    NSGradient *grad = [[NSGradient alloc] initWithStartingColor:top endingColor:bottom];
    [grad drawInBezierPath:path angle:-75];
}

static void setSoftShadow(void) {
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowBlurRadius = 6;
    shadow.shadowOffset = NSMakeSize(0, 2);
    shadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.18];
    [shadow set];
}

static NSTimeInterval readBannerDuration(void) {
    NSString *path = @"/tmp/meeting-reminder-banner-config.json";
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return kDefaultFlyDuration;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([json isKindOfClass:[NSDictionary class]]) {
        NSNumber *n = json[@"duration_seconds"];
        if (n) return MAX(4.0, [n doubleValue]);
    }
    return kDefaultFlyDuration;
}

#pragma mark - Text helpers

static NSFont *bannerTitleFont(void) {
    return [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
}

static NSFont *bannerSubFont(void) {
    return [NSFont systemFontOfSize:16 weight:NSFontWeightMedium];
}

static void measureBannerText(NSString *text, CGFloat *outWidth, CGFloat *outHeight) {
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    CGFloat maxW = 0;
    CGFloat totalH = 0;
    CGFloat lineGap = 4;

    for (NSUInteger i = 0; i < lines.count; i++) {
        NSFont *font = (i == 0) ? bannerTitleFont() : bannerSubFont();
        NSSize sz = [lines[i] sizeWithAttributes:@{NSFontAttributeName: font}];
        maxW = MAX(maxW, sz.width);
        totalH += sz.height;
        if (i > 0) totalH += lineGap;
    }

    *outWidth = MAX(maxW + 52, 200);
    *outHeight = MAX(totalH + 20, 54);
}

static void drawBannerText(NSString *text, NSRect bannerRect) {
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    CGFloat lineGap = 4;
    CGFloat totalH = 0;

    for (NSUInteger i = 0; i < lines.count; i++) {
        NSFont *font = (i == 0) ? bannerTitleFont() : bannerSubFont();
        NSSize sz = [lines[i] sizeWithAttributes:@{NSFontAttributeName: font}];
        totalH += sz.height;
        if (i > 0) totalH += lineGap;
    }

    CGFloat y = bannerRect.origin.y + (bannerRect.size.height - totalH) / 2.0 + 1;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSFont *font = (i == 0) ? bannerTitleFont() : bannerSubFont();
        NSColor *color = (i == 0) ? NSColor.whiteColor
                                  : [NSColor colorWithCalibratedRed:0.88 green:0.95 blue:1.0 alpha:1.0];
        NSDictionary *attrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: color};
        NSSize sz = [lines[i] sizeWithAttributes:attrs];
        NSPoint origin = NSMakePoint(
            bannerRect.origin.x + (bannerRect.size.width - sz.width) / 2.0,
            y
        );
        [lines[i] drawAtPoint:origin withAttributes:attrs];
        y += sz.height + lineGap;
    }
}

#pragma mark - Dolphin + Banner View

@interface DolphinBannerView : NSView
@property (nonatomic, copy) NSString *message;
@end

@implementation DolphinBannerView

- (BOOL)isFlipped {
    return YES;
}

- (void)drawBubble:(NSPoint)center radius:(CGFloat)r alpha:(CGFloat)a {
    NSBezierPath *b = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - r, center.y - r, r * 2, r * 2)];
    [[NSColor colorWithCalibratedRed:0.75 green:0.92 blue:1.0 alpha:a] setFill];
    [b fill];
    [[NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:a * 0.6] setStroke];
    [b setLineWidth:0.8];
    [b stroke];
}

- (void)drawDolphinAtY:(CGFloat)originY {
    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
    [ctx saveGraphicsState];

    NSAffineTransform *xf = [NSAffineTransform transform];
    [xf translateXBy:0 yBy:originY];
    [xf concat];

    // Soft ground shadow
    NSBezierPath *groundShadow = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(18, 72, 78, 10)];
    [[NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:0.10] setFill];
    [groundShadow fill];

    [ctx saveGraphicsState];
    setSoftShadow();

    // --- Unified body silhouette (plump mascot style) ---
    NSBezierPath *body = [NSBezierPath bezierPath];
    [body moveToPoint:NSMakePoint(8, 44)];
    [body curveToPoint:NSMakePoint(28, 22)
         controlPoint1:NSMakePoint(4, 34)
         controlPoint2:NSMakePoint(12, 22)];
    [body curveToPoint:NSMakePoint(62, 16)
         controlPoint1:NSMakePoint(40, 18)
         controlPoint2:NSMakePoint(50, 12)];
    [body curveToPoint:NSMakePoint(96, 28)
         controlPoint1:NSMakePoint(76, 14)
         controlPoint2:NSMakePoint(90, 18)];
    [body curveToPoint:NSMakePoint(104, 42)
         controlPoint1:NSMakePoint(102, 34)
         controlPoint2:NSMakePoint(106, 38)];
    [body curveToPoint:NSMakePoint(88, 58)
         controlPoint1:NSMakePoint(100, 52)
         controlPoint2:NSMakePoint(96, 58)];
    [body curveToPoint:NSMakePoint(48, 66)
         controlPoint1:NSMakePoint(74, 62)
         controlPoint2:NSMakePoint(62, 68)];
    [body curveToPoint:NSMakePoint(18, 58)
         controlPoint1:NSMakePoint(34, 64)
         controlPoint2:NSMakePoint(24, 62)];
    [body curveToPoint:NSMakePoint(8, 44)
         controlPoint1:NSMakePoint(12, 54)
         controlPoint2:NSMakePoint(6, 50)];
    [body closePath];

    fillPath(body,
             [NSColor colorWithCalibratedRed:0.45 green:0.82 blue:1.00 alpha:1.0],
             [NSColor colorWithCalibratedRed:0.12 green:0.58 blue:0.92 alpha:1.0]);
    [[NSColor colorWithCalibratedRed:0.08 green:0.48 blue:0.82 alpha:0.35] setStroke];
    [body setLineWidth:1.2];
    [body stroke];

    [ctx restoreGraphicsState];

    // Belly patch
    NSBezierPath *belly = [NSBezierPath bezierPath];
    [belly moveToPoint:NSMakePoint(34, 52)];
    [belly curveToPoint:NSMakePoint(82, 48)
          controlPoint1:NSMakePoint(50, 62)
          controlPoint2:NSMakePoint(68, 62)];
    [belly curveToPoint:NSMakePoint(34, 52)
          controlPoint1:NSMakePoint(68, 38)
          controlPoint2:NSMakePoint(50, 38)];
    [belly closePath];
    fillPath(belly,
             [NSColor colorWithCalibratedRed:0.97 green:0.99 blue:1.00 alpha:1.0],
             [NSColor colorWithCalibratedRed:0.86 green:0.94 blue:1.00 alpha:1.0]);

    // Dorsal fin
    NSBezierPath *dorsal = [NSBezierPath bezierPath];
    [dorsal moveToPoint:NSMakePoint(50, 20)];
    [dorsal curveToPoint:NSMakePoint(58, 20)
          controlPoint1:NSMakePoint(52, 8)
          controlPoint2:NSMakePoint(56, 8)];
    [dorsal curveToPoint:NSMakePoint(66, 28)
          controlPoint1:NSMakePoint(62, 22)
          controlPoint2:NSMakePoint(66, 26)];
    [dorsal curveToPoint:NSMakePoint(50, 20)
          controlPoint1:NSMakePoint(58, 24)
          controlPoint2:NSMakePoint(52, 22)];
    [dorsal closePath];
    fillPath(dorsal,
             [NSColor colorWithCalibratedRed:0.30 green:0.72 blue:0.98 alpha:1.0],
             [NSColor colorWithCalibratedRed:0.10 green:0.52 blue:0.86 alpha:1.0]);

    // Tail flukes
    NSBezierPath *tail = [NSBezierPath bezierPath];
    [tail moveToPoint:NSMakePoint(12, 42)];
    [tail curveToPoint:NSMakePoint(2, 30)
          controlPoint1:NSMakePoint(4, 40)
          controlPoint2:NSMakePoint(0, 34)];
    [tail curveToPoint:NSMakePoint(10, 42)
          controlPoint1:NSMakePoint(4, 36)
          controlPoint2:NSMakePoint(6, 40)];
    [tail curveToPoint:NSMakePoint(2, 54)
          controlPoint1:NSMakePoint(6, 44)
          controlPoint2:NSMakePoint(4, 50)];
    [tail curveToPoint:NSMakePoint(12, 44)
          controlPoint1:NSMakePoint(0, 58)
          controlPoint2:NSMakePoint(4, 52)];
    [tail closePath];
    fillPath(tail,
             [NSColor colorWithCalibratedRed:0.35 green:0.76 blue:0.99 alpha:1.0],
             [NSColor colorWithCalibratedRed:0.12 green:0.56 blue:0.90 alpha:1.0]);

    // Pectoral fin
    NSBezierPath *fin = [NSBezierPath bezierPath];
    [fin moveToPoint:NSMakePoint(52, 56)];
    [fin curveToPoint:NSMakePoint(44, 72)
         controlPoint1:NSMakePoint(42, 60)
         controlPoint2:NSMakePoint(40, 70)];
    [fin curveToPoint:NSMakePoint(60, 58)
         controlPoint1:NSMakePoint(52, 70)
         controlPoint2:NSMakePoint(58, 62)];
    [fin closePath];
    fillPath(fin,
             [NSColor colorWithCalibratedRed:0.28 green:0.70 blue:0.97 alpha:1.0],
             [NSColor colorWithCalibratedRed:0.10 green:0.52 blue:0.86 alpha:1.0]);

    // Snout highlight
    NSBezierPath *snout = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(92, 34, 14, 10)];
    [[NSColor colorWithCalibratedRed:0.55 green:0.86 blue:1.0 alpha:0.35] setFill];
    [snout fill];

    // --- Face ---
    // Eye white
    NSBezierPath *eyeWhite = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(74, 30, 20, 22)];
    [[NSColor whiteColor] setFill];
    [eyeWhite fill];
    [[NSColor colorWithCalibratedRed:0.08 green:0.45 blue:0.78 alpha:0.25] setStroke];
    [eyeWhite setLineWidth:1.0];
    [eyeWhite stroke];

    // Pupil
    NSBezierPath *pupil = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(81, 36, 10, 12)];
    [[NSColor colorWithCalibratedRed:0.06 green:0.28 blue:0.48 alpha:1.0] setFill];
    [pupil fill];

    // Eye highlights
    [[NSColor whiteColor] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(83, 38, 4, 4)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(88, 42, 2, 2)] fill];

    // Blush
    NSBezierPath *blush = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(88, 46, 12, 7)];
    [[NSColor colorWithCalibratedRed:1.0 green:0.62 blue:0.68 alpha:0.45] setFill];
    [blush fill];

    // Smile
    NSBezierPath *smile = [NSBezierPath bezierPath];
    [[NSColor colorWithCalibratedRed:0.08 green:0.40 blue:0.65 alpha:0.85] setStroke];
    [smile setLineWidth:1.6];
    [smile setLineCapStyle:NSLineCapStyleRound];
    [smile moveToPoint:NSMakePoint(92, 50)];
    [smile curveToPoint:NSMakePoint(102, 50)
          controlPoint1:NSMakePoint(95, 54)
          controlPoint2:NSMakePoint(99, 54)];
    [smile stroke];

    // Water spout
    [self drawBubble:NSMakePoint(98, 18) radius:3.5 alpha:0.75];
    [self drawBubble:NSMakePoint(104, 14) radius:2.5 alpha:0.55];
    [self drawBubble:NSMakePoint(92, 15) radius:2.0 alpha:0.45];

    // Trailing bubbles
    [self drawBubble:NSMakePoint(6, 36) radius:2.5 alpha:0.35];
    [self drawBubble:NSMakePoint(2, 46) radius:1.8 alpha:0.28];

    [ctx restoreGraphicsState];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [[NSColor clearColor] setFill];
    NSRectFill(dirtyRect);

    NSString *text = self.message ?: @"Meeting in 5 min";
    CGFloat bannerW = 0, bannerH = 0;
    measureBannerText(text, &bannerW, &bannerH);

    CGFloat cy = (NSHeight(self.bounds) - MAX(kDolphinH, bannerH)) / 2.0;

    CGFloat bannerX = kDolphinW + kRopeLen;
    CGFloat bannerY = cy + (kDolphinH - bannerH) / 2.0;
    NSRect bannerRect = NSMakeRect(bannerX, bannerY, bannerW, bannerH);

    // Banner shadow
    NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
    [ctx saveGraphicsState];
    setSoftShadow();
    NSBezierPath *bannerPath = [NSBezierPath bezierPathWithRoundedRect:bannerRect xRadius:10 yRadius:10];
    fillPath(bannerPath,
             [NSColor colorWithCalibratedRed:0.22 green:0.56 blue:0.96 alpha:1.0],
             [NSColor colorWithCalibratedRed:0.10 green:0.42 blue:0.82 alpha:1.0]);
    [ctx restoreGraphicsState];

    drawBannerText(text, bannerRect);

    // Curved rope
    NSBezierPath *rope = [NSBezierPath bezierPath];
    [[NSColor colorWithCalibratedRed:0.12 green:0.48 blue:0.82 alpha:0.75] setStroke];
    [rope setLineWidth:2.0];
    [rope setLineCapStyle:NSLineCapStyleRound];
    CGFloat tailY = cy + kDolphinH * 0.48;
    [rope moveToPoint:NSMakePoint(kDolphinW - 10, tailY)];
    [rope curveToPoint:NSMakePoint(bannerX, bannerY + bannerH * 0.5)
         controlPoint1:NSMakePoint(kDolphinW + 2, tailY - 6)
         controlPoint2:NSMakePoint(bannerX - 8, bannerY + bannerH * 0.5 + 4)];
    [rope stroke];

    [self drawDolphinAtY:cy];
}

+ (CGFloat)widthForMessage:(NSString *)message {
    CGFloat bannerW = 0, bannerH = 0;
    measureBannerText(message, &bannerW, &bannerH);
    return kDolphinW + kRopeLen + bannerW;
}

@end

#pragma mark - App Delegate

@interface BannerAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, copy) NSString *message;
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) DolphinBannerView *bannerView;
@property (nonatomic, assign) CGFloat sceneWidth;
@property (nonatomic, assign) CGFloat startX;
@property (nonatomic, assign) CGFloat endX;
@property (nonatomic, assign) CGFloat y;
@property (nonatomic, assign) NSTimeInterval flyDuration;
@property (nonatomic, assign) CFAbsoluteTime startTime;
@end

@implementation BannerAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    NSScreen *screen = NSScreen.mainScreen;
    if (!screen) {
        [NSApp terminate:nil];
        return;
    }

    NSRect frame = screen.frame;
    self.sceneWidth = [DolphinBannerView widthForMessage:self.message];
    CGFloat screenW = frame.size.width;

    self.y = frame.origin.y + (frame.size.height - kSceneHeight) / 2.0;
    self.startX = -self.sceneWidth - 30;
    self.endX = screenW + 30;
    self.flyDuration = readBannerDuration();
    self.startTime = CFAbsoluteTimeGetCurrent();

    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(self.startX, self.y, self.sceneWidth, kSceneHeight)
                                              styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.level = NSScreenSaverWindowLevel;
    self.window.backgroundColor = NSColor.clearColor;
    self.window.opaque = NO;
    self.window.hasShadow = NO;
    self.window.ignoresMouseEvents = YES;
    self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                       NSWindowCollectionBehaviorFullScreenAuxiliary |
                                       NSWindowCollectionBehaviorStationary |
                                       NSWindowCollectionBehaviorIgnoresCycle;

    self.bannerView = [[DolphinBannerView alloc] initWithFrame:NSMakeRect(0, 0, self.sceneWidth, kSceneHeight)];
    self.bannerView.message = self.message;
    [self.window setContentView:self.bannerView];
    [self.window makeKeyAndOrderFront:nil];

    [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                    target:self
                                  selector:@selector(tick:)
                                  userInfo:nil
                                   repeats:YES];
}

- (void)tick:(NSTimer *)timer {
    CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - self.startTime;
    CGFloat progress = MIN(elapsed / self.flyDuration, 1.0);

    // Strictly linear horizontal movement
    CGFloat x = self.startX + (self.endX - self.startX) * progress;

    // Very subtle vertical drift — does not affect horizontal speed
    CGFloat bob = sin(progress * M_PI * 2) * 1.5;
    [self.window setFrame:NSMakeRect(x, self.y + bob, self.sceneWidth, kSceneHeight) display:YES];

    if (progress >= 1.0) {
        [timer invalidate];
        [self.window orderOut:nil];
        [NSApp terminate:nil];
    }
}

@end

#pragma mark - Entry

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *message = (argc > 1) ? [NSString stringWithUTF8String:argv[1]] : @"Meeting in 5 min";

        BannerAppDelegate *delegate = [BannerAppDelegate new];
        delegate.message = message;

        NSApplication *app = NSApplication.sharedApplication;
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
