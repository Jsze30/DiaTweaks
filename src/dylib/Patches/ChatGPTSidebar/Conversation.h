#import "Sidebar.h"

@interface DPChatConversation ()
@property(readwrite) NSMutableArray<DPChatMessage *> *messages;
@property(readwrite) BOOL busy;
@property(copy) NSString *threadID, *turnID, *queued, *sharedPages;
@property(copy) NSString *tab, *windowID;  // where the chat is saved
@property BOOL resumed, restoring;  // Codex has the thread loaded; waiting to sign in before loading it
@property(copy) NSArray<NSURL *> *pages;
@property NSUInteger generation;
@end

@interface DPChatConversation (Private)
- (void)notify:(BOOL)streaming;
- (void)fail:(NSString *)problem;
- (NSDictionary *)threadParams;
- (void)saveThread;
- (void)restore;
- (void)resume:(void (^)(void))done;
@end
