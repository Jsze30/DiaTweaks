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

// A web page read for the chat; `text` is what ChatGPT gets, in <page> tags.
@interface DPChatPage : NSObject
@property(copy) NSString *url, *title, *text;
@property NSImage *icon;
@end

@interface DPChatMessage : NSObject
@property BOOL fromUser, failed, pending;
@property(copy) NSString *text;
@property DPChatPage *page;  // the first page sent along with this message
@end

// One chat per tab, kept by the tab's ID so it survives Dia rebuilding the sidebar.
@interface DPChatConversation : NSObject
@property(readonly) NSMutableArray<DPChatMessage *> *messages;
@property(readonly) BOOL busy;
@property(copy) void (^changed)(BOOL streaming);
// `pages` are the web addresses of the tabs attached to the composer.
- (void)send:(NSString *)prompt pages:(NSArray<NSURL *> *)pages;
- (void)stop;
- (void)reset;
@end

@interface DPChatConversation (Tabs)
// Saved with Codex's thread ID, so it survives Dia restarting.
// `diaChat` is Dia's ID for the chat on screen, which it keeps when it moves the chat to a tab of its own (full window).
+ (instancetype)forTab:(NSString *)tab window:(NSWindow *)window diaChat:(NSString *)diaChat;
// Drops the chats of tabs that were closed.
+ (void)forgetClosedTabs;
@end

@interface DPChatTranscript : NSView
@property(weak) NSView *composer;
@property(weak) DPChatConversation *conversation;
- (instancetype)initWithConversation:(DPChatConversation *)conversation;
- (void)reload;
@end

void DPChatInstallHost(void);
void DPChatApplyHost(void);
// The pages that could be read, in order, and a key that changes when the URLs do.
void DPChatPages(NSArray<NSURL *> *urls, void (^done)(NSString *key, NSArray<DPChatPage *> *pages));
NSArray<NSURL *> *DPChatAttachedURLs(NSView *chips);
NSAttributedString *DPChatMarkdown(NSString *markdown, CGFloat size);
NSArray<NSView *> *DPChatSettings(void);
// The browser tools ChatGPT gets, and the answer to each request Codex sends: a tool call or an approval.
NSArray *DPChatTools(void);
void DPChatServe(NSString *method, NSDictionary *params, DPChatReply reply);
NSString *DPChatWindowOfThread(NSString *thread);  // the Dia window whose tab owns the chat
