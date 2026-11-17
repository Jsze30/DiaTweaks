#import "Client.h"

NSString *DPChatHome(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/DiaPatches/ChatGPT"];
}

NSString *DPChatExecutable(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *saved = [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] stringForKey:@"chatGPTCodexPath"];
    NSMutableArray *paths = [NSMutableArray array];
    if (saved.length) [paths addObject:saved];
    [paths addObjectsFromArray:@[@"/Applications/Codex.app/Contents/Resources/codex", @"/opt/homebrew/bin/codex", @"/usr/local/bin/codex"]];
    for (NSString *dir in [NSProcessInfo.processInfo.environment[@"PATH"] componentsSeparatedByString:@":"])
        if (dir.length) [paths addObject:[dir stringByAppendingPathComponent:@"codex"]];
    NSString *nvm = [NSHomeDirectory() stringByAppendingPathComponent:@".nvm/versions/node"];
    NSArray *versions = [[files contentsOfDirectoryAtPath:nvm error:nil] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [b compare:a options:NSNumericSearch];
    }];
    for (NSString *version in versions) [paths addObject:[[nvm stringByAppendingPathComponent:version] stringByAppendingPathComponent:@"bin/codex"]];
    for (NSString *path in paths) if ([files isExecutableFileAtPath:path]) return path;
    return nil;
}

NSDictionary *DPChatEnvironment(NSString *executable) {
    // Shares the user's own Codex sign-in, but not API keys or provider overrides from Dia's environment.
    NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:@{
        @"HOME": NSHomeDirectory(),
        @"PATH": [NSString stringWithFormat:@"%@:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", executable.stringByDeletingLastPathComponent],
        @"LANG": @"en_US.UTF-8"
    }];
    NSString *temp = NSProcessInfo.processInfo.environment[@"TMPDIR"];
    if (temp) env[@"TMPDIR"] = temp;
    NSString *home = NSProcessInfo.processInfo.environment[@"CODEX_HOME"];
    if (home) env[@"CODEX_HOME"] = home;
    return env;
}

NSArray *DPChatArguments(void) {
    return @[@"app-server", @"--listen", @"stdio://",
        @"-c", @"forced_login_method=\"chatgpt\"", @"-c", @"mcp_servers={}",
        @"-c", @"approval_policy=\"never\"", @"-c", @"sandbox_mode=\"read-only\"",
        @"-c", @"features.shell_tool=false", @"-c", @"features.unified_exec=false",
        @"-c", @"features.apps=false", @"-c", @"features.browser_use=false",
        @"-c", @"features.computer_use=false", @"-c", @"features.multi_agent=false",
        @"-c", @"web_search=\"disabled\"", @"-c", @"history.persistence=\"none\"",
        @"-c", @"project_doc_max_bytes=0", @"-c", @"model_reasoning_effort=\"low\""];
}
