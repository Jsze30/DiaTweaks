#import "Host.h"

// Dia's onboarding card and suggested prompts sit over our transcript.
// Hiding them makes Dia lay out again and again until AppKit aborts, so they go clear instead.
static BOOL DPChatCoversHints(NSView *hints) { return DPChatConversationFor(hints.superview) != nil; }

void DPChatClearHints(NSView *container) {
    BOOL covered = DPChatConversationFor(container) != nil;
    for (NSView *view in container.subviews) if (DPIsKind(view, DPDiaChatHints)) view.alphaValue = covered ? 0 : 1;
}

static void DPChatHints_setAlphaValue(NSView *self, SEL _cmd, CGFloat alpha) {
    DPCallOriginal(DPChatHints_setAlphaValue, self, DPChatCoversHints(self) ? 0 : alpha);  // Dia fades them in.
}

static NSView *DPChatHints_hitTest(NSView *self, SEL _cmd, NSPoint point) {
    return DPChatCoversHints(self) ? nil : DPCallOriginal(DPChatHints_hitTest, self, point);
}

void DPChatInstallHints(void) {
    DPHook(DPDiaChatHints, @selector(setAlphaValue:), (IMP)DPChatHints_setAlphaValue);
    DPHook(DPDiaChatHints, @selector(hitTest:), (IMP)DPChatHints_hitTest);
}
