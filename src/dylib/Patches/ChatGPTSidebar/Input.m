#import "Host.h"
#import "Patches/CommandBar/Tabs.h"

// Sends what's typed in Dia's own composer to ChatGPT instead of Dia's chat.

static NSTextView *DPChatTextView(NSView *composer) {
    NSTextView *text = (NSTextView *)DPFindView(composer, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSTextView.class] && [NSStringFromClass(view.class) hasPrefix:@"_TtCC15BoostCommandBar"];
    });
    return text ?: (NSTextView *)DPFindView(composer, ^BOOL(NSView *view) { return [view isKindOfClass:NSTextView.class] && ((NSTextView *)view).editable; });
}

// The @-mention picker is open, so Return and Escape belong to it.
static BOOL DPChatPicking(NSView *composer) {
    return DPFindView(composer, ^BOOL(NSView *view) {
        return DPIsKind(view, DPDiaCommandBarSuggestions) && !view.isHiddenOrHasHiddenAncestor && NSHeight(view.frame) > 0.5;
    }) != nil;
}

static void DPChatSubmit(NSView *composer, NSTextView *textView) {
    DPChatConversation *conversation = DPChatConversationFor(composer);
    if (!conversation || !textView) return;
    NSString *text = [textView.string stringByReplacingOccurrencesOfString:@"￼" withString:@""];
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length) {
        if (conversation.busy) [conversation stop];
        return;
    }
    if (conversation.busy) return;
    [textView setString:@""];
    [textView didChangeText];  // So Dia updates its send button.
    // Once Dia's own chat in this sidebar has messages, Dia stops showing the tab's chip but still means the tab.
    NSView *chips = DPFindView(composer, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaChatAttachments); });
    NSString *tab = [DPScriptTab(composer.window, DPActiveTabID(composer.window)) valueForKey:@"URL"];
    NSURL *url = tab.length ? [NSURL URLWithString:tab] : nil;
    [conversation send:text pages:chips ? DPChatAttachedURLs(chips) : url ? @[ url ] : @[]];
}

static NSEvent *DPChatKeyDown(NSEvent *event) {
    if (!DPChatGPTSidebar.on) return event;
    NSTextView *textView = (NSTextView *)event.window.firstResponder;
    if (![textView isKindOfClass:NSTextView.class]) return event;
    NSView *composer = DPChatComposerFor(textView);
    if (!composer || DPChatPicking(composer)) return event;
    NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagControl);
    if (event.keyCode == 53 && !mods) {
        DPChatConversation *conversation = DPChatConversationFor(composer);
        if (!conversation.busy) return event;
        [conversation stop];
        return nil;
    }
    if ((event.keyCode == 36 || event.keyCode == 76) && !mods && !textView.hasMarkedText) {
        DPChatSubmit(composer, textView);
        return nil;
    }
    return event;
}

static NSEvent *DPChatMouseDown(NSEvent *event) {
    if (!DPChatGPTSidebar.on || !event.window) return event;
    NSView *frame = event.window.contentView.superview ?: event.window.contentView;
    for (NSView *view = [frame hitTest:event.locationInWindow]; view; view = view.superview) {
        if (DPHasLabel(view, @"Send prompt")) {
            NSView *composer = DPChatComposerFor(view);
            if (!composer) return event;
            DPChatSubmit(composer, DPChatTextView(composer));
            return nil;  // Dia's button sends in mouseDown, so it must not see this click.
        }
        // Dia's New chat button doesn't hit-test itself, so find it under the click.
        if (DPIsKind(view, DPDiaChatHeader)) {
            NSView *button = DPFindView(view, ^BOOL(NSView *sub) { return DPHasLabel(sub, @"New chat"); });
            if (button && NSPointInRect([button convertPoint:event.locationInWindow fromView:nil], button.bounds)) [DPChatConversationFor(view) reset];
            return event;  // Dia resets its own chat too.
        }
    }
    return event;
}

void DPChatInstallInput(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) { return DPChatKeyDown(event); }];
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *event) { return DPChatMouseDown(event); }];
}
