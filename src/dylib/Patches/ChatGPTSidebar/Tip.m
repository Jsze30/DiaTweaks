#import "Transcript.h"

// Dia's new-chat card: tilted 5°, a gray header with an icon and a bold label over a lighter body with a sample question.
static const CGFloat DPChatTipWidth = 191, DPChatTipHeader = 46, DPChatTipBody = 73, DPChatTipPad = 16, DPChatTipRadius = 16, DPChatTipTilt = -5;  // counterclockwise, in this flipped view

static NSColor *DPChatTipFill(CGFloat light, CGFloat dark) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL isDark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
        return [NSColor colorWithWhite:isDark ? dark : light alpha:1];
    }];
}

@interface DPChatTipCard : NSView
@end

@implementation DPChatTipCard
- (BOOL)isFlipped { return YES; }
@end

@implementation DPChatTip {
    NSView *_card, *_header, *_line;
    NSImageView *_icon;
    NSTextField *_label, *_prompt;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.wantsLayer = YES;
    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.12];
    shadow.shadowBlurRadius = 16;
    shadow.shadowOffset = NSMakeSize(0, -6);
    self.shadow = shadow;
    _card = [DPChatTipCard new];
    _card.wantsLayer = YES;
    _card.layer.cornerRadius = DPChatTipRadius;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.layer.masksToBounds = YES;
    _header = [NSView new];
    _header.wantsLayer = YES;
    _line = [NSView new];
    _line.wantsLayer = YES;
    _icon = [NSImageView new];
    _icon.contentTintColor = NSColor.labelColor;
    _label = [NSTextField labelWithString:@""];
    _label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    _label.textColor = NSColor.labelColor;
    _prompt = [NSTextField wrappingLabelWithString:@""];
    _prompt.font = [NSFont systemFontOfSize:14];
    _prompt.textColor = NSColor.secondaryLabelColor;
    _prompt.selectable = NO;
    [self addSubview:_card];
    for (NSView *view in @[_header, _line, _icon, _label, _prompt]) [_card addSubview:view];
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer {
    _card.layer.backgroundColor = DPChatTipFill(0.98, 0.17).CGColor;
    _header.layer.backgroundColor = DPChatTipFill(0.902, 0.23).CGColor;
    _line.layer.backgroundColor = DPChatTipFill(0.86, 0.28).CGColor;
}

- (void)showIcon:(NSString *)icon label:(NSString *)label prompt:(NSString *)prompt {
    _icon.image = DPChatGlyph(icon, 20);
    _label.stringValue = label;
    _prompt.stringValue = prompt;
    self.needsLayout = YES;
}

- (NSSize)intrinsicContentSize { return NSMakeSize(DPChatTipWidth, DPChatTipHeader + DPChatTipBody); }

- (void)layout {
    [super layout];
    CGFloat width = DPChatTipWidth, inner = width - DPChatTipPad * 2;
    _card.frameCenterRotation = 0;
    _card.frame = NSMakeRect((NSWidth(self.bounds) - width) / 2, (NSHeight(self.bounds) - DPChatTipHeader - DPChatTipBody) / 2, width, DPChatTipHeader + DPChatTipBody);
    _card.frameCenterRotation = DPChatTipTilt;
    _header.frame = NSMakeRect(0, 0, width, DPChatTipHeader);
    _line.frame = NSMakeRect(0, DPChatTipHeader - 0.5, width, 0.5);
    _icon.frame = NSMakeRect(DPChatTipPad, (DPChatTipHeader - 20) / 2, 20, 20);
    CGFloat labelX = NSMaxX(_icon.frame) + 8;
    _label.frame = NSMakeRect(labelX, (DPChatTipHeader - _label.intrinsicContentSize.height) / 2, width - labelX - DPChatTipPad, _label.intrinsicContentSize.height);
    NSSize prompt = [_prompt sizeThatFits:NSMakeSize(inner, CGFLOAT_MAX)];
    _prompt.frame = NSMakeRect(DPChatTipPad, DPChatTipHeader + (DPChatTipBody - prompt.height) / 2, inner, ceil(prompt.height));
}
@end
