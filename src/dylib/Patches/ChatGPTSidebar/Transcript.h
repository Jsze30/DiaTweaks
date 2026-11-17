#import "Sidebar.h"

// One message laid out for a width: the user's in a bubble, ChatGPT's as plain text.
@interface DPChatRow : NSView
@property(nonatomic) NSColor *bubbleColor;
- (void)show:(DPChatMessage *)message;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

// Scrolls the messages, and follows the newest one until the user scrolls up.
@interface DPChatScroll : NSScrollView
@property BOOL pinned;
- (void)follow;
@end

// What shows before the first message: sign-in, or a hint once signed in.
@interface DPChatEmpty : NSView
- (void)update;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

NSColor *DPChatCodeFill(void);
// Bold, italic, code, strikethrough and links within one line, on top of `base`.
NSAttributedString *DPChatInline(NSString *text, CGFloat size, BOOL bold, NSDictionary *base);
