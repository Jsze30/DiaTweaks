#import "Sidebar.h"
#import "Patches/CommandBar/Tabs.h"
#import <sqlite3.h>

// Browser tools ChatGPT can call. Codex sends each call here, and Dia does the work.

static NSDictionary *DPChatTool(NSString *name, NSString *description, NSDictionary *properties) {
    return @{@"type": @"function", @"name": name, @"description": description,
             @"inputSchema": @{@"type": @"object", @"properties": properties, @"required": properties.allKeys, @"additionalProperties": @NO}};
}

NSArray *DPChatTools(void) {
    NSDictionary *urls = @{@"urls": @{@"type": @"array", @"items": @{@"type": @"string"}, @"description": @"Full http or https web addresses."}};
    return @[
        DPChatTool(@"list_tabs", @"List the tabs open in the user's browser windows, with their titles and web addresses.", @{}),
        DPChatTool(@"read_tabs", @"Read the text of open tabs, found by their web addresses from list_tabs.", urls),
        DPChatTool(@"open_tabs", @"Open web pages in new tabs in the user's browser window.", urls),
        DPChatTool(@"search_history", @"Search the user's browsing history by words in page titles and web addresses, newest first.",
                   @{@"query": @{@"type": @"string", @"description": @"Words to look for. Empty lists the latest pages."}}),
    ];
}

static NSArray<NSURL *> *DPChatWebURLs(id list) {
    NSMutableArray *urls = [NSMutableArray new];
    for (id text in [list isKindOfClass:NSArray.class] ? list : @[]) {
        NSURL *url = [text isKindOfClass:NSString.class] ? [NSURL URLWithString:text] : nil;
        if ([@[@"http", @"https"] containsObject:url.scheme.lowercaseString] && url.host.length && urls.count < 10) [urls addObject:url];
    }
    return urls;
}

static NSString *DPChatListTabs(void) {
    NSMutableString *out = [NSMutableString new];
    for (id window in [(id)NSApp.delegate valueForKey:@"appleScriptWindows"]) {
        [out appendFormat:@"Window \"%@\":\n", [window valueForKey:@"name"]];
        NSString *active = DPTabID([window valueForKey:@"activeTab"]);
        for (id tab in [window valueForKey:@"appleScriptTabs"])
            [out appendFormat:@"- %@%@ | %@\n", [DPTabID(tab) isEqual:active] ? @"(current) " : @"", [tab valueForKey:@"title"], [tab valueForKey:@"URL"]];
    }
    return out.length ? out : @"No tabs are open.";
}

// Dia's scripting objects are snapshots, so look the window up again to see its tabs change.
static id DPChatScriptWindow(NSString *windowID) {
    id found = nil;
    for (id window in [(id)NSApp.delegate valueForKey:@"appleScriptWindows"])
        if (!found || [[window valueForKey:@"windowId"] isEqual:windowID]) found = window;
    return found;
}

static void DPChatOpenTabs(NSArray<NSURL *> *urls, NSString *windowID, void (^done)(NSString *)) {
    id target = DPChatScriptWindow(windowID);
    if (!target || !urls.count) return done(@"Nothing was opened: give full http or https web addresses.");
    windowID = [target valueForKey:@"windowId"];
    NSString *shown = DPTabID([target valueForKey:@"activeTab"]);
    NSSet *before = [NSSet setWithArray:[[target valueForKey:@"appleScriptTabs"] valueForKey:@"tabId"]];
    NSMutableArray *opened = [NSMutableArray new];
    for (NSURL *url in urls) {
        // Dia's own scripting command, so the tab opens the way "make new tab" does in AppleScript.
        NSString *source = [NSString stringWithFormat:@"tell application id \"%@\" to make new tab at end of tabs of window id \"%@\" with properties {URL:\"%@\"}",
                            NSBundle.mainBundle.bundleIdentifier, windowID, url.absoluteString];
        NSDictionary *error;
        if ([url.absoluteString rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\"\\"]].location == NSNotFound &&
            [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error])
            [opened addObject:url.absoluteString];
    }
    // A new tab comes to the front; put back the tab the user was on, so they stay with its chat.
    target = DPChatScriptWindow(windowID);
    if (![before containsObject:DPTabID([target valueForKey:@"activeTab"])])
        for (id tab in [target valueForKey:@"appleScriptTabs"])
            if ([DPTabID(tab) isEqual:shown]) DPFocusTab(tab);
    done(opened.count ? [@"Opened:\n" stringByAppendingString:[opened componentsJoinedByString:@"\n"]] : @"Couldn't open those pages.");
}

static NSString *DPChatSearchHistory(NSString *query) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Dia/User Data/Default/History"];
    // Chromium keeps the database locked, so read the last saved state without taking a lock.
    NSString *uri = [@"file:" stringByAppendingString:[path stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]];
    sqlite3 *db;
    if (sqlite3_open_v2([uri stringByAppendingString:@"?immutable=1"].UTF8String, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, NULL) != SQLITE_OK) return sqlite3_close(db), @"Couldn't read the browsing history.";
    NSArray *words = [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    if (words.count > 8) words = [words subarrayWithRange:NSMakeRange(0, 8)];
    NSMutableString *sql = [@"SELECT title, url, datetime(last_visit_time / 1000000 - 11644473600, 'unixepoch', 'localtime') FROM urls WHERE hidden = 0" mutableCopy];
    for (NSUInteger i = 0; i < words.count; i++) [sql appendString:@" AND (title LIKE ? ESCAPE '\\' OR url LIKE ? ESCAPE '\\')"];
    [sql appendString:@" ORDER BY last_visit_time DESC LIMIT 25"];
    sqlite3_stmt *statement;
    NSMutableString *out = [NSMutableString new];
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &statement, NULL) == SQLITE_OK) {
        for (NSUInteger i = 0; i < words.count; i++) {
            NSString *escaped = [[[words[i] stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"%" withString:@"\\%"]
                                 stringByReplacingOccurrencesOfString:@"_" withString:@"\\_"];
            NSString *like = [NSString stringWithFormat:@"%%%@%%", escaped];
            sqlite3_bind_text(statement, (int)(2 * i + 1), like.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, (int)(2 * i + 2), like.UTF8String, -1, SQLITE_TRANSIENT);
        }
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const char *title = (const char *)sqlite3_column_text(statement, 0), *url = (const char *)sqlite3_column_text(statement, 1), *when = (const char *)sqlite3_column_text(statement, 2);
            [out appendFormat:@"- %s | %s | last visited %s\n", title ?: "", url ?: "", when ?: ""];
        }
    }
    sqlite3_finalize(statement);
    sqlite3_close(db);
    return out.length ? out : @"No pages in the history match.";
}

static void DPChatRunTool(NSString *tool, NSDictionary *arguments, NSString *windowID, void (^done)(NSString *)) {
    if ([tool isEqual:@"list_tabs"]) return done(DPChatListTabs());
    if ([tool isEqual:@"search_history"]) return done(DPChatSearchHistory([arguments[@"query"] isKindOfClass:NSString.class] ? arguments[@"query"] : @""));
    if ([tool isEqual:@"open_tabs"]) return DPChatOpenTabs(DPChatWebURLs(arguments[@"urls"]), windowID, done);
    if ([tool isEqual:@"read_tabs"])
        return DPChatPages(DPChatWebURLs(arguments[@"urls"]), ^(NSString *key, NSArray<DPChatPage *> *pages) {
            done(pages.count ? [[pages valueForKey:@"text"] componentsJoinedByString:@"\n\n"] : @"Couldn't read those tabs. Use web addresses of open tabs from list_tabs.");
        });
    done([NSString stringWithFormat:@"There is no tool named %@.", tool]);
}

void DPChatServe(NSString *method, NSDictionary *params, DPChatReply reply) {
    if ([method isEqual:@"mcpServer/elicitation/request"]) {
        NSDictionary *meta = [params[@"_meta"] isKindOfClass:NSDictionary.class] ? params[@"_meta"] : @{};
        NSDictionary *hints = [meta[@"tool_annotations"] isKindOfClass:NSDictionary.class] ? meta[@"tool_annotations"] : @{};
        // Nobody can approve in the sidebar: an app's tool that only reads runs, and one that sends or changes anything is turned down.
        BOOL reads = [meta[@"codex_approval_kind"] isEqual:@"mcp_tool_call"] && [hints[@"readOnlyHint"] isEqual:@YES] && ![hints[@"destructiveHint"] isEqual:@YES];
        return reply(@{@"action": reads ? @"accept" : @"decline"}, nil);
    }
    if (![method isEqual:@"item/tool/call"]) return reply(nil, @"Tools are not available in the browser chat.");
    NSDictionary *arguments = [params[@"arguments"] isKindOfClass:NSDictionary.class] ? params[@"arguments"] : @{};
    DPChatRunTool(params[@"tool"], arguments, DPChatWindowOfThread(params[@"threadId"]), ^(NSString *text) {
        reply(@{@"success": @YES, @"contentItems": @[@{@"type": @"inputText", @"text": text}]}, nil);
    });
}
