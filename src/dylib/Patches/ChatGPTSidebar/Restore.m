#import "Sidebar.h"
#import "Conversation.h"

// Codex keeps each chat on disk, so a tab's chat comes back after Dia restarts.

// What the user typed, without the pages that went along with it.
static NSString *DPChatTyped(NSDictionary *item) {
    NSMutableString *text = [NSMutableString new];
    for (NSDictionary *part in [item[@"content"] isKindOfClass:NSArray.class] ? item[@"content"] : @[])
        if ([part isKindOfClass:NSDictionary.class] && [part[@"text"] isKindOfClass:NSString.class]) [text appendString:part[@"text"]];
    // What follows the typed text is the pages and the time, which the user never typed.
    NSUInteger end = text.length;
    for (NSString *mark in @[@"\n\n<page>\n", @"\n\n<context>\n"]) end = MIN(end, [text rangeOfString:mark].location);
    return [text substringToIndex:end];
}

@implementation DPChatConversation (Restore)
- (void)restore {
    self.restoring = !DPChatService.shared.signedIn;
    if (!self.restoring && self.threadID && !self.resumed) [self resume:nil];
}

// Codex must load a saved chat before it takes a turn; an empty transcript also gets the chat's messages back.
- (void)resume:(void (^)(void))done {
    __weak DPChatConversation *weak = self;
    NSString *thread = self.threadID;
    NSMutableDictionary *params = [self.threadParams mutableCopy];
    params[@"threadId"] = thread;
    [DPChatService.shared.client request:@"thread/resume" params:params done:^(NSDictionary *result, NSString *error) {
        if (!weak || ![weak.threadID isEqual:thread]) return;
        NSDictionary *chat = [result[@"thread"] isKindOfClass:NSDictionary.class] ? result[@"thread"] : nil;
        if (error || !chat) {
            weak.threadID = nil;  // Codex no longer has it, so the next message starts a new chat.
            [weak saveThread];
        } else {
            weak.resumed = YES;
            if (!weak.messages.count) [weak show:chat];
        }
        if (done) done();
    }];
}

- (void)show:(NSDictionary *)thread {
    for (NSDictionary *turn in [thread[@"turns"] isKindOfClass:NSArray.class] ? thread[@"turns"] : @[]) {
        if (![turn isKindOfClass:NSDictionary.class]) continue;
        DPChatMessage *answer = nil;  // the turn's last message, as the live chat shows it
        for (NSDictionary *item in [turn[@"items"] isKindOfClass:NSArray.class] ? turn[@"items"] : @[]) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            BOOL user = [item[@"type"] isEqual:@"userMessage"];
            NSString *text = user ? DPChatTyped(item) : [item[@"type"] isEqual:@"agentMessage"] ? item[@"text"] : nil;
            if (![text isKindOfClass:NSString.class] || !text.length) continue;
            if (!user && answer) { answer.text = text; continue; }
            DPChatMessage *message = [DPChatMessage new];
            message.text = text;
            message.fromUser = user;
            if (!user) answer = message;
            [self.messages addObject:message];
        }
    }
    [self notify:NO];
}
@end
