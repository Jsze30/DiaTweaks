#import "Client.h"

@implementation DPChatClient (Protocol)
- (void)receive:(NSData *)data {
    [self.buffer appendData:data];
    if (self.buffer.length > 8 * 1024 * 1024) return [self fail:@"Codex sent an oversized response."];
    while (self.buffer.length) {
        const void *newline = memchr(self.buffer.bytes, '\n', self.buffer.length);
        if (!newline) break;
        NSUInteger count = (const char *)newline - (const char *)self.buffer.bytes;
        NSData *line = [self.buffer subdataWithRange:NSMakeRange(0, count)];
        [self.buffer replaceBytesInRange:NSMakeRange(0, count + 1) withBytes:NULL length:0];
        if (!count) continue;
        id message = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
        if (![message isKindOfClass:NSDictionary.class]) return [self fail:@"Codex sent an invalid response."];
        NSString *method = message[@"method"];
        id identifier = message[@"id"];
        if (method && identifier) {
            __weak DPChatClient *weak = self;
            NSTask *task = self.task;
            DPChatReply reply = ^(NSDictionary *result, NSString *error) {
                if (weak.task != task) return;  // Codex restarted, so nobody is waiting for the answer.
                [weak write:error ? @{@"id": identifier, @"error": @{@"code": @(-32601), @"message": error}} : @{@"id": identifier, @"result": result}];
            };
            NSDictionary *params = [message[@"params"] isKindOfClass:NSDictionary.class] ? message[@"params"] : @{};
            if (self.serve && [method isKindOfClass:NSString.class]) self.serve(method, params, reply);
            else reply(nil, @"Tools are not available in the browser chat.");
        } else if (identifier) {
            DPChatReply done = self.pending[identifier];
            [self.pending removeObjectForKey:identifier];
            NSDictionary *error = message[@"error"];
            if (done) done([message[@"result"] isKindOfClass:NSDictionary.class] ? message[@"result"] : @{},
                           [error isKindOfClass:NSDictionary.class] ? error[@"message"] ?: @"Codex request failed." : nil);
        } else if ([method isKindOfClass:NSString.class] && self.event) {
            self.event(method, [message[@"params"] isKindOfClass:NSDictionary.class] ? message[@"params"] : @{});
        }
    }
}
@end
