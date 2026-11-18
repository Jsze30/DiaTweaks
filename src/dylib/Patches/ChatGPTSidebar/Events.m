#import "Sidebar.h"
#import "Conversation.h"

@implementation DPChatConversation (Events)
- (void)serviceEvent:(NSNotification *)note {
    NSString *method = note.userInfo[@"method"];
    NSDictionary *params = note.userInfo[@"params"];
    if (!self.threadID || ![params[@"threadId"] isEqual:self.threadID] || !self.busy) return;
    DPChatMessage *last = self.messages.lastObject;
    if (!last || last.fromUser) return;
    if ([method isEqual:@"turn/started"] && [params[@"turn"] isKindOfClass:NSDictionary.class]) self.turnID = params[@"turn"][@"id"];
    // A turn that uses tools can say something before them; the next message replaces it, so only the answer stays.
    else if ([method isEqual:@"item/started"] && [params[@"item"] isKindOfClass:NSDictionary.class] && [params[@"item"][@"type"] isEqual:@"agentMessage"]) {
        if (!last.text.length) return;
        last.text = @"";
        [self notify:YES];
    } else if ([method isEqual:@"item/agentMessage/delta"] && [params[@"delta"] isKindOfClass:NSString.class]) {
        if (last.text.length + [params[@"delta"] length] > 1000000) return [self stop];
        last.text = [last.text stringByAppendingString:params[@"delta"]];
        [self notify:YES];
    } else if ([method isEqual:@"item/completed"] && [params[@"item"] isKindOfClass:NSDictionary.class]) {
        NSDictionary *item = params[@"item"];
        if ([item[@"type"] isEqual:@"agentMessage"] && [item[@"text"] isKindOfClass:NSString.class]) {
            last.text = item[@"text"];
            [self notify:YES];
        }
    } else if ([method isEqual:@"turn/completed"]) {
        NSDictionary *turn = [params[@"turn"] isKindOfClass:NSDictionary.class] ? params[@"turn"] : @{};
        NSDictionary *error = [turn[@"error"] isKindOfClass:NSDictionary.class] ? turn[@"error"] : nil;
        if (error[@"message"]) return [self fail:error[@"message"]];
        last.pending = NO;
        self.busy = NO;
        self.turnID = nil;
        [self notify:NO];
    } else if ([method isEqual:@"error"] && ![params[@"willRetry"] boolValue]) {
        NSDictionary *error = [params[@"error"] isKindOfClass:NSDictionary.class] ? params[@"error"] : @{};
        [self fail:[error[@"message"] isKindOfClass:NSString.class] ? error[@"message"] : @"ChatGPT ran into a problem. Try again."];
    }
}
@end
