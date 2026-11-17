#import "Sidebar.h"

// The chat shown in the hosted sidebar that contains `view`, or nil when that sidebar isn't ours.
DPChatConversation *DPChatConversationFor(NSView *view);
// The hosted composer that contains `view`, or nil.
NSView *DPChatComposerFor(NSView *view);
void DPChatInstallInput(void);
