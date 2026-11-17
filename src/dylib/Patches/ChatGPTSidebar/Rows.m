#import "Transcript.h"

static const CGFloat DPChatBubbleX = 14, DPChatBubbleY = 10;

@implementation DPChatRow {
    NSTextView *_text;
    NSView *_bubble;
    NSString *_shown;
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
    _bubble = [NSView new];
    _bubble.wantsLayer = YES;
    _bubble.layer.cornerRadius = 16;
    _bubble.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_bubble];
    [self addSubview:_text];
    _width = -1;
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)show:(DPChatMessage *)message {
    NSString *text = message.text ?: @"";
    if (_shown && (_shown == text || [_shown isEqualToString:text]) && _user == message.fromUser && _failed == message.failed && _pending == message.pending) return;
    _shown = text;
    _user = message.fromUser;
    _failed = message.failed;
    _pending = message.pending;
    _width = -1;
    _bubble.hidden = !_user;
    NSAttributedString *shown;
    if (_user || _failed || (_pending && !text.length)) {
        CGFloat size = _user ? 14 : _failed ? 13 : 12;
        NSColor *color = _user ? NSColor.labelColor : _failed ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor;
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.lineHeightMultiple = _user ? 1.1 : 1.2;
        shown = [[NSAttributedString alloc] initWithString:text.length ? text : @"Thinking…" attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:size], NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style}];
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
        NSSize size = [self measure:floor(width * 0.8) - DPChatBubbleX * 2];
        NSRect bubble = NSMakeRect(width - size.width - DPChatBubbleX * 2, 0, size.width + DPChatBubbleX * 2, size.height + DPChatBubbleY * 2);
        _bubble.frame = bubble;
        _text.frame = NSMakeRect(NSMinX(bubble) + DPChatBubbleX, DPChatBubbleY, size.width, size.height);
        _height = NSHeight(bubble);
    } else {
        NSSize size = [self measure:width];
        _text.frame = NSMakeRect(0, 0, width, size.height);
        _height = size.height;
    }
    return _height;
}
@end
