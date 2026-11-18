#import "Client.h"

@implementation DPChatClient
- (void)start:(DPChatReply)done {
    if (self.task) return done(nil, @"Chat is already connecting.");
    NSString *path = DPChatExecutable();
    if (!path) return done(nil, @"Codex was not found. Choose its executable in this tweak's settings.");
    NSString *workspace = [DPChatHome() stringByAppendingPathComponent:@"workspace"];
    NSError *error;
    if (![NSFileManager.defaultManager createDirectoryAtPath:workspace withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions: @0700} error:&error]) return done(nil, error.localizedDescription);
    self.stopping = NO;
    self.pending = [NSMutableDictionary new];
    self.buffer = [NSMutableData new];
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = DPChatArguments();
    task.environment = DPChatEnvironment(path);
    task.currentDirectoryURL = [NSURL fileURLWithPath:workspace];
    NSPipe *input = [NSPipe pipe], *output = [NSPipe pipe];
    task.standardInput = input;
    task.standardOutput = output;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    self.input = input.fileHandleForWriting;
    self.output = output.fileHandleForReading;
    self.task = task;
    __weak DPChatClient *weak = self;
    self.output.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data;
        @try { data = handle.availableData; } @catch (NSException *exception) { data = nil; }
        if (!data.length) handle.readabilityHandler = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weak.task != task) return;
            if (data.length) [weak receive:data];
            else if (!weak.stopping) [weak fail:@"Codex disconnected. Reconnect to start a new chat."];
        });
    };
    if (![task launchAndReturnError:&error]) { [self stop]; return done(nil, error.localizedDescription); }
    [self request:@"initialize" params:@{@"clientInfo": @{@"name": @"diatweaks", @"title": @"DiaTweaks", @"version": @"1.0"},
                                                         @"capabilities": @{@"experimentalApi": @YES}}
        done:^(NSDictionary *result, NSString *problem) {
            if (!problem) [weak write:@{@"method": @"initialized", @"params": @{}}];
            done(result, problem);
        }];
}

- (void)request:(NSString *)method params:(NSDictionary *)params done:(DPChatReply)done {
    if (!self.task.running) return done(nil, @"Codex is not connected.");
    NSNumber *key = @(++self.sequence);
    self.pending[key] = [done copy];
    [self write:@{@"id": key, @"method": method, @"params": params}];
    __weak DPChatClient *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (weak.pending[key]) [weak fail:@"Codex took too long to respond. Reconnect and try again."];
    });
}

- (void)write:(NSDictionary *)message {
    if (!self.input) return;
    NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:message options:0 error:nil] mutableCopy];
    [data appendBytes:"\n" length:1];
    NSError *error;
    if (![self.input writeData:data error:&error]) [self fail:@"Could not send a message to Codex."];
}

- (void)fail:(NSString *)message {
    NSDictionary *pending = self.pending.copy;
    [self.pending removeAllObjects];
    [self stop];
    for (DPChatReply reply in pending.allValues) reply(nil, message);
    if (self.failed) self.failed(message);
}

- (void)stop {
    self.stopping = YES;
    self.output.readabilityHandler = nil;
    [self.input closeAndReturnError:nil];
    self.input = nil;
    [self.output closeAndReturnError:nil];
    self.output = nil;
    NSTask *task = self.task;
    self.task = nil;
    [self.pending removeAllObjects];
    if (task.running) [task terminate];
}
- (void)dealloc { [self stop]; }
@end
