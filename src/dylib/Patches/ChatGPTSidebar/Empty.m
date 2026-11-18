#import "Transcript.h"

static BOOL DPChatWantsSignIn;
static NSString *const DPChatTipsHidden = @"chatGPTTipsHidden";

// What ChatGPT here can really do: read the page, take a new page along, and remember the chat.
static NSArray<NSArray<NSString *> *> *DPChatTips(void) {
    return @[
        @[@"browser", @"This page", @"Summarize this page in a few points", @"Ask about this page", @"ChatGPT reads the page you're on"],
        @[@"arrows", @"Another page", @"How does this compare to the last page?", @"Compare pages", @"Open another page and keep asking"],
        @[@"chat", @"Follow-ups", @"Now make it shorter", @"Keep the conversation going", @"ChatGPT remembers this chat until you start a new one"],
    ];
}

static NSUserDefaults *DPChatDefaults(void) { return [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; }

static NSTextField *DPChatLabel(CGFloat size, NSColor *ink) {
    NSTextField *label = [NSTextField wrappingLabelWithString:@""];
    label.font = [NSFont systemFontOfSize:size weight:NSFontWeightMedium];
    label.textColor = ink;
    label.alignment = NSTextAlignmentCenter;
    label.selectable = NO;
    return label;
}

// Dia's new chat: a tilted tip card, a medium title and a lighter line under it. Signed out, a sign-in button takes the card's place.
@implementation DPChatEmpty {
    DPChatTip *_tip;
    DPChatHoverButton *_dismiss, *_button;
    NSTextField *_title, *_subtitle;
    NSUInteger _shown;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _tip = [DPChatTip new];
    _dismiss = [DPChatHoverButton new];
    _dismiss.hover = 0.05;
    _dismiss.layer.cornerRadius = 6;
    _dismiss.image = DPChatGlyph(@"x", 12);
    _dismiss.contentTintColor = NSColor.tertiaryLabelColor;
    _dismiss.toolTip = _dismiss.accessibilityLabel = @"Hide tips";
    _dismiss.target = self;
    _dismiss.action = @selector(hideTips);
    _title = DPChatLabel(15, NSColor.secondaryLabelColor);
    _subtitle = DPChatLabel(13, NSColor.tertiaryLabelColor);
    _button = [DPChatHoverButton new];
    _button.rest = 0.08;
    _button.hover = 0.12;
    _button.layer.cornerRadius = 8;
    _button.target = self;
    _button.action = @selector(signIn);
    for (NSView *view in @[_tip, _dismiss, _title, _subtitle, _button]) [self addSubview:view];
    _shown = arc4random_uniform((uint32_t)DPChatTips().count);
    [self update];
    return self;
}

- (BOOL)isFlipped { return YES; }

// A new tip each time a new chat shows.
- (void)setHidden:(BOOL)hidden {
    if (self.hidden && !hidden) {
        _shown = (_shown + 1) % DPChatTips().count;
        [self update];
    }
    [super setHidden:hidden];
}

- (void)signIn {
    DPChatService *service = DPChatService.shared;
    DPChatWantsSignIn = !service.client.task;
    [service signIn];
}

- (void)hideTips {
    [DPChatDefaults() setBool:YES forKey:DPChatTipsHidden];
    [self update];
}

- (void)update {
    DPChatService *service = DPChatService.shared;
    if (DPChatWantsSignIn && !service.connecting) {
        DPChatWantsSignIn = NO;
        if (service.client.task && !service.signedIn && !service.problem) [service signIn];
    }
    BOOL busy = service.connecting || service.signingIn;
    NSString *title = service.signingIn ? @"Waiting for sign-in…" : service.connecting ? @"Connecting…" : @"Sign in with ChatGPT";
    _button.enabled = !busy;
    _button.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: busy ? NSColor.tertiaryLabelColor : NSColor.labelColor}];
    [_button refresh];
    // Until Codex says whether you're signed in, show nothing rather than a sign-in screen that's about to vanish.
    BOOL waiting = !service.signedIn && !service.checked && !service.problem;
    BOOL wasWaiting = _tip.hidden && _title.hidden;
    for (NSView *view in @[_title, _subtitle]) view.hidden = waiting;
    if (waiting) _tip.hidden = _dismiss.hidden = _button.hidden = YES;
    if (wasWaiting && !waiting && self.window) DPChatAppear(self.layer, 0.36, 0, 6);
    if (waiting) return;
    NSArray<NSString *> *tip = DPChatTips()[_shown];
    [_tip showIcon:tip[0] label:tip[1] prompt:tip[2]];
    _tip.hidden = _dismiss.hidden = !service.signedIn || [DPChatDefaults() boolForKey:DPChatTipsHidden];
    _button.hidden = service.signedIn;
    _title.stringValue = service.signedIn ? tip[3] : @"Sign in to ChatGPT";
    _subtitle.stringValue = service.signedIn ? tip[4] : service.problem.length ? service.problem : @"Uses the ChatGPT login from Codex";
    self.needsLayout = YES;
}

- (CGFloat)place:(NSView *)view at:(CGFloat)y width:(CGFloat)width {
    if (view.hidden) return y;
    if ([view isKindOfClass:NSTextField.class]) ((NSTextField *)view).preferredMaxLayoutWidth = width;
    NSSize size = view == _button ? NSMakeSize(ceil(_button.attributedTitle.size.width) + 28, 30)
                : view == _tip ? NSMakeSize(width, 136) : [(NSTextField *)view sizeThatFits:NSMakeSize(width, CGFLOAT_MAX)];
    size.width = MIN(ceil(size.width), width);
    view.frame = NSMakeRect(floor((NSWidth(self.bounds) - size.width) / 2), y, size.width, ceil(size.height));
    return y + ceil(size.height) + (view == _tip ? 16 : view == _title ? 4 : 16);
}

- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat y = 0;
    for (NSView *view in @[_tip, _title, _subtitle, _button]) y = [self place:view at:y width:width];
    _dismiss.frame = NSMakeRect(floor(NSMidX(_tip.frame) + 191 / 2.0 + 8), NSMinY(_tip.frame) + 4, 20, 20);
    return MAX(y - 16, 0);
}

- (void)layout {
    [super layout];
    [self heightForWidth:NSWidth(self.bounds)];
}
@end
