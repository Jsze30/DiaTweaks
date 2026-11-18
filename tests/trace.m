#import "DevTools/DevTools.h"

@interface DPTraceBase : NSObject
- (void)ping;
@end
@implementation DPTraceBase
- (void)ping {}
- (NSRect)frameFor:(NSInteger)index scale:(double)scale { return NSMakeRect(index, 2, 3 * scale, 4); }
- (BOOL)flip:(BOOL)value small:(char)c tiny:(float)f { return !value && c == -3 && f == 1.5f; }
- (NSString *)echo:(NSString *)text { return [text stringByAppendingString:@"!"]; }
- (CGAffineTransform)scaled:(CGAffineTransform)t by:(double)k { return CGAffineTransformScale(t, k, k); }
- (NSRange)rangeOf:(NSArray *)items selector:(SEL)sel block:(void (^)(void))block { block(); return NSMakeRange(items.count, 7); }
+ (instancetype)make { return [self new]; }
@end

@interface DPTraceSub : DPTraceBase
@end
@implementation DPTraceSub
- (void)ping { [super ping]; }
@end

static int failures;

static void expect(BOOL ok, NSString *what) {
    if (!ok) failures++, fprintf(stderr, "FAIL: %s\n", what.UTF8String);
}

static NSString *contents(NSString *path) {
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
}

int main(void) {
    @autoreleasepool {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"dp-trace-test.txt"];
        DPTraceTo(path);
        DPTrace(@"DPTraceBase");
        DPTrace(@"DPTraceSub");
        DPTrace(@"DPNoSuchClass");
        DPTraceMark(@"start");

        DPTraceSub *sub = [DPTraceSub make];
        [sub ping];
        NSRect rect = [sub frameFor:5 scale:2];
        expect(NSEqualRects(rect, NSMakeRect(5, 2, 6, 4)), @"struct return passes through");
        expect([sub flip:NO small:-3 tiny:1.5f], @"small scalar arguments pass through");
        expect([[sub echo:@"hi"] isEqual:@"hi!"], @"object return passes through");
        CGAffineTransform t = [sub scaled:CGAffineTransformMakeTranslation(10, 20) by:2];
        expect(t.a == 2 && t.d == 2 && t.tx == 10 && t.ty == 20, @"large struct by value passes through");
        __block BOOL ran = NO;
        NSRange range = [sub rangeOf:@[@1, @2] selector:@selector(ping) block:^{ ran = YES; }];
        expect(ran && range.location == 2 && range.length == 7, @"block, selector and range pass through");
        NSThread *thread = [[NSThread alloc] initWithBlock:^{ [sub echo:@"bg"]; }];
        [thread start];
        while (!thread.finished) usleep(1000);

        DPTraceBase *observed = [DPTraceBase new];
        NSObject *observer = [NSObject new];
        [observed addObserver:observer forKeyPath:@"hash" options:0 context:NULL];
        [observed echo:@"kvo"];
        [observed removeObserver:observer forKeyPath:@"hash"];

        DPUntrace();
        [sub echo:@"after"];
        NSString *log = contents(path);
        expect([log containsString:@"== tracing 7 methods of DPTraceBase"], @"traces instance and class methods");
        expect([log containsString:@"== no class named DPNoSuchClass"], @"reports a missing class");
        expect([log containsString:@"== start"], @"writes marks");
        expect([log containsString:@"[DPTraceBase make] from DPTraceSub"] || [log containsString:@"[DPTraceSub make] from DPTraceBase"], @"logs class methods");
        NSRegularExpression *nested = [NSRegularExpression regularExpressionWithPattern:@"main +\\[DPTraceSub 0x[0-9a-f]+ ping\\]\\n.*main   +\\[DPTraceSub 0x[0-9a-f]+ ping\\] from DPTraceBase" options:0 error:nil];
        expect([nested numberOfMatchesInString:log options:0 range:NSMakeRange(0, log.length)] == 1, @"nests super calls, once each");
        expect([log containsString:@"frameFor:5 scale:2]"] && [log containsString:@"= {{5, 2}, {6, 4}}"], @"logs arguments and struct results");
        expect([log containsString:@"flip:NO small:-3 tiny:1.5]"] && [log containsString:@"= YES"], @"logs scalars");
        expect([log containsString:@"echo:\"hi\"]"] && [log containsString:@"= \"hi!\""], @"logs strings");
        expect([log containsString:@"scaled:{CGAffineTransform} by:2]"], @"names other structs");
        expect([log containsString:@"rangeOf:<"] && [log containsString:@"count=2> selector:@selector(ping) block:<block 0x"] && [log containsString:@"= {2, 7}"], @"logs collections, selectors, blocks and ranges");
        expect([[NSRegularExpression regularExpressionWithPattern:@" t[0-9]+ +\\[DPTraceSub 0x[0-9a-f]+ echo:\"bg\"\\]" options:0 error:nil]
                   numberOfMatchesInString:log options:0 range:NSMakeRange(0, log.length)] == 1, @"marks other threads");
        expect([[NSRegularExpression regularExpressionWithPattern:@"\\[DPTraceBase 0x[0-9a-f]+ echo:\"kvo\"\\]\n" options:0 error:nil]
                   numberOfMatchesInString:log options:0 range:NSMakeRange(0, log.length)] == 1, @"hides key-value observing subclasses");
        expect(![log containsString:@"after"], @"untrace stops logging");
        expect(method_getImplementation(class_getInstanceMethod(DPTraceBase.class, @selector(echo:))) == class_getMethodImplementation(DPTraceBase.class, @selector(echo:)), @"untrace restores methods");

        DPTrace(@"DPTraceBase echo");
        [sub echo:@"again"];
        [sub ping];
        DPUntrace();
        log = contents(path);
        expect([log containsString:@"== tracing 1 methods of DPTraceBase"] && [log containsString:@"echo:\"again\""] && ![log containsString:@"ping"], @"filters by selector and starts a fresh log");
    }
    if (failures) return fprintf(stderr, "%s", contents([NSTemporaryDirectory() stringByAppendingPathComponent:@"dp-trace-test.txt"]).UTF8String), 1;
    puts("trace: ok");
    return 0;
}
