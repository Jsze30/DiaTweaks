#import "StdPatch/StdPatch.h"
#import "Client.h"

#define DPChatSidebarClass "_TtC6Window30AssistantSidebarViewController"
extern DPPatch DPChatGPTSidebar;

// One Codex process serves every window. It owns sign-in and passes its events on.
@interface DPChatService : NSObject
@property(readonly) DPChatClient *client;
@property(readonly) BOOL connecting, signedIn, signingIn;
@property(readonly, copy) NSString *problem;
+ (instancetype)shared;
- (void)connect;
- (void)signIn;
- (void)signOut;
- (void)shutdown;
@end
extern NSNotificationName const DPChatServiceDidChange;
extern NSNotificationName const DPChatServiceEvent;  // userInfo: method, params

@interface DPChatMessage : NSObject
@property BOOL fromUser, failed, pending;
@property(copy) NSString *text;
@end

// One chat per window, so it survives Dia rebuilding the sidebar.
@interface DPChatConversation : NSObject
@property(readonly) NSMutableArray<DPChatMessage *> *messages;
@property(readonly) BOOL busy;
@property(copy) void (^changed)(BOOL streaming);
+ (instancetype)forWindow:(NSWindow *)window;
- (void)send:(NSString *)prompt;
- (void)stop;
- (void)reset;
@end

@interface DPChatTranscript : NSView
@property(weak) NSView *composer;
@property(weak) DPChatConversation *conversation;
- (instancetype)initWithConversation:(DPChatConversation *)conversation;
- (void)reload;
@end

void DPChatInstallHost(void);
void DPChatApplyHost(void);
void DPChatPage(NSWindow *window, void (^done)(NSString *url, NSString *text));
NSAttributedString *DPChatMarkdown(NSString *markdown, CGFloat size);
NSArray<NSView *> *DPChatSettings(void);
