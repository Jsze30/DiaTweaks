#import "Transcript.h"

// Dia centers its chat in a column up to 596pt wide with 28pt on each side, 40pt under the header.
static const CGFloat DPChatColumn = 596, DPChatSide = 28, DPChatGap = 16, DPChatTop = 40;

@implementation DPChatTranscript {
    __weak DPChatConversation *_chat;
    DPChatAccent *_accent;
    DPChatScroll *_scroll;
    DPChatEmpty *_empty;
    NSMutableArray<DPChatRow *> *_rows;
    NSColor *_bubble;
    BOOL _scheduled, _live, _glide;
    CFTimeInterval _shown;
}

- (instancetype)initWithConversation:(DPChatConversation *)conversation {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _accent = [DPChatAccent new];
    __weak DPChatTranscript *weak = self;
    _accent.changed = ^{ [weak reload]; };
    _rows = [NSMutableArray new];
    _scroll = [DPChatScroll new];
    _empty = [DPChatEmpty new];
    _empty.wantsLayer = YES;
    self.wantsLayer = YES;
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
    BOOL wasEmpty = !_empty.hidden, empty = !messages.count;
    // Moving between the new-chat screen and a chat crossfades; a restored chat just shows.
    if (_live && wasEmpty != empty) DPChatFade(self.layer, 0.22);
    if (messages.count > _rows.count) _scroll.pinned = YES, _glide = _live;
    while (_rows.count > messages.count) { [_rows.lastObject removeFromSuperview]; [_rows removeLastObject]; }
    while (_rows.count < messages.count) {
        DPChatRow *row = [DPChatRow new];
        [_rows addObject:row];
        [_scroll.documentView addSubview:row];
        if (_live) DPChatAppear(row.layer, 0.32, 0, 8);
    }
    if (!_bubble) _bubble = [_accent bubbleFor:self];
    [messages enumerateObjectsUsingBlock:^(DPChatMessage *message, NSUInteger i, BOOL *stop) {
        DPChatRow *row = self->_rows[i];
        [row show:message];
        if (row.bubbleColor != self->_bubble) row.bubbleColor = self->_bubble;
    }];
    _scroll.hidden = empty;
    _empty.hidden = !empty;
    if (_live && empty && !wasEmpty) DPChatAppear(_empty.layer, 0.36, 0.06, 6);
    self.needsLayout = YES;
}

// Dia swaps in a new chat view for New chat: fade the old chat out over the new one as the new-chat screen rises in.
- (void)takeOverFrom:(NSImage *)picture frame:(NSRect)frame {
    [self layoutSubtreeIfNeeded];
    DPChatFadeAway(self, picture, NSIsEmptyRect(frame) ? self.bounds : frame, 0.2);
    if (!_empty.hidden) DPChatAppear(_empty.layer, 0.36, 0.08, 6);
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    __weak DPChatTranscript *weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weak reload]; });
}

- (void)viewWillMoveToWindow:(NSWindow *)window {
    if (!window && self.window && self.conversation.messages.count)
        _parting = DPChatPicture(self), _partingFrame = [self convertRect:self.bounds toView:nil];
    [super viewWillMoveToWindow:window];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    _live = NO;
    if (!self.window) return;
    [self reload];
    // What's already there when the view shows (a restored chat) appears at once; what comes after moves.
    __weak DPChatTranscript *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DPChatTranscript *strong = weak;
        if (strong.window) strong->_live = YES;
    });
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
    CGFloat width = MAX(MIN(_scroll.contentSize.width - DPChatSide * 2, DPChatColumn), 40), y = 0;
    CGFloat x = floor((_scroll.contentSize.width - width) / 2);
    for (DPChatRow *row in _rows) {
        CGFloat height = [row heightForWidth:width];
        row.frame = NSMakeRect(x, y, width, height);
        y += height + DPChatGap;
    }
    [_scroll.documentView setFrameSize:NSMakeSize(_scroll.contentSize.width, MAX(y - DPChatGap, 0))];
    if (!_empty.hidden) {
        CGFloat height = [_empty heightForWidth:width];
        _empty.frame = NSMakeRect(x, floor(bottom + (NSHeight(self.bounds) - bottom - height) / 2), width, height);
    }
    [_scroll follow:_glide];
    _glide = NO;
}
@end
