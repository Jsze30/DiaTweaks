#import "Transcript.h"

static const CGFloat DPChatSide = 16, DPChatGap = 16, DPChatTop = 12;

@implementation DPChatTranscript {
    __weak DPChatConversation *_chat;
    __weak NSView *_send;
    DPChatScroll *_scroll;
    DPChatEmpty *_empty;
    NSMutableArray<DPChatRow *> *_rows;
    NSColor *_bubble;
    BOOL _scheduled;
    CFTimeInterval _shown;
}

- (instancetype)initWithConversation:(DPChatConversation *)conversation {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _rows = [NSMutableArray new];
    _scroll = [DPChatScroll new];
    _empty = [DPChatEmpty new];
    [self addSubview:_scroll];
    [self addSubview:_empty];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(serviceChanged) name:DPChatServiceDidChange object:nil];
    self.conversation = conversation;
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (DPChatConversation *)conversation { return _chat; }

- (void)setConversation:(DPChatConversation *)conversation {
    _chat = conversation;
    __weak DPChatTranscript *weak = self;
    conversation.changed = ^(BOOL streaming) { streaming ? [weak throttle] : [weak reload]; };
    [self reload];
}

// Streaming changes the last message many times a second, so show at most 30 of them.
- (void)throttle {
    if (_scheduled) return;
    CFTimeInterval wait = _shown + 1.0 / 30 - CACurrentMediaTime();
    if (wait <= 0) return [self refresh];
    _scheduled = YES;
    __weak DPChatTranscript *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weak flush]; });
}

- (void)flush { if (_scheduled) [self refresh]; }
- (void)reload { _bubble = nil; [self refresh]; }

- (void)refresh {
    _scheduled = NO;
    _shown = CACurrentMediaTime();
    NSArray<DPChatMessage *> *messages = _chat.messages ?: @[];
    if (messages.count > _rows.count) _scroll.pinned = YES;
    while (_rows.count > messages.count) { [_rows.lastObject removeFromSuperview]; [_rows removeLastObject]; }
    while (_rows.count < messages.count) { [_rows addObject:[DPChatRow new]]; [_scroll.documentView addSubview:_rows.lastObject]; }
    if (!_bubble) _bubble = [self bubbleColor];
    [messages enumerateObjectsUsingBlock:^(DPChatMessage *message, NSUInteger i, BOOL *stop) {
        DPChatRow *row = self->_rows[i];
        [row show:message];
        if (row.bubbleColor != self->_bubble) row.bubbleColor = self->_bubble;
    }];
    _scroll.hidden = !messages.count;
    _empty.hidden = messages.count > 0;
    self.needsLayout = YES;
}

// The user's bubbles take the profile's accent from Dia's send button.
- (NSColor *)bubbleColor {
    BOOL (^isSend)(NSView *) = ^BOOL(NSView *view) { return DPHasLabel(view, @"Send prompt"); };
    NSView *send = _send.window == self.window ? _send : nil;
    if (!send && self.composer) send = DPFindView(self.composer, isSend);
    for (NSView *view = self.superview; !send && view; view = view.superview) send = DPFindView(view, isSend);
    _send = send;
    NSColor *accent = send.layer.backgroundColor ? [NSColor colorWithCGColor:send.layer.backgroundColor] : nil;
    if (accent.alphaComponent < 0.05) return [NSColor.labelColor colorWithAlphaComponent:0.06];
    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
    return [accent colorWithAlphaComponent:dark ? 0.30 : 0.16];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    __weak DPChatTranscript *weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weak reload]; });
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) [self reload];
}

// Dia animates the container's subviews to sizes it picked before the container settled, so always fill it.
- (void)setFrameSize:(NSSize)size { [super setFrameSize:self.superview ? self.superview.bounds.size : size]; }

- (void)serviceChanged {
    [_empty update];
    self.needsLayout = YES;
}

- (void)layout {
    [super layout];
    NSView *composer = self.composer;
    CGFloat bottom = DPChatGap;
    if (composer.superview) bottom += MAX(0, [self convertPoint:NSMakePoint(0, NSMaxY(composer.frame)) fromView:composer.superview].y);
    _scroll.frame = self.bounds;
    NSEdgeInsets insets = NSEdgeInsetsMake(DPChatTop, 0, bottom, 0);
    if (!NSEdgeInsetsEqual(insets, _scroll.contentInsets)) _scroll.contentInsets = insets;
    CGFloat width = MAX(_scroll.contentSize.width - DPChatSide * 2, 40), y = 0;
    for (DPChatRow *row in _rows) {
        CGFloat height = [row heightForWidth:width];
        row.frame = NSMakeRect(DPChatSide, y, width, height);
        y += height + DPChatGap;
    }
    [_scroll.documentView setFrameSize:NSMakeSize(_scroll.contentSize.width, MAX(y - DPChatGap, 0))];
    if (!_empty.hidden) {
        CGFloat height = [_empty heightForWidth:width];
        _empty.frame = NSMakeRect(DPChatSide, floor(bottom + (NSHeight(self.bounds) - DPChatTop - bottom - height) / 2), width, height);
    }
    [_scroll follow];
}
@end
