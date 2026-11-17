#import "Transcript.h"

// Dia's attachment card: 20pt squircle, 8pt padding, a 30.5 by 38 tile holding the 16pt favicon, 13pt title over 11pt site.
static const CGFloat DPChatCardPad = 8, DPChatTileWidth = 30.5, DPChatTileHeight = 38;

static NSTextField *DPChatCardLabel(CGFloat size, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:@""];
    label.font = [NSFont systemFontOfSize:size];
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

// CSS's 0 1px <blur> shadow in black at `opacity`.
static void DPChatShadow(NSView *view, CGFloat opacity, CGFloat blur) {
    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:opacity];
    shadow.shadowBlurRadius = blur;
    shadow.shadowOffset = NSMakeSize(0, -1);
    view.shadow = shadow;
}

@implementation DPChatCard {
    NSView *_tile;
    NSImageView *_icon;
    NSTextField *_title, *_site;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 20;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    DPChatShadow(self, 0.2, 3);
    _tile = [NSView new];
    _tile.wantsLayer = YES;
    _tile.layer.cornerRadius = 6;
    _tile.layer.cornerCurve = kCACornerCurveContinuous;
    DPChatShadow(_tile, 0.1, 2);
    _icon = [NSImageView new];
    _icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    _icon.wantsLayer = YES;
    _icon.layer.cornerRadius = 4;
    _icon.layer.masksToBounds = YES;
    _title = DPChatCardLabel(13, NSColor.labelColor);
    _site = DPChatCardLabel(11, NSColor.secondaryLabelColor);
    [_tile addSubview:_icon];
    for (NSView *view in @[_tile, _title, _site]) [self addSubview:view];
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer {
    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
    self.layer.backgroundColor = [NSColor colorWithWhite:dark ? 0.204 : 0.906 alpha:1].CGColor;
    _tile.layer.backgroundColor = [NSColor colorWithWhite:dark ? 0.086 : 0.988 alpha:1].CGColor;
}

- (void)show:(DPChatMessage *)message {
    NSString *site = [NSURL URLWithString:message.page.url].host ?: @"";
    if ([site hasPrefix:@"www."]) site = [site substringFromIndex:4];
    // Like Dia's chip, leave off a trailing " - Wikipedia" when the site already says it.
    NSString *title = message.page.title ?: @"";
    for (NSString *mark in @[@" - ", @" | ", @" — ", @" · "]) {
        NSRange cut = [title rangeOfString:mark options:NSBackwardsSearch];
        NSString *tail = cut.length ? [[title substringFromIndex:NSMaxRange(cut)] stringByReplacingOccurrencesOfString:@" " withString:@""].lowercaseString : nil;
        if (tail.length && [site.lowercaseString containsString:tail]) { title = [title substringToIndex:cut.location]; break; }
    }
    _title.stringValue = title.length ? title : site;
    _site.stringValue = site;
    _icon.image = message.page.icon ?: [NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:nil];
    self.needsLayout = YES;
}

- (void)layout {
    [super layout];
    NSRect bounds = self.bounds;
    _tile.frame = NSMakeRect(DPChatCardPad, (NSHeight(bounds) - DPChatTileHeight) / 2, DPChatTileWidth, DPChatTileHeight);
    _icon.frame = NSMakeRect((DPChatTileWidth - 16) / 2, (DPChatTileHeight - 16) / 2, 16, 16);
    CGFloat x = NSMaxX(_tile.frame) + DPChatCardPad, width = MAX(NSWidth(bounds) - x - DPChatCardPad, 0);
    // CSS stacks the two lines at 1.2 line height with 2pt between, centered; place each by its baseline.
    CGFloat top = (NSHeight(bounds) - 13 * 1.2 - 2 - 11 * 1.2) / 2;
    CGFloat titleBase = top + (13 * 1.2 + _title.font.ascender + _title.font.descender) / 2;
    CGFloat siteBase = top + 13 * 1.2 + 2 + (11 * 1.2 + _site.font.ascender + _site.font.descender) / 2;
    _title.frame = NSMakeRect(x, titleBase - _title.firstBaselineOffsetFromTop, width, _title.intrinsicContentSize.height);
    _site.frame = NSMakeRect(x, siteBase - _site.firstBaselineOffsetFromTop, width, _site.intrinsicContentSize.height);
}
@end
