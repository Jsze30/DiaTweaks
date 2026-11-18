#import "Transcript.h"

// Dia's chat: the user's 14pt text on 23.52pt lines, in a bubble at most 80% wide, padded 16 by 14 in a column up to 360pt
// and 24 by 16 past it, a capsule on one line and 17pt round otherwise. Dia keeps 32pt under it for a timestamp row on hover.
// The shared page's 184 by 54 card sits 12pt above the bubble. A reply's actions sit 17pt under it.
static const CGFloat DPChatUserLine = 23.52, DPChatUserMeta = 32, DPChatCardWidth = 184, DPChatCardHeight = 54, DPChatCardGap = 12,
                     DPChatActionGap = 17, DPChatActionSize = 24;

@implementation DPChatRow {
    NSTextView *_text;
    NSView *_bubble;
    DPChatCard *_card;
    DPChatCopy *_copy;
    NSString *_shown, *_page;
    DPChatPage *_pageShown;
    NSImage *_iconShown;
    BOOL _user, _failed, _pending;
    CGFloat _width, _height;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    NSTextStorage *storage = [NSTextStorage new];
    NSLayoutManager *layout = [NSLayoutManager new];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(100, CGFLOAT_MAX)];
    container.lineFragmentPadding = 0;
    container.widthTracksTextView = NO;
    [layout addTextContainer:container];
    [storage addLayoutManager:layout];
    _text = [[NSTextView alloc] initWithFrame:NSZeroRect textContainer:container];
    _text.editable = NO;
    _text.selectable = YES;
    _text.drawsBackground = NO;
    _text.textContainerInset = NSZeroSize;
    _text.verticallyResizable = _text.horizontallyResizable = NO;
    _text.wantsLayer = YES;
    self.wantsLayer = YES;
    _bubble = [NSView new];
    _bubble.wantsLayer = YES;
    _bubble.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_bubble];
    [self addSubview:_text];
    _width = -1;
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)show:(DPChatMessage *)message {
    NSString *text = message.text ?: @"", *page = message.fromUser ? message.page.url : nil;
    DPChatPage *pageShown = message.fromUser ? message.page : nil;
    if (_shown && (_shown == text || [_shown isEqualToString:text]) && _user == message.fromUser && _failed == message.failed &&
        _pending == message.pending && (_page == page || [_page isEqualToString:page]) && _pageShown == pageShown && _iconShown == pageShown.icon)
        return;
    BOOL wasThinking = _shown && !_user && _pending && !_shown.length, copyWasHidden = !_copy || _copy.hidden;
    BOOL cardChanged = _pageShown && pageShown && (_pageShown != pageShown || _iconShown != pageShown.icon);
    _shown = text;
    _page = page;
    _pageShown = pageShown;
    _iconShown = pageShown.icon;
    _user = message.fromUser;
    _failed = message.failed;
    _pending = message.pending;
    _width = -1;
    _bubble.hidden = !_user;
    if (page && !_card) [self addSubview:(_card = [DPChatCard new])];
    _card.hidden = !page;
    if (page) {
        if (cardChanged) DPChatFade(_card.layer, 0.2);  // The page was read: its real title and icon replace the address.
        [_card show:message];
    }
    BOOL done = !_user && !_failed && !_pending && text.length;
    if (done && !_copy) [self addSubview:(_copy = [DPChatCopy new])];
    _copy.hidden = !done;
    _copy.text = text;
    if (done && copyWasHidden) DPChatAppear(_copy.layer, 0.25, 0.1, 0);
    BOOL thinking = !_user && !_failed && _pending && !text.length;
    DPChatPulse(_text.layer, thinking);
    if (wasThinking && !thinking) DPChatAppear(_text.layer, 0.3, 0, 4);
    NSAttributedString *shown;
    if (_user) {
        NSFont *font = [NSFont systemFontOfSize:14];
        NSMutableDictionary *attributes = [DPChatLine(font, DPChatUserLine, [NSMutableParagraphStyle new]) mutableCopy];
        attributes[NSFontAttributeName] = font;
        attributes[NSForegroundColorAttributeName] = NSColor.labelColor;
        shown = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    } else if (_failed || (_pending && !text.length)) {
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.lineHeightMultiple = 1.2;
        shown = [[NSAttributedString alloc] initWithString:text.length ? text : @"Thinking" attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:_failed ? 13 : 12], NSParagraphStyleAttributeName: style,
            NSForegroundColorAttributeName: NSColor.secondaryLabelColor}];
    } else shown = DPChatMarkdown(text, 15);
    [_text.textStorage setAttributedString:shown];
}

- (void)setBubbleColor:(NSColor *)color {
    _bubbleColor = color;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{ self->_bubble.layer.backgroundColor = color.CGColor; }];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    self.bubbleColor = _bubbleColor;
}

- (NSSize)measure:(CGFloat)width {
    NSTextContainer *container = _text.textContainer;
    container.size = NSMakeSize(MAX(width, 1), CGFLOAT_MAX);
    [_text.layoutManager ensureLayoutForTextContainer:container];
    NSRect used = [_text.layoutManager usedRectForTextContainer:container];
    return NSMakeSize(ceil(NSWidth(used)), ceil(NSHeight(used)));
}

- (CGFloat)heightForWidth:(CGFloat)width {
    if (width == _width) return _height;
    _width = width;
    if (_user) {
        CGFloat top = 0, padX = width <= 360 ? 16 : 24, padY = width <= 360 ? 14 : 16;
        if (_page) {
            CGFloat card = MIN(DPChatCardWidth, width);
            _card.frame = NSMakeRect(width - card, 0, card, DPChatCardHeight);
            top = DPChatCardHeight + DPChatCardGap;
        }
        NSSize size = [self measure:floor(width * 0.8) - padX * 2];
        NSRect bubble = NSMakeRect(width - size.width - padX * 2, top, size.width + padX * 2, size.height + padY * 2);
        _bubble.frame = bubble;
        _bubble.layer.cornerRadius = size.height <= ceil(DPChatUserLine) ? NSHeight(bubble) / 2 : 17;
        _text.frame = NSMakeRect(NSMinX(bubble) + padX, top + padY, size.width, size.height);
        _height = NSMaxY(bubble) + DPChatUserMeta;
    } else {
        NSSize size = [self measure:width];
        _text.frame = NSMakeRect(0, 0, width, size.height);
        _height = size.height;
        if (_copy && !_copy.hidden) {
            _copy.frame = NSMakeRect(0, _height + DPChatActionGap, DPChatActionSize, DPChatActionSize);
            _height = NSMaxY(_copy.frame);
        }
    }
    return _height;
}
@end
