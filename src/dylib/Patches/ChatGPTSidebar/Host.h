#import "Sidebar.h"

// The chat shown in the hosted sidebar that contains `view`, or nil when that sidebar isn't ours.
DPChatConversation *DPChatConversationFor(NSView *view);
// The hosted composer that contains `view`, or nil.
NSView *DPChatComposerFor(NSView *view);
void DPChatInstallInput(void);
// What was just asked in this window's command bar, taken once and only for a few seconds.
NSString *DPChatTakeAsked(NSWindow *window);
void DPChatInstallHints(void);
void DPChatInstallTabs(void);
// Clears Dia's hints over our transcript in `container`, or gives them back once it isn't ours.
void DPChatClearHints(NSView *container);
