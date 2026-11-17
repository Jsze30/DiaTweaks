#import "Host.h"
#import "Conversation.h"
#import "Patches/CommandBar/Tabs.h"

static NSMutableDictionary<NSString *, DPChatConversation *> *gChats;

@implementation DPChatConversation (Tabs)
+ (instancetype)forTab:(NSString *)tab {
    if (!gChats) gChats = [NSMutableDictionary new];
    DPChatConversation *chat = gChats[tab];
    if (!chat) {
        [self forgetClosedTabs];
        chat = [DPChatConversation new];
        chat.messages = [NSMutableArray new];
        gChats[tab] = chat;
        [NSNotificationCenter.defaultCenter addObserver:chat selector:@selector(serviceEvent:) name:DPChatServiceEvent object:nil];
        [NSNotificationCenter.defaultCenter addObserver:chat selector:@selector(serviceChanged:) name:DPChatServiceDidChange object:nil];
    }
    return chat;
}

+ (void)forgetClosedTabs {
    NSMutableSet<NSString *> *open = [NSMutableSet new];
    for (id window in [(id)NSApp.delegate valueForKey:@"appleScriptWindows"])
        for (id tab in [window valueForKey:@"appleScriptTabs"]) if (DPTabID(tab)) [open addObject:DPTabID(tab)];
    for (NSString *tab in gChats.allKeys) {
        if ([open containsObject:tab]) continue;
        [gChats[tab] stop];
        [gChats removeObjectForKey:tab];
    }
}
@end

// Dia updates its tab list after the page closes.
static void DPChatPage_close(id self, SEL _cmd, NSInteger timing) {
    DPCallOriginal(DPChatPage_close, self, timing);
    dispatch_async(dispatch_get_main_queue(), ^{ [DPChatConversation forgetClosedTabs]; });
}

void DPChatInstallTabs(void) { DPHook(DPDiaWebContents, @selector(closeWithForegroundCommitTiming:), (IMP)DPChatPage_close); }
