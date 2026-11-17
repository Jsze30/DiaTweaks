#import "Host.h"
#import "Patches/CommandBar/Tabs.h"

// Swaps only Dia's web-rendered message list for our transcript, keeping its header and composer.
@interface DPChatHost : NSObject
@property(weak) NSViewController *sidebar;
@property(weak) NSView *panel, *container;
@property(nonatomic, weak) NSView *composer;
@property(weak) NSWindow *window;
@property(copy) NSString *tab;
@property(nonatomic) NSView *wrapper;  // Strong, so its observer is always removed.
@property DPChatTranscript *transcript;
@property DPChatConversation *conversation;
@property BOOL wrapperWasHidden, enforcing;
@end

static NSHashTable<NSViewController *> *gSidebars;
static NSHashTable<DPChatHost *> *gHosts;
static char gHostKey;
static int gHiddenContext;

@implementation DPChatHost
// Dia may show its message list again at any time, so hide it back and remember what Dia wanted.
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &gHiddenContext) return [super observeValueForKeyPath:path ofObject:object change:change context:context];
    if (self.enforcing) return;
    self.wrapperWasHidden = self.wrapper.hidden;
    [self enforce];
}

- (void)enforce {
    if (!self.wrapper || self.wrapper.hidden || self.enforcing) return;
    self.wrapperWasHidden = NO;
    self.enforcing = YES;
    self.wrapper.hidden = YES;
    self.enforcing = NO;
}

- (void)setWrapper:(NSView *)wrapper restore:(BOOL)restore {
    if (wrapper == _wrapper) return;
    if (_wrapper) {
        [_wrapper removeObserver:self forKeyPath:@"hidden" context:&gHiddenContext];
        if (restore) _wrapper.hidden = self.wrapperWasHidden;
    }
    _wrapper = wrapper;
    if (!wrapper) return;
    self.wrapperWasHidden = wrapper.hidden;
    [wrapper addObserver:self forKeyPath:@"hidden" options:0 context:&gHiddenContext];
    [self enforce];
}

- (void)setComposer:(NSView *)composer {
    if (_composer == composer) return;
    if (_composer) [NSNotificationCenter.defaultCenter removeObserver:self name:NSViewFrameDidChangeNotification object:_composer];
    _composer = composer;
    self.transcript.composer = composer;
    if (!composer) return;
    composer.postsFrameChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(composerMoved:) name:NSViewFrameDidChangeNotification object:composer];
}

- (void)composerMoved:(NSNotification *)note { self.transcript.needsLayout = YES; }

- (void)dealloc {
    [self setWrapper:nil restore:NO];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
@end

static void DPChatDetach(DPChatHost *host) {
    [host.transcript removeFromSuperview];
    host.transcript = nil;
    [host setWrapper:nil restore:YES];
    host.composer = nil;
    for (id owner in @[ host.sidebar ?: NSNull.null, host.panel ?: NSNull.null, host.container ?: NSNull.null ])
        if (owner != NSNull.null && DPGet(owner, &gHostKey) == host) DPSet(owner, &gHostKey, nil);
    DPChatClearHints(host.container);
    [gHosts removeObject:host];
}

// panel root > ... > container > { web wrapper > ... > WebContentsHostView, composer > ... > command bar }
static BOOL DPChatResolve(NSView *root, NSView **panel, NSView **container, NSView **wrapper, NSView **composer) {
    *panel = DPFindView(root, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaAssistantPanel) && DPFindView(view, ^BOOL(NSView *sub) { return DPHasLabel(sub, @"Hide chat"); });
    });
    NSView *web = DPFindView(*panel, ^BOOL(NSView *view) { return DPIsKind(view, "WebContentsHostView"); });
    for (NSView *view = web; view && view != *panel; view = view.superview)
        for (NSView *sibling in view.superview.subviews)
            if (sibling != view && DPFindView(sibling, ^BOOL(NSView *sub) { return DPIsKind(sub, DPDiaCommandBar); })) {
                *container = view.superview, *wrapper = view, *composer = sibling;
                return YES;
            }
    return NO;
}

static void DPChatAttach(NSViewController *sidebar) {
    if (!DPChatGPTSidebar.on || !sidebar.viewLoaded) return;
    NSView *panel = nil, *container = nil, *wrapper = nil, *composer = nil;
    if (!DPChatResolve(sidebar.view, &panel, &container, &wrapper, &composer) || !container.window) return;
    NSString *tab = DPActiveTabID(container.window);  // The sidebar on screen is the front tab's.
    if (!tab) return;
    DPChatHost *previous = DPGet(sidebar, &gHostKey), *host = DPGet(container, &gHostKey);
    if (host && host.window != container.window) DPChatDetach(host), host = nil;  // Dia moved the panel to another window.
    DPChatConversation *chat = [DPChatConversation forTab:tab window:container.window];
    // A window has one sidebar, and each tab keeps its own chat view in it, so another tab's view stays as it is.
    // A new chat view for the same tab means Dia started a new chat (button, menu or shortcut).
    if (previous && previous != host && [previous.tab isEqual:tab]) {
        if (previous.window == container.window) [chat reset];
        DPChatDetach(previous);
    }
    if (!host) {
        host = [DPChatHost new];
        host.window = container.window;
        host.transcript = [[DPChatTranscript alloc] initWithConversation:nil];
        host.transcript.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        host.container = container;
        DPSet(container, &gHostKey, host);
        [gHosts addObject:host];
        if (!DPTesting) [DPChatService.shared connect];
    }
    if (host.conversation != chat) host.conversation = host.transcript.conversation = chat;
    host.sidebar = sidebar, host.panel = panel, host.composer = composer, host.tab = tab;
    DPSet(sidebar, &gHostKey, host);
    DPSet(panel, &gHostKey, host);
    NSArray<NSView *> *subviews = container.subviews;
    if (host.transcript.superview != container || [subviews indexOfObject:host.transcript] > [subviews indexOfObject:composer]) {
        [host.transcript removeFromSuperview];
        [container addSubview:host.transcript positioned:NSWindowBelow relativeTo:composer];
    }
    if (!NSEqualRects(host.transcript.frame, container.bounds)) host.transcript.frame = container.bounds;
    [host setWrapper:wrapper restore:YES];
    [host enforce];
    // Dia opens a question from its command bar in a chat tab, the one kind of tab with no web address.
    id url = [DPScriptTab(container.window, tab) valueForKey:@"URL"];
    if (!chat.messages.count && !chat.busy && !([url isKindOfClass:NSString.class] && [url length])) {
        NSString *asked = DPChatTakeAsked(container.window);
        if (asked.length) [chat send:asked pages:@[]];
    }
    DPChatClearHints(container);
}

static void DPChatSidebar_viewWillLayout(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPChatSidebar_viewWillLayout, self);
    [gSidebars addObject:self];
    DPChatAttach(self);
}

// Dia's new chat view doesn't lay out the sidebar again, so attach when its composer shows up.
static void DPChatComposer_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPChatComposer_viewDidMoveToWindow, self);
    if (self.window && DPChatGPTSidebar.on) dispatch_async(dispatch_get_main_queue(), ^{ DPChatApplyHost(); });
}

DPChatConversation *DPChatConversationFor(NSView *view) {
    for (; view; view = view.superview) {
        DPChatHost *host = DPGet(view, &gHostKey);
        if (host.transcript) return host.conversation;
    }
    return nil;
}

NSView *DPChatComposerFor(NSView *view) {
    for (NSView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        DPChatHost *host = DPGet(ancestor, &gHostKey);
        if (host.transcript && host.composer && [view isDescendantOf:host.composer]) return host.composer;
    }
    return nil;
}

void DPChatApplyHost(void) {
    if (DPChatGPTSidebar.on) {
        for (NSViewController *sidebar in gSidebars.allObjects) DPChatAttach(sidebar);
        return;
    }
    for (DPChatHost *host in gHosts.allObjects) DPChatDetach(host);
    [DPChatService.shared shutdown];
}

void DPChatInstallHost(void) {
    gSidebars = [NSHashTable weakObjectsHashTable];
    gHosts = [NSHashTable weakObjectsHashTable];
    DPHook(DPChatSidebarClass, @selector(viewWillLayout), (IMP)DPChatSidebar_viewWillLayout);
    DPHook(DPDiaCommandBar, @selector(viewDidMoveToWindow), (IMP)DPChatComposer_viewDidMoveToWindow);
    DPChatInstallInput();
    DPChatInstallHints();
    DPChatInstallTabs();
    DPOnQuit(^{ for (DPChatHost *host in gHosts.allObjects) DPChatDetach(host); });
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        for (DPChatHost *host in gHosts.allObjects)
            if (host.window == note.object) DPChatDetach(host);
    }];
}
