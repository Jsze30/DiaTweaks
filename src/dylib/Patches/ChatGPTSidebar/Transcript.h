#import "Sidebar.h"

// One message laid out for a width: the user's in a bubble under the page it shared, ChatGPT's as plain text with a Copy button.
@interface DPChatRow : NSView
@property(nonatomic) NSColor *bubbleColor;
- (void)show:(DPChatMessage *)message;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

// Scrolls the messages, and follows the newest one until the user scrolls up.
@interface DPChatScroll : NSScrollView
@property BOOL pinned;
- (void)follow:(BOOL)glide;
@end

// What shows before the first message: sign-in, or a hint once signed in.
@interface DPChatEmpty : NSView
- (void)update;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

// The user's bubble color: the space's color from Dia's send button, watched so a switch of spaces recolors at once.
@interface DPChatAccent : NSObject
@property(copy) void (^changed)(void);
- (NSColor *)bubbleFor:(DPChatTranscript *)transcript;
@end

// A borderless button whose fill shows on hover, as Dia's own do.
@interface DPChatHoverButton : NSButton
@property CGFloat rest, hover;  // fill opacity
@property(readonly) BOOL hovered;
- (void)refresh;
@end

// Dia's tilted new-chat card: an icon and label over a sample question.
@interface DPChatTip : NSView
- (void)showIcon:(NSString *)icon label:(NSString *)label prompt:(NSString *)prompt;
@end

// The page a message shared: its icon, title and site, as Dia shows a tab above a message.
@interface DPChatCard : NSView
- (void)show:(DPChatMessage *)message;
@end

// Copies a reply, then shows a check for a moment.
@interface DPChatCopy : DPChatHoverButton
@property(copy) NSString *text;
@end

// A Phosphor icon by name, as a template image.
NSImage *DPChatGlyph(NSString *name, CGFloat size);
NSColor *DPChatCodeFill(void);
// Bold, italic, code, strikethrough and links within one line, on top of `base`.
NSAttributedString *DPChatInline(NSString *text, CGFloat size, NSFontWeight weight, NSDictionary *base);
// Line height and the baseline shift that centers text in it, as CSS does.
NSDictionary *DPChatLine(NSFont *font, CGFloat height, NSMutableParagraphStyle *style);

// Motion, all on one curve and skipped when Reduce Motion is on.
void DPChatFade(CALayer *layer, CFTimeInterval duration);  // crossfades the layer's next change
void DPChatAppear(CALayer *layer, CFTimeInterval duration, CFTimeInterval delay, CGFloat rise);
void DPChatPulse(CALayer *layer, BOOL on);
void DPChatFadeAway(NSView *over, NSImage *picture, NSRect frame, CFTimeInterval duration);
NSImage *DPChatPicture(NSView *view);
