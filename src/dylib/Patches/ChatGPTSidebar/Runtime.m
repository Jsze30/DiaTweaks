#import "Client.h"
#import <pwd.h>

NSString *DPChatHome(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/DiaPatches/ChatGPT"];
}

// Last resort, asked once: where the user's login shell finds Codex. Dia's own PATH depends on how it was launched.
static NSString *DPChatShellCodex(void) {
    static NSString *found;
    static BOOL asked;
    if (asked) return found;
    asked = YES;
    struct passwd *user = getpwuid(getuid());
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:user && user->pw_shell ? @(user->pw_shell) : @"/bin/zsh"];
    // Interactive too, since many profiles only set PATH in the rc file. The tag keeps profile output out of the answer.
    task.arguments = @[@"-i", @"-l", @"-c", @"printf '\\nDPCODEX=%s\\n' \"$(command -v codex)\""];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardInput = task.standardError = NSFileHandle.fileHandleWithNullDevice;
    dispatch_semaphore_t exited = dispatch_semaphore_create(0);
    task.terminationHandler = ^(NSTask *t) { dispatch_semaphore_signal(exited); };
    if (![task launchAndReturnError:nil]) return nil;
    if (dispatch_semaphore_wait(exited, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC))) return [task terminate], nil;
    int fd = pipe.fileHandleForReading.fileDescriptor;
    fcntl(fd, F_SETFL, O_NONBLOCK);  // A process the shell left behind may hold the pipe open.
    char buffer[4096];
    ssize_t length = read(fd, buffer, sizeof buffer);
    NSString *output = length > 0 ? [[NSString alloc] initWithBytes:buffer length:length encoding:NSUTF8StringEncoding] : nil;
    for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet])
        if ([line hasPrefix:@"DPCODEX=/"]) found = [line substringFromIndex:8];
    return found;
}

NSString *DPChatExecutable(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *home = NSHomeDirectory();
    NSString *saved = [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] stringForKey:@"chatGPTCodexPath"];
    NSMutableArray *paths = [NSMutableArray array];
    if (saved.length) [paths addObject:saved];
    [paths addObjectsFromArray:@[@"/Applications/Codex.app/Contents/Resources/codex", [home stringByAppendingPathComponent:@"Applications/Codex.app/Contents/Resources/codex"],
        [home stringByAppendingPathComponent:@".local/bin/codex"], @"/opt/homebrew/bin/codex", @"/usr/local/bin/codex"]];
    for (NSString *dir in [NSProcessInfo.processInfo.environment[@"PATH"] componentsSeparatedByString:@":"])
        if (dir.length) [paths addObject:[dir stringByAppendingPathComponent:@"codex"]];
    NSString *nvm = [home stringByAppendingPathComponent:@".nvm/versions/node"];
    NSArray *versions = [[files contentsOfDirectoryAtPath:nvm error:nil] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [b compare:a options:NSNumericSearch];
    }];
    for (NSString *version in versions) [paths addObject:[[nvm stringByAppendingPathComponent:version] stringByAppendingPathComponent:@"bin/codex"]];
    for (NSString *path in paths) if ([files isExecutableFileAtPath:path]) return path;
    NSString *shell = DPChatShellCodex();
    return [files isExecutableFileAtPath:shell] ? shell : nil;
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
