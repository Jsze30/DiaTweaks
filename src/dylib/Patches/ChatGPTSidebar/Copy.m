#import "Transcript.h"

// Dia's reply actions: a 24pt button, 6pt round, its 16pt icon in tertiary ink, full ink on hover over a 5% fill.
@implementation DPChatCopy {
    NSUInteger _copies;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.hover = 0.05;
    self.layer.cornerRadius = 6;
    self.image = DPChatGlyph(@"copy", 16);
    self.imagePosition = NSImageOnly;
    self.imageScaling = NSImageScaleNone;
    self.toolTip = @"Copy";
    self.accessibilityLabel = @"Copy";
    self.target = self;
    self.action = @selector(copyText);
    [self refresh];
    return self;
}

- (void)refresh {
    [super refresh];
    self.contentTintColor = self.hovered ? NSColor.labelColor : NSColor.tertiaryLabelColor;
}

- (void)copyText {
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:self.text ?: @"" forType:NSPasteboardTypeString];
    self.image = DPChatGlyph(@"check", 16);
    NSUInteger copy = ++_copies;
    __weak DPChatCopy *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DPChatCopy *button = weak;
        if (button && button->_copies == copy) button.image = DPChatGlyph(@"copy", 16);
    });
}
@end
