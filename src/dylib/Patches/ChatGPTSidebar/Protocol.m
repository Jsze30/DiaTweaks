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
            // This is a chat client. Never approve command execution, file changes, or external tool requests.
            [self write:@{@"id": identifier, @"error": @{@"code": @(-32601), @"message": @"Tools are not available in the browser chat."}}];
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
