#import "Sidebar.h"

static void DPChatApply(DPPatch *patch) { DPChatApplyHost(); }

// Dia's chat sidebar panels on screen: the ones with a Hide chat button.
static NSArray<NSView *> *DPChatPanels(void) {
    NSMutableArray<NSView *> *panels = [NSMutableArray new];
    for (NSView *panel in DPFindViews(DPDiaAssistantPanel))
        if (!panel.isHiddenOrHasHiddenAncestor && DPFindView(panel, ^BOOL(NSView *view) { return DPHasLabel(view, @"Hide chat"); }))
            [panels addObject:panel];
    return panels;
}

static NSString *DPChatVerify(DPPatch *patch) {
    for (NSView *panel in DPChatPanels()) {
        NSView *page = DPFindView(panel, ^BOOL(NSView *view) { return DPIsKind(view, "WebContentsHostView"); });
        NSView *hints = DPFindView(panel, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaChatHints) && !view.isHiddenOrHasHiddenAncestor; });
        if (patch->on) {
            if (!DPFindView(panel, ^BOOL(NSView *view) { return DPIsKind(view, "DPChatTranscript"); })) return @"chat sidebar has no ChatGPT messages";
            if (page && !page.isHiddenOrHasHiddenAncestor) return @"Dia's chat messages still show";
            if (hints.alphaValue > 0) return @"Dia's chat hints still show";
        } else if (page.isHiddenOrHasHiddenAncestor) return @"Dia's chat messages stay hidden after switching off";
        else if (hints && hints.alphaValue == 0) return @"Dia's chat hints stay clear after switching off";
    }
    if (!patch->on && DPFindViews("DPChatTranscript").count) return @"ChatGPT messages remain after switching off";
    return nil;
}

DP_PATCH(DPChatGPTSidebar) {
    .key = @"chatGPTSidebar",
    .order = 94,
    .section = @"AI",
    .title = @"ChatGPT Sidebar",
    .detail = @"Dia's chat sidebar answers with ChatGPT, using your ChatGPT sign-in through Codex. The tabs attached in the composer are shared with your message. Requires the Codex app or CLI.",
    .symbol = @"bubble.left.and.text.bubble.right.fill bubble.left.and.bubble.right.fill",
    .tint = @"systemPurpleColor",
    .classes = DPClasses(DPChatSidebarClass, DPDiaAssistantPanel, DPDiaCommandBar),
    .disabledBy = @"turnOffAI",
    .rows = DPChatSettings,
    .install = DPChatInstallHost,
    .apply = DPChatApply,
    .verify = DPChatVerify,
};
