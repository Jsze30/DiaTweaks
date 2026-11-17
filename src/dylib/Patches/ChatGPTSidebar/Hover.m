#import "Transcript.h"

@implementation DPChatHoverButton
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.bordered = NO;
    self.wantsLayer = YES;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
}

- (void)mouseEntered:(NSEvent *)event { _hovered = YES; [self refresh]; }
- (void)mouseExited:(NSEvent *)event { _hovered = NO; [self refresh]; }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self refresh]; }

- (void)refresh {
    NSColor *fill = [NSColor.labelColor colorWithAlphaComponent:_hovered && self.enabled ? self.hover : self.rest];
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{ self.layer.backgroundColor = fill.CGColor; }];
}
@end
