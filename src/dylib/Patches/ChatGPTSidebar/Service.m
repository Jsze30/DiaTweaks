#import "Sidebar.h"

NSNotificationName const DPChatServiceDidChange = @"DPChatServiceDidChange";
NSNotificationName const DPChatServiceEvent = @"DPChatServiceEvent";

@interface DPChatService ()
@property(readwrite) DPChatClient *client;
@property(readwrite) BOOL connecting, signedIn, signingIn, checked;
@property(readwrite, copy) NSString *problem, *loginID;
@end

@implementation DPChatService
+ (instancetype)shared {
    static DPChatService *shared;
    if (!shared) shared = [DPChatService new];
    return shared;
}

- (void)changed { [NSNotificationCenter.defaultCenter postNotificationName:DPChatServiceDidChange object:self]; }

- (void)connect {
    if (self.client.task || self.connecting) return;
    self.connecting = YES;
    self.problem = nil;
    [self changed];
    DPChatClient *client = [DPChatClient new];
    self.client = client;
    __weak DPChatService *weak = self;
    client.event = ^(NSString *method, NSDictionary *params) { [weak event:method params:params]; };
    client.serve = ^(NSString *method, NSDictionary *params, DPChatReply reply) { DPChatServe(method, params, reply); };
    client.failed = ^(NSString *message) {
        weak.connecting = weak.signedIn = weak.signingIn = NO;
        weak.problem = message;
        [weak changed];
    };
    [client start:^(NSDictionary *result, NSString *error) {
        if (error) {
            weak.connecting = NO;
            weak.problem = error;
            [weak changed];
        } else [weak readAccount];
    }];
}

- (void)readAccount {
    __weak DPChatService *weak = self;
    [self.client request:@"account/read" params:@{} done:^(NSDictionary *result, NSString *error) {
        NSDictionary *account = [result[@"account"] isKindOfClass:NSDictionary.class] ? result[@"account"] : nil;
        weak.connecting = NO;
        weak.checked = YES;
        weak.problem = error;
        weak.signedIn = [account[@"type"] isEqual:@"chatgpt"];
        [weak changed];
    }];
}

- (void)signIn {
    if (!self.client.task) return [self connect];
    if (self.signedIn || self.signingIn) return;
    self.signingIn = YES;
    self.problem = nil;
    [self changed];
    __weak DPChatService *weak = self;
    [self.client request:@"account/login/start" params:@{@"type": @"chatgpt"} done:^(NSDictionary *login, NSString *error) {
        NSURL *url = [NSURL URLWithString:[login[@"authUrl"] isKindOfClass:NSString.class] ? login[@"authUrl"] : @""];
        BOOL safe = [url.scheme isEqual:@"https"] && [@[@"auth.openai.com", @"chatgpt.com"] containsObject:url.host];
        if (error || !safe || ![NSWorkspace.sharedWorkspace openURL:url]) {
            weak.signingIn = NO;
            weak.problem = error ?: @"Couldn't open the ChatGPT sign-in page.";
        } else weak.loginID = login[@"loginId"];
        [weak changed];
    }];
}

- (void)signOut {
    if (!self.signedIn) return;
    __weak DPChatService *weak = self;
    [self.client request:@"account/logout" params:@{} done:^(NSDictionary *result, NSString *error) {
        weak.problem = error;
        if (!error) weak.signedIn = NO;
        [weak changed];
    }];
}

- (void)event:(NSString *)method params:(NSDictionary *)params {
    if ([method isEqual:@"account/login/completed"]) {
        if (self.loginID && ![params[@"loginId"] isEqual:self.loginID]) return;
        self.loginID = nil;
        self.signingIn = NO;
        if ([params[@"success"] boolValue]) return [self readAccount];
        self.problem = [params[@"error"] isKindOfClass:NSString.class] ? params[@"error"] : @"Sign-in didn't finish.";
        return [self changed];
    }
    if ([method isEqual:@"account/updated"]) {
        self.signedIn = [params[@"authMode"] isEqual:@"chatgpt"];
        return [self changed];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:DPChatServiceEvent object:self
                                                    userInfo:@{@"method": method, @"params": params}];
}

- (void)shutdown {
    [self.client stop];
    self.client = nil;
    self.connecting = self.signedIn = self.signingIn = NO;
    self.loginID = nil;
    [self changed];
}
@end
