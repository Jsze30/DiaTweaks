#import "Sidebar.h"

static void DPChatApply(DPPatch *patch) { DPChatApplyHost(); }

static NSString *DPChatVerify(DPPatch *patch) {
    // Dia's chats on screen, in the sidebar or in their own tab: what holds the prompt queue.
    for (NSView *queue in DPFindViews(DPDiaChatQueue)) {
        NSView *chat = queue.superview;
        if (!chat.window || chat.isHiddenOrHasHiddenAncestor) continue;
        NSView *page = DPFindView(chat, ^BOOL(NSView *view) { return DPIsKind(view, "WebContentsHostView"); });
        NSView *hints = DPFindView(chat, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaChatHints) && !view.isHiddenOrHasHiddenAncestor; });
        if (patch->on) {
            if (!DPFindView(chat, ^BOOL(NSView *view) { return DPIsKind(view, "DPChatTranscript"); })) return @"Dia's chat has no ChatGPT messages";
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
    .title = @"Enable ChatGPT",
    .detail = @"Dia's chat answers with ChatGPT, using your Codex sign-in.",
    .symbol = @"bubble.left.and.text.bubble.right.fill bubble.left.and.bubble.right.fill",
    .tint = @"systemPurpleColor",
    .classes = DPClasses(DPChatSidebarClass, DPDiaAssistantPanel, DPDiaCommandBar, DPDiaChatQueue),
    .disabledBy = @"turnOffAI",
    .rows = DPChatSettings,
    .install = DPChatInstallHost,
    .apply = DPChatApply,
    .verify = DPChatVerify,
};
