#import "Transcript.h"

static BOOL DPChatWantsSignIn;

@interface DPChatSignInButton : NSButton
@property BOOL hovered;
@end

@implementation DPChatSignInButton
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; [self refresh]; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; [self refresh]; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self refresh]; }
- (void)refresh {
    NSColor *fill = [NSColor.labelColor colorWithAlphaComponent:self.hovered && self.enabled ? 0.12 : 0.08];
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{ self.layer.backgroundColor = fill.CGColor; }];
}
@end

static NSTextField *DPChatLabel(CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = [NSTextField wrappingLabelWithString:@""];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.alignment = NSTextAlignmentCenter;
    label.selectable = NO;
    return label;
}

@implementation DPChatEmpty {
    NSTextField *_title, *_problem, *_hint;
    DPChatSignInButton *_button;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _title = DPChatLabel(15, NSFontWeightMedium, NSColor.secondaryLabelColor);
    _title.stringValue = @"ChatGPT";
    _problem = DPChatLabel(12, NSFontWeightRegular, NSColor.secondaryLabelColor);
    _hint = DPChatLabel(13, NSFontWeightRegular, NSColor.tertiaryLabelColor);
    _hint.stringValue = @"Ask ChatGPT about this page";
    _button = [DPChatSignInButton new];
    _button.bordered = NO;
    _button.wantsLayer = YES;
    _button.layer.cornerRadius = 8;
    _button.layer.cornerCurve = kCACornerCurveContinuous;
    _button.target = self;
    _button.action = @selector(signIn);
    for (NSView *view in @[_title, _button, _problem, _hint]) [self addSubview:view];
    [self update];
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)signIn {
    DPChatService *service = DPChatService.shared;
    DPChatWantsSignIn = !service.client.task;
    [service signIn];
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
    _problem.stringValue = service.problem ?: @"";
    _hint.hidden = !service.signedIn;
    _title.hidden = _button.hidden = service.signedIn;
    _problem.hidden = service.signedIn || !service.problem.length;
    self.needsLayout = YES;
}

- (CGFloat)place:(NSView *)view at:(CGFloat)y width:(CGFloat)width {
    if (view.hidden) return y;
    NSSize size = view == _button ? NSMakeSize(ceil(_button.attributedTitle.size.width) + 28, 30) : [(NSTextField *)view sizeThatFits:NSMakeSize(width, CGFLOAT_MAX)];
    size.width = MIN(ceil(size.width), width);
    view.frame = NSMakeRect(floor((NSWidth(self.bounds) - size.width) / 2), y, size.width, ceil(size.height));
    return y + ceil(size.height) + (view == _title ? 12 : 8);
}

- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat y = 0;
    for (NSView *view in @[_title, _button, _problem, _hint]) y = [self place:view at:y width:width];
    return MAX(y - 8, 0);
}

- (void)layout {
    [super layout];
    [self heightForWidth:NSWidth(self.bounds)];
}
@end
