#import "Sidebar.h"

@interface DPChatConversation ()
@property(readwrite) NSMutableArray<DPChatMessage *> *messages;
@property(readwrite) BOOL busy;
@property(weak) NSWindow *window;
@property(copy) NSString *threadID, *turnID, *queued, *sharedURL;
@property NSUInteger generation;
@end

@interface DPChatConversation (Private)
- (void)notify:(BOOL)streaming;
- (void)fail:(NSString *)problem;
@end
