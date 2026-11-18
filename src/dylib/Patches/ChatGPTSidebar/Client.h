#import <Foundation/Foundation.h>

typedef void (^DPChatReply)(NSDictionary *result, NSString *error);
NSString *DPChatExecutable(void);
NSString *DPChatHome(void);
NSDictionary *DPChatEnvironment(NSString *executable);
NSArray *DPChatArguments(void);

@interface DPChatClient : NSObject
@property(copy) void (^event)(NSString *method, NSDictionary *params);
@property(copy) void (^failed)(NSString *message);
@property(copy) void (^serve)(NSString *method, NSDictionary *params, DPChatReply reply);  // Codex's requests to us
@property NSTask *task;
@property NSFileHandle *input, *output;
@property NSMutableData *buffer;
@property NSMutableDictionary<NSNumber *, DPChatReply> *pending;
@property NSUInteger sequence;
@property BOOL stopping;
- (void)start:(DPChatReply)done;
- (void)request:(NSString *)method params:(NSDictionary *)params done:(DPChatReply)done;
- (void)write:(NSDictionary *)message;
- (void)fail:(NSString *)message;
- (void)stop;
@end

@interface DPChatClient (Protocol)
- (void)receive:(NSData *)data;
@end
