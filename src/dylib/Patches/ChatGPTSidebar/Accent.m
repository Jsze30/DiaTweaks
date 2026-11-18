#import "Transcript.h"

@implementation DPChatAccent {
    __weak NSView *_send;
    CALayer *_layer;
}

// Dia greys its send button while the field is empty, which is right after every send; keep the space's color from before.
static NSMapTable<NSWindow *, NSColor *> *DPChatAccents(void) {
    static NSMapTable *accents;
    if (!accents) accents = [NSMapTable weakToStrongObjectsMapTable];
    return accents;
}

- (void)dealloc { [_layer removeObserver:self forKeyPath:@"backgroundColor"]; }

- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    void (^changed)(void) = self.changed;
    if (changed) dispatch_async(dispatch_get_main_queue(), changed);
}

- (NSColor *)bubbleFor:(DPChatTranscript *)transcript {
    BOOL (^isSend)(NSView *) = ^BOOL(NSView *view) { return DPHasLabel(view, @"Send prompt"); };
    NSView *send = _send.window == transcript.window ? _send : nil;
    if (!send && transcript.composer) send = DPFindView(transcript.composer, isSend);
    for (NSView *view = transcript.superview; !send && view; view = view.superview) send = DPFindView(view, isSend);
    _send = send;
    if (send.layer != _layer) {
        [_layer removeObserver:self forKeyPath:@"backgroundColor"];
        _layer = send.layer;
        [_layer addObserver:self forKeyPath:@"backgroundColor" options:0 context:NULL];
    }
    CGColorRef fill = send.layer.backgroundColor;
    NSColor *accent = fill ? [[NSColor colorWithCGColor:fill] colorUsingColorSpace:NSColorSpace.sRGBColorSpace] : nil;
    BOOL colored = accent.alphaComponent >= 0.05 && accent.saturationComponent >= 0.12;
    BOOL enabled = ![send isKindOfClass:NSControl.class] || ((NSControl *)send).enabled;
    if (colored && transcript.window) [DPChatAccents() setObject:accent forKey:transcript.window];
    else if (!enabled && transcript.window) accent = [DPChatAccents() objectForKey:transcript.window];
    // Dia washes a neutral space's bubbles with 6% of the text color, as it does with no color at all.
    if (!accent || accent.alphaComponent < 0.05 || accent.saturationComponent < 0.12) return [NSColor.labelColor colorWithAlphaComponent:0.06];
    BOOL dark = [[transcript.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
    return [accent colorWithAlphaComponent:dark ? 0.30 : 0.25];
}
@end
