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

@implementation DPChatPage
@end

static NSString *DPChatString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }

// The open page at `url`, in any window: a tab can be open in several, and they all show the same page.
// A favorite's chip keeps the favorite's saved URL (calendar.google.com) while its page moves on
// (calendar.google.com/calendar/u/0/r), so failing an exact match, take the same site's page, the one on screen first.
static id DPChatContents(NSURL *url) {
    id site = nil;
    for (NSWindow *window in NSApp.windows) {
        id browser = DPBrowserOfWindow(window);
        for (id contents in browser ? DPTrackedContents(browser) : @[]) {
            id address = [contents respondsToSelector:@selector(url)] ? DPMsg(contents, @selector(url)) : nil;
            NSURL *page = [address isKindOfClass:NSURL.class] ? address : [NSURL URLWithString:DPChatString(address)];
            if ([page.absoluteString isEqual:url.absoluteString]) return contents;
            if (!url.host.length || [page.host caseInsensitiveCompare:url.host] != NSOrderedSame) continue;
            BOOL shown = [contents respondsToSelector:@selector(visibility)] && ((NSInteger (*)(id, SEL))objc_msgSend)(contents, @selector(visibility)) == 2;
            if (!site || shown) site = contents;
        }
    }
    return site;
}

static void DPChatReadPage(NSURL *url, void (^done)(DPChatPage *page)) {
    id contents = [@[ @"https", @"http" ] containsObject:url.scheme.lowercaseString] ? DPChatContents(url) : nil;
    SEL execute = @selector(executeJavascript:completion:);
    if (![contents respondsToSelector:execute]) return done(nil);
    id favicon = [contents respondsToSelector:@selector(favicon)] ? DPMsg(contents, @selector(favicon)) : nil;
    id tabTitle = [contents respondsToSelector:@selector(title)] ? DPMsg(contents, @selector(title)) : nil;
    ((void (*)(id, SEL, NSString *, id))objc_msgSend)(contents, execute, DPChatPageScript, ^(id result, BOOL ok) {
        NSDictionary *data = ok ? DPChatPageResult(result) : nil;
        NSString *text = DPChatString(data[@"text"]);
        if (!data) return done(nil);
        if (text.length > DPChatPageLimit) text = [text substringToIndex:DPChatPageLimit];
        DPChatPage *page = [DPChatPage new];
        page.url = DPChatString(data[@"url"]).length ? data[@"url"] : url.absoluteString;
        // Dia's tab title ("Calendar") reads better on the card than the document's ("Name - Calendar - Week of …").
        page.title = DPChatString(tabTitle).length ? tabTitle : DPChatString(data[@"title"]);
        page.icon = [favicon isKindOfClass:NSImage.class] ? favicon : nil;
        NSMutableString *context = [NSMutableString stringWithFormat:@"<page>\nTitle: %@\nURL: %@", DPChatString(data[@"title"]), page.url];
        if (text.length) [context appendFormat:@"\n%@: %@", [data[@"selection"] boolValue] ? @"Selected text" : @"Page text", text];
        [context appendString:@"\n</page>"];
        page.text = context;
        done(page);
    });
}

void DPChatPages(NSArray<NSURL *> *urls, void (^done)(NSString *key, NSArray<DPChatPage *> *pages)) {
    NSString *key = [[urls valueForKey:@"absoluteString"] componentsJoinedByString:@"\n"];
    NSMutableArray *read = [NSMutableArray new];
    for (NSUInteger i = 0; i < urls.count; i++) [read addObject:NSNull.null];
    __block NSUInteger left = urls.count;
    __block BOOL finished = NO;
    void (^finish)(void) = ^{
        if (finished) return;
        finished = YES;
        done(key, [read filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id page, id bindings) { return page != NSNull.null; }]]);
    };
    if (!left) return dispatch_async(dispatch_get_main_queue(), finish);
    // Never hold up the message: after this, it goes with the pages read so far.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), finish);
    [urls enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger i, BOOL *stop) {
        DPChatReadPage(url, ^(DPChatPage *page) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (page) read[i] = page;
                if (--left == 0) finish();
            });
        });
    }];
}
