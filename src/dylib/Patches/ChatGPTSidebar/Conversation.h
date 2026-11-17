#import "Sidebar.h"

@interface DPChatConversation ()
@property(readwrite) NSMutableArray<DPChatMessage *> *messages;
@property(readwrite) BOOL busy;
@property(copy) NSString *threadID, *turnID, *queued, *sharedPages;
@property(copy) NSArray<NSURL *> *pages;
@property NSUInteger generation;
@end

@interface DPChatConversation (Private)
- (void)notify:(BOOL)streaming;
- (void)fail:(NSString *)problem;
@end
