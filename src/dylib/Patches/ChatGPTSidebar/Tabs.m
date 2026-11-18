#import "Host.h"
#import "Conversation.h"
#import "Patches/CommandBar/Tabs.h"

static NSMutableDictionary<NSString *, DPChatConversation *> *gChats;
static NSString *const DPChatThreadsKey = @"chatGPTThreads";  // tab ID: {thread, window}

static NSUserDefaults *DPChatDefaults(void) { return [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; }

@implementation DPChatConversation (Tabs)
+ (instancetype)forTab:(NSString *)tab window:(NSWindow *)window {
    if (!gChats) gChats = [NSMutableDictionary new];
    DPChatConversation *chat = gChats[tab];
    if (!chat) {
        [self forgetClosedTabs];
        chat = [DPChatConversation new];
        chat.messages = [NSMutableArray new];
        chat.tab = tab;
        chat.threadID = [[DPChatDefaults() dictionaryForKey:DPChatThreadsKey][tab] valueForKey:@"thread"];
        gChats[tab] = chat;
        [NSNotificationCenter.defaultCenter addObserver:chat selector:@selector(serviceEvent:) name:DPChatServiceEvent object:nil];
        [NSNotificationCenter.defaultCenter addObserver:chat selector:@selector(serviceChanged:) name:DPChatServiceDidChange object:nil];
        [chat restore];
    }
    if (window.identifier && ![chat.windowID isEqual:window.identifier]) {
        chat.windowID = window.identifier;
        if (chat.threadID) [chat saveThread];
    }
    return chat;
}

- (void)saveThread {
    NSUserDefaults *defaults = DPChatDefaults();
    NSMutableDictionary *saved = [[defaults dictionaryForKey:DPChatThreadsKey] mutableCopy] ?: [NSMutableDictionary new];
    saved[self.tab] = self.threadID ? @{@"thread": self.threadID, @"window": self.windowID ?: @""} : nil;
    [defaults setObject:saved forKey:DPChatThreadsKey];
}

+ (void)forgetClosedTabs {
    NSMutableSet<NSString *> *open = [NSMutableSet new], *windows = [NSMutableSet new];
    for (id window in [(id)NSApp.delegate valueForKey:@"appleScriptWindows"]) {
        if ([window valueForKey:@"windowId"]) [windows addObject:[window valueForKey:@"windowId"]];
        for (id tab in [window valueForKey:@"appleScriptTabs"]) if (DPTabID(tab)) [open addObject:DPTabID(tab)];
    }
    for (NSString *tab in gChats.allKeys) {
        if ([open containsObject:tab]) continue;
        [gChats[tab] stop];
        [gChats removeObjectForKey:tab];
    }
    // A saved chat goes only once its tab is gone from a window that is still open: quitting closes whole windows.
    NSUserDefaults *defaults = DPChatDefaults();
    NSMutableDictionary *saved = [[defaults dictionaryForKey:DPChatThreadsKey] mutableCopy];
    for (NSString *tab in saved.allKeys)
        if (![open containsObject:tab] && [windows containsObject:[saved[tab] valueForKey:@"window"]]) [saved removeObjectForKey:tab];
    if (saved) [defaults setObject:saved forKey:DPChatThreadsKey];
}
@end

NSString *DPChatWindowOfThread(NSString *thread) {
    for (DPChatConversation *chat in gChats.allValues)
        if ([chat.threadID isEqual:thread]) return chat.windowID;
    return nil;
}

// Dia updates its tab list after the page closes.
static void DPChatPage_close(id self, SEL _cmd, NSInteger timing) {
    DPCallOriginal(DPChatPage_close, self, timing);
    dispatch_async(dispatch_get_main_queue(), ^{ [DPChatConversation forgetClosedTabs]; });
}

void DPChatInstallTabs(void) { DPHook(DPDiaWebContents, @selector(closeWithForegroundCommitTiming:), (IMP)DPChatPage_close); }
