#import "Host.h"

// Asking from Dia's command bar (such as on a new tab) sends the question straight to Dia's own AI, in a new chat.
// Its dispatch is Swift with nothing to hook, so the question is taken at the bar instead: Dia never gets it, and
// ChatGPT answers it in the window's chat.

static NSString *gAsked;
static __weak NSWindow *gAskedWindow;
static CFTimeInterval gAskedAt;
static BOOL gSwallowMouseUp;

NSString *DPChatTakeAsked(NSWindow *window) {
    if (!gAsked || window != gAskedWindow || CACurrentMediaTime() - gAskedAt > 10) return nil;
    NSString *asked = gAsked;
    gAsked = nil;
    return asked;
}

// Dia's command bar, told from a chat composer (the same view) by its list of results.
static NSView *DPChatBarOf(NSView *view) {
    for (; view && !DPIsKind(view, DPDiaCommandBar); view = view.superview);
    BOOL results = DPFindView(view, ^BOOL(NSView *sub) { return DPIsKind(sub, DPDiaCommandBarSuggestions) && !sub.isHiddenOrHasHiddenAncestor && NSHeight(sub.frame) > 0.5; }) != nil;
    return results ? view : nil;
}

// A row that asks Dia's AI has the chat bubble for its icon, as does the bar itself once it is set to chat.
static BOOL DPChatAsks(NSView *view) {
    return DPFindView(view, ^BOOL(NSView *sub) { return DPHasLabel(sub, @"chat") && !sub.isHiddenOrHasHiddenAncestor; }) != nil;
}

static NSString *DPChatBarText(NSView *bar) {
    NSTextView *text = (NSTextView *)DPFindView(bar, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextView.class]; });
    NSString *typed = [text.string stringByReplacingOccurrencesOfString:@"￼" withString:@""];
    return [typed stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static void DPChatAsk(NSView *bar) {
    NSString *text = DPChatBarText(bar);
    NSWindow *window = bar.window;
    if (!text.length || !window) return;
    // Escape closes the bar as if the user had, and the Command Bar tweak closes the new tab it opened. Not from inside the event.
    dispatch_async(dispatch_get_main_queue(), ^{
        for (int up = 0; up < 2; up++)
            [NSApp sendEvent:[NSEvent keyEventWithType:up ? NSEventTypeKeyUp : NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                             timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
                                            characters:@"\e" charactersIgnoringModifiers:@"\e" isARepeat:NO keyCode:53]];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DPChatConversation *shown = DPChatShownIn(window);
        if (shown) return [shown send:text pages:@[]];
        // Otherwise the chat opens beside the tab the bar left, or as Dia's New Chat, and takes the question as it shows.
        gAsked = text, gAskedWindow = window, gAskedAt = CACurrentMediaTime();
        NSView *open = DPFindView(window.contentView.superview, ^BOOL(NSView *view) { return DPHasLabel(view, @"Chat with this tab") && !view.isHiddenOrHasHiddenAncestor; });
        if (open) return (void)[open accessibilityPerformPress];
        NSMenuItem *newChat = [[NSApp.mainMenu itemWithTitle:@"File"].submenu itemWithTitle:@"New Chat"];
        if (newChat.action) [NSApp sendAction:newChat.action to:newChat.target from:newChat];
    });
}

// Return asks when the chosen row is a chat row; ⌃⌘Return always asks.
BOOL DPChatBarKey(NSEvent *event, NSTextView *textView) {
    NSView *bar = DPChatBarOf(textView);
    if (!bar || textView.hasMarkedText || (event.keyCode != 36 && event.keyCode != 76)) return NO;
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagControl);
    NSView *chosen = DPFindView(bar, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSTableRowView.class] && ((NSTableRowView *)view).selected && !view.isHiddenOrHasHiddenAncestor;
    });
    BOOL asks = mods == (NSEventModifierFlagControl | NSEventModifierFlagCommand) || (!mods && (chosen ? DPChatAsks(chosen) : DPChatAsks(bar)));
    if (!asks || !DPChatBarText(bar).length) return NO;
    DPChatAsk(bar);
    return YES;
}

// A click on a chat row, or on the bar's Chat button.
BOOL DPChatBarClick(NSEvent *event, NSView *hit) {
    NSView *bar = DPChatBarOf(hit);
    if (!bar) return NO;
    for (NSView *view = hit; view && view != bar; view = view.superview) {
        BOOL row = [view isKindOfClass:NSTableRowView.class] && DPChatAsks(view);
        BOOL button = DPIsKind(view, "_TtC15BoostCommandBar13ToolbarButton") && [view.accessibilityTitle hasPrefix:@"Chat"];
        if (!row && !button) continue;
        DPChatAsk(bar);
        gSwallowMouseUp = YES;
        return YES;
    }
    return NO;
}

// Dia acts on the click's mouse-up, so that goes too.
BOOL DPChatBarMouseUp(void) {
    BOOL swallow = gSwallowMouseUp;
    gSwallowMouseUp = NO;
    return swallow;
}
