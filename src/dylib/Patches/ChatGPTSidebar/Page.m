#import "Sidebar.h"
#import "Commands/GroupTabs/GroupTabs.h"
#import <objc/message.h>

static const NSUInteger DPChatPageLimit = 24000;

// The selection, or the page's visible text with form fields and hidden parts left out.
static NSString *const DPChatPageScript = @"(() => {"
    "const limit = 24000, skip = 'script,style,noscript,template,svg,canvas,iframe,input,textarea,select,option,[hidden],[aria-hidden=\"true\"]';"
    "const block = /^(ADDRESS|ARTICLE|ASIDE|BLOCKQUOTE|BR|DD|DIV|DL|DT|FIELDSET|FIGCAPTION|FIGURE|FOOTER|FORM|H[1-6]|HEADER|HR|LI|MAIN|NAV|OL|P|PRE|SECTION|TABLE|TD|TH|TR|UL)$/;"
    "const selection = (getSelection()?.toString() || '').trim();"
    "let out = '';"
    "const walk = node => {"
    "  if (out.length > limit) return;"
    "  if (node.nodeType === 3) { out += node.parentElement?.closest('pre') ? node.data : node.data.replace(/\\s+/g, ' '); return; }"
    "  if (node.nodeType !== 1 || node.matches(skip)) return;"
    "  if (node.checkVisibility && !node.checkVisibility({visibilityProperty: true})) return;"
    "  const isBlock = block.test(node.tagName);"
    "  if (isBlock) out += '\\n';"
    "  for (const child of node.childNodes) walk(child);"
    "  if (isBlock) out += '\\n';"
    "};"
    "if (!selection && document.body) walk(document.body);"
    "const text = (selection || out.replace(/[ \\t]*\\n[ \\t]*/g, '\\n').replace(/\\n{3,}/g, '\\n\\n').trim()).slice(0, limit);"
    "return JSON.stringify({title: document.title, url: location.href, text, selection: !!selection});"
    "})()";

static NSDictionary *DPChatPageResult(id result) {
    id decoded = [result isKindOfClass:NSString.class]
        ? [NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingFragmentsAllowed error:nil]
        : result;
    // Dia versions differ in whether JavaScript strings arrive JSON-quoted.
    if ([decoded isKindOfClass:NSString.class])
        decoded = [NSJSONSerialization JSONObjectWithData:[decoded dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    return [decoded isKindOfClass:NSDictionary.class] ? decoded : nil;
}

static NSString *DPChatString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }

void DPChatPage(NSWindow *window, void (^done)(NSString *url, NSString *title, NSImage *icon, NSString *text)) {
    __block BOOL finished = NO;
    __block NSImage *icon = nil;
    void (^finish)(NSString *, NSString *, NSString *) = ^(NSString *url, NSString *title, NSString *text) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finished) return;
            finished = YES;
            done(url, title, url ? icon : nil, text);
        });
    };

    id browser = window ? DPBrowserOfWindow(window) : nil;
    long long active = browser ? DPActiveSession(browser) : 0;
    id page = nil;
    if (active > 0)
        for (id candidate in DPTrackedContents(browser))
            if (DPSessionOf(candidate) == active) { page = candidate; break; }
    SEL execute = @selector(executeJavascript:completion:);
    id address = [page respondsToSelector:@selector(url)] ? DPMsg(page, @selector(url)) : nil;
    NSURL *url = [address isKindOfClass:NSURL.class] ? address : [address isKindOfClass:NSString.class] ? [NSURL URLWithString:address] : nil;
    if (![page respondsToSelector:execute] || ![@[ @"https", @"http" ] containsObject:url.scheme.lowercaseString]) return finish(nil, nil, nil);

    id favicon = [page respondsToSelector:@selector(favicon)] ? DPMsg(page, @selector(favicon)) : nil;
    icon = [favicon isKindOfClass:NSImage.class] ? favicon : nil;
    id tabTitle = [page respondsToSelector:@selector(title)] ? DPMsg(page, @selector(title)) : nil;

    // Never hold up the message: after this, it goes without the page.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ finish(nil, nil, nil); });
    ((void (*)(id, SEL, NSString *, id))objc_msgSend)(page, execute, DPChatPageScript, ^(id result, BOOL ok) {
        NSDictionary *data = ok ? DPChatPageResult(result) : nil;
        NSString *text = DPChatString(data[@"text"]);
        if (!data) return finish(nil, nil, nil);
        if (text.length > DPChatPageLimit) text = [text substringToIndex:DPChatPageLimit];
        NSString *pageURL = DPChatString(data[@"url"]).length ? data[@"url"] : url.absoluteString;
        NSMutableString *context = [NSMutableString stringWithFormat:@"Title: %@\nURL: %@", DPChatString(data[@"title"]), pageURL];
        if (text.length) [context appendFormat:@"\n%@: %@", [data[@"selection"] boolValue] ? @"Selected text" : @"Page text", text];
        // Dia's tab title ("Calendar") reads better on the card than the document's ("Name - Calendar - Week of …").
        finish(pageURL, DPChatString(tabTitle).length ? tabTitle : DPChatString(data[@"title"]), context);
    });
}
