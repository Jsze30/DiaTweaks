#import "Sidebar.h"

// A label with a small button at its trailing edge, like the other tweaks' rows.
@interface DPChatSettingsRow : NSStackView
@property(strong) NSButton *button;
@end

@implementation DPChatSettingsRow
- (instancetype)initWithLabel:(NSString *)label button:(NSString *)title action:(SEL)action {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.button = [NSButton buttonWithTitle:title target:self action:action];
    self.button.controlSize = NSControlSizeSmall;
    [self.button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSTextField *text = [NSTextField labelWithString:label];
    [text setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.distribution = NSStackViewDistributionFill;
    [self setViews:@[ text, self.button ] inGravity:NSStackViewGravityLeading];
    return self;
}
@end

@interface DPChatAccountRow : DPChatSettingsRow
@end

@implementation DPChatAccountRow
- (instancetype)init {
    if (!(self = [super initWithLabel:@"ChatGPT Account" button:@"Sign Out of ChatGPT" action:@selector(signOut:)])) return nil;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sync) name:DPChatServiceDidChange object:nil];
    [self sync];
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    // Codex only knows whether you're signed in once it's running.
    if (self.window && DPChatGPTSidebar.on && !DPTesting) [DPChatService.shared connect];
    [self sync];
}

- (void)sync { self.button.enabled = DPChatService.shared.signedIn; }
- (void)signOut:(id)sender { [DPChatService.shared signOut]; }
@end

@interface DPChatCodexRow : DPChatSettingsRow
@end

@implementation DPChatCodexRow
- (instancetype)init {
    if (!(self = [super initWithLabel:@"Codex App or CLI" button:@"Choose Codex…" action:@selector(choose:)])) return nil;
    [self sync];
    return self;
}

- (void)sync { self.button.toolTip = DPChatExecutable() ?: @"Install Codex or choose its executable."; }

- (void)choose:(id)sender {
    NSOpenPanel *picker = [NSOpenPanel openPanel];
    picker.message = @"Choose the Codex executable";
    picker.canChooseDirectories = NO;
    picker.allowsMultipleSelection = NO;
    picker.showsHiddenFiles = YES;
    if ([picker runModal] != NSModalResponseOK) return;
    NSString *path = picker.URL.path;
    if ([path.pathExtension isEqualToString:@"app"]) path = [path stringByAppendingPathComponent:@"Contents/Resources/codex"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:path]) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Choose the Codex app or its executable.";
        [alert runModal];
        return;
    }
    [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] setObject:path forKey:@"chatGPTCodexPath"];
    [self sync];
    // Restart Codex so the next message uses the one you chose.
    if (DPChatService.shared.client.task || DPChatService.shared.connecting) {
        [DPChatService.shared shutdown];
        if (DPChatGPTSidebar.on) [DPChatService.shared connect];
    }
}
@end

NSArray<NSView *> *DPChatSettings(void) { return @[ [DPChatAccountRow new], [DPChatCodexRow new] ]; }
