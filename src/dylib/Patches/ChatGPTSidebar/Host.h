#import "Sidebar.h"

// The chat shown in the hosted sidebar that contains `view`, or nil when that sidebar isn't ours.
DPChatConversation *DPChatConversationFor(NSView *view);
// The hosted composer that contains `view`, or nil.
NSView *DPChatComposerFor(NSView *view);
void DPChatInstallInput(void);
// Takes a question asked in Dia's command bar to ChatGPT. Each returns YES when it took the event from Dia.
BOOL DPChatBarKey(NSEvent *event, NSTextView *textView);
BOOL DPChatBarClick(NSEvent *event, NSView *hit);
BOOL DPChatBarMouseUp(void);
// The chat shown in `window`'s sidebar for its front tab, or nil.
DPChatConversation *DPChatShownIn(NSWindow *window);
// The question waiting for the chat opened for it in `window`, taken once and only for a few seconds.
NSString *DPChatTakeAsked(NSWindow *window);
void DPChatInstallHints(void);
void DPChatInstallTabs(void);
// Clears Dia's hints over our transcript in `container`, or gives them back once it isn't ours.
void DPChatClearHints(NSView *container);
