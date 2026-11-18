#import "DevTools/DevTools.h"
#import "Updates/Updates.h"
#include <dlfcn.h>

static void DPDescribe(NSView *view, NSUInteger depth, NSMutableString *out) {
    NSString *label = view.accessibilityLabel;
    [out appendFormat:@"%*s%@ %@", (int)depth * 2, "", NSStringFromClass(view.class), NSStringFromRect(view.frame)];
    if (label.length) [out appendFormat:@" label=\"%@\"", label];
    if (view.layer.cornerRadius > 0)
        [out appendFormat:@" radius=%g corners=%lu", view.layer.cornerRadius, (unsigned long)view.layer.maskedCorners];
    if ([view isKindOfClass:NSTextField.class] && [(NSTextField *)view stringValue].length)
        [out appendFormat:@" text=\"%@\"", [(NSTextField *)view stringValue]];
    if ([view isKindOfClass:NSTableRowView.class] && [(NSTableRowView *)view isSelected]) [out appendString:@" selected"];
    if (view.hidden) [out appendString:@" hidden"];
    [out appendString:@"\n"];
    for (NSView *sub in view.subviews) DPDescribe(sub, depth + 1, out);
}

NSString *DPBesideDylib(NSString *name) {
    Dl_info dylib;
    dladdr((const void *)DPInstallDevTools, &dylib);
    return [@(dylib.dli_fname).stringByDeletingLastPathComponent stringByAppendingPathComponent:name];
}

NSString *DPDescribeViews(NSView *root) {
    NSMutableString *out = [NSMutableString new];
    if (root) DPDescribe(root, 0, out);
    return out;
}

static void DPCopyViewTree(void) {
    NSWindow *window = NSApp.keyWindow ?: NSApp.orderedWindows.firstObject;
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:DPDescribeViews(window.contentView.superview) forType:NSPasteboardTypeString];
}

static void DPScriptSet(NSNotification *note) {
    NSArray<NSString *> *parts = [note.object componentsSeparatedByString:@"="];
    DPPatch *patch = parts.count == 2 ? DPPatchNamed(parts[0]) : NULL;
    if (patch) DPSetPatch(patch, parts[1].boolValue, YES);
    for (NSUInteger i = 0; parts.count == 2 && i < DPPatchCount; i++)
        if ([DPPatches[i]->choice isEqualToString:parts[0]]) DPSetChoice(DPPatches[i], parts[1]);
}

static void DPScriptType(NSNotification *note) {
    id responder = (NSApp.keyWindow ?: NSApp.orderedWindows.firstObject).firstResponder;
    if (![responder isKindOfClass:NSTextView.class] || ![note.object isKindOfClass:NSString.class]) return;
    NSString *text = note.object;
    if ([text hasPrefix:@"@"]) @try { [responder doCommandBySelector:NSSelectorFromString([text substringFromIndex:1])]; } @catch (NSException *e) {}
    else if ([text hasPrefix:@"="]) [responder insertText:[text substringFromIndex:1] replacementRange:NSMakeRange(0, [[responder string] length])];
    else [responder insertText:text replacementRange:[responder selectedRange]];
}

static void DPScriptMethods(NSNotification *note) {
    NSMutableString *out = [NSMutableString new];
    NSView *live = DPFindViews([note.object UTF8String]).firstObject;
    NSMutableArray *classes = [NSMutableArray arrayWithObjects:note.object, nil];
    for (NSString *key in @[@"delegate", @"dataSource"])
        if ([live respondsToSelector:NSSelectorFromString(key)]) {
            id value = [live valueForKey:key];
            [out appendFormat:@"%@: %s\n", key, value ? object_getClassName(value) : "nil"];
            if (value) [classes addObject:@(object_getClassName(value))];
        }
    for (NSString *name in classes)
        for (Class cls = NSClassFromString(name); cls && cls != NSObject.class && cls != NSView.class && cls != NSResponder.class; cls = class_getSuperclass(cls)) {
            unsigned count = 0;
            Method *methods = class_copyMethodList(cls, &count);
            [out appendFormat:@"== %s\n", class_getName(cls)];
            for (unsigned i = 0; i < count; i++) [out appendFormat:@"  %s %s\n", sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i])];
            free(methods);
        }
    [out writeToFile:DPBesideDylib(@"methods.txt") atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// Clicks the front window's view with this accessibility label, as a real click would, so event monitors see it.
static void DPScriptClick(NSNotification *note) {
    NSWindow *window = NSApp.keyWindow ?: NSApp.mainWindow ?: NSApp.orderedWindows.firstObject;
    NSView *view = DPFindView(window.contentView.superview, ^BOOL(NSView *candidate) {
        return DPHasLabel(candidate, note.object) && !candidate.isHiddenOrHasHiddenAncestor && NSWidth(candidate.bounds) > 0;
    });
    if (!view) return;
    NSPoint point = [view convertPoint:NSMakePoint(NSMidX(view.bounds), NSMidY(view.bounds)) toView:nil];
    NSEventType types[] = {NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp};
    for (int i = 0; i < 2; i++)
        [NSApp postEvent:[NSEvent mouseEventWithType:types[i] location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                         windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:i ? 0 : 1] atStart:NO];
}

// Focuses the front window's first visible view whose class name contains this text.
static void DPScriptFocus(NSNotification *note) {
    NSWindow *window = NSApp.keyWindow ?: NSApp.mainWindow ?: NSApp.orderedWindows.firstObject;  // works with Dia in the background
    NSView *view = DPFindView(window.contentView.superview, ^BOOL(NSView *candidate) {
        return [NSStringFromClass(candidate.class) containsString:note.object] && !candidate.isHiddenOrHasHiddenAncestor && candidate.acceptsFirstResponder;
    });
    if (view) [window makeFirstResponder:view];
}

// Runs the main menu item with this title, wherever it is.
static NSMenuItem *DPMenuItemNamed(NSMenu *menu, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.title isEqual:title]) return item;
        NSMenuItem *found = item.submenu ? DPMenuItemNamed(item.submenu, title) : nil;
        if (found) return found;
    }
    return nil;
}

static void DPScriptMenu(NSNotification *note) {
    NSMenuItem *item = DPMenuItemNamed(NSApp.mainMenu, note.object);
    [item.menu update];
    if (item.enabled) [item.menu performActionForItemAtIndex:[item.menu indexOfItem:item]];
}

// Presses Return in the front window, as a real key press would.
static void DPScriptReturn(NSNotification *note) {
    NSWindow *window = NSApp.keyWindow ?: NSApp.mainWindow ?: NSApp.orderedWindows.firstObject;  // works with Dia in the background
    NSEventType types[] = {NSEventTypeKeyDown, NSEventTypeKeyUp};
    for (int i = 0; i < 2; i++)
        [NSApp postEvent:[NSEvent keyEventWithType:types[i] location:NSZeroPoint modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                                      windowNumber:window.windowNumber context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36] atStart:NO];
}

static void DPScriptDump(NSNotification *note) {
    NSMutableString *out = [NSMutableString new];
    for (NSWindow *window in NSApp.windows)
        [out appendFormat:@"== window \"%@\"\n%@", window.title, DPDescribeViews(window.contentView.superview)];
    [out writeToFile:DPBesideDylib(@"views.txt") atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void DPListen(NSString *name, void (*handler)(NSNotification *)) {
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                           usingBlock:^(NSNotification *note) { handler(note); }];
}

static void DPListenForScripts(void) {
    DPListen(@"com.diapatches.dev.set", DPScriptSet);
    DPListen(@"com.diapatches.dev.type", DPScriptType);
    DPListen(@"com.diapatches.dev.methods", DPScriptMethods);
    DPListen(@"com.diapatches.dev.dump", DPScriptDump);
    DPListen(@"com.diapatches.dev.click", DPScriptClick);
    DPListen(@"com.diapatches.dev.return", DPScriptReturn);
    DPListen(@"com.diapatches.dev.focus", DPScriptFocus);
    DPListen(@"com.diapatches.dev.menu", DPScriptMenu);
}

void DPInstallDevTools(void) {
    if (![[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] boolForKey:@"devTools"]) return;
    DPListenForScripts();
    DPTraceLayoutLoops();
    DPOnLaunch(^{
        DPAddMenuItem(@"Help", @"DiaPatches: Copy View Tree", ^{ DPCopyViewTree(); });
        NSMenu *debug = [[NSMenu alloc] initWithTitle:@"Debug"];
        [debug addItem:DPMenuItem(@"Pretend Dia Has an Update", ^{ [DPUpdates.shared pretend:DPDia]; })];
        [debug addItem:DPMenuItem(@"Pretend DiaTweaks Has an Update", ^{ [DPUpdates.shared pretend:DPTweaks]; })];
        [debug addItem:DPMenuItem(@"Stop Pretending", ^{ [DPUpdates.shared stopPretending]; })];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Debug" action:nil keyEquivalent:@""];
        item.submenu = debug;
        [NSApp.mainMenu insertItem:item atIndex:1];
    });
}
