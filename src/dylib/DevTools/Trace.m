#import "DevTools/DevTools.h"
#import <ffi/ffi.h>
#import <os/lock.h>
#import <pthread.h>
#import <stdatomic.h>

// Logs every call to a class's own Objective-C methods: receiver, arguments, result, thread and nesting.
// Each traced method runs through a libffi closure that calls the IMP it replaced, so an override calling super traces both.
// Pure Swift methods aren't in the Objective-C runtime, so they can't be traced; their @objc callers can.

typedef struct {
    __unsafe_unretained Class cls;
    Method method;
    BOOL meta;
    unsigned count;  // arguments, with self and _cmd
    char **types;    // the return type, then each argument's
    IMP original, closure;
    ffi_cif cif;
} DPTraced;

static const unsigned DPTraceLimit = 100000;
static NSString *DPTracePath;
static NSMutableDictionary<NSValue *, NSValue *> *DPTracedMethods;  // Method -> DPTraced *
static os_unfair_lock DPTraceLock = OS_UNFAIR_LOCK_INIT;
static FILE *DPTraceFile;
static unsigned DPTraceLines;
static CFAbsoluteTime DPTraceStart;
static atomic_bool DPTracing;
static _Thread_local unsigned DPDepth;
static _Thread_local bool DPInside;  // formatting a line: calls it makes aren't logged

static void DPTraceWrite(NSString *line) {
    os_unfair_lock_lock(&DPTraceLock);
    if (DPTraceFile && DPTraceLines < DPTraceLimit) fprintf(DPTraceFile, "%s\n", line.UTF8String);
    if (DPTraceFile && ++DPTraceLines == DPTraceLimit) fprintf(DPTraceFile, "== stopped logging after %u lines; untrace and trace fewer methods\n", DPTraceLimit);
    os_unfair_lock_unlock(&DPTraceLock);
}

static NSString *DPTracePrefix(unsigned depth) {
    char thread[16] = "main";
    if (!pthread_main_np()) snprintf(thread, sizeof thread, "t%u", pthread_mach_thread_np(pthread_self()));
    return [NSString stringWithFormat:@"%9.3f %-6s %*s", CFAbsoluteTimeGetCurrent() - DPTraceStart, thread, depth * 2, ""];
}

static const char *DPSkipQualifiers(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}

// Nil for types libffi can't pass: unions, C arrays, bit-fields, long double and opaque structs.
static ffi_type *DPFFIType(const char **cursor) {
    const char *type = DPSkipQualifiers(*cursor);
    ffi_type *result;
    switch (*type) {
        case 'c': result = &ffi_type_sint8; break;
        case 'C': case 'B': result = &ffi_type_uint8; break;
        case 's': result = &ffi_type_sint16; break;
        case 'S': result = &ffi_type_uint16; break;
        case 'i': case 'l': result = &ffi_type_sint32; break;
        case 'I': case 'L': result = &ffi_type_uint32; break;
        case 'q': result = &ffi_type_sint64; break;
        case 'Q': result = &ffi_type_uint64; break;
        case 'f': result = &ffi_type_float; break;
        case 'd': result = &ffi_type_double; break;
        case 'v': result = &ffi_type_void; break;
        case '@': case '#': case ':': case '^': case '*': result = &ffi_type_pointer; break;
        case '{': {
            const char *p = type + 1;
            while (*p && *p != '=' && *p != '}') p++;
            if (*p++ != '=') return NULL;
            ffi_type *fields[64];
            unsigned n = 0;
            while (*p && *p != '}') {
                if (n == 63 || !(fields[n++] = DPFFIType(&p))) return NULL;
            }
            if (*p != '}' || !n) return NULL;
            ffi_type *s = calloc(1, sizeof *s);
            s->type = FFI_TYPE_STRUCT;
            s->elements = calloc(n + 1, sizeof *s->elements);
            memcpy(s->elements, fields, n * sizeof *fields);
            *cursor = p + 1;
            return s;
        }
        default: return NULL;
    }
    @try { *cursor = NSGetSizeAndAlignment(type, NULL, NULL); } @catch (NSException *e) { return NULL; }
    return result;
}

static BOOL DPIsA(id object, Class cls) {
    for (Class c = object_getClass(object); c; c = class_getSuperclass(c)) if (c == cls) return YES;
    return NO;
}

// The object's own class, not the subclass key-value observing swaps in.
static const char *DPClassName(id object) {
    Class cls = object_getClass(object);
    while (cls && strstr(class_getName(cls), "NSKVONotifying_")) cls = class_getSuperclass(cls);
    return class_getName(cls);
}

// Messages only Foundation value types, so describing an argument can't change what's being traced.
static NSString *DPDescribeObject(__unsafe_unretained id object) {
    if (!object) return @"nil";
    if (object_isClass(object)) return NSStringFromClass(object);
    if (DPIsA(object, NSString.class)) {
        NSString *text = [[object stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
        return [NSString stringWithFormat:@"\"%@\"", text.length > 80 ? [[text substringToIndex:80] stringByAppendingString:@"…"] : text];
    }
    if (DPIsA(object, NSNumber.class)) return [object description];
    if (DPIsA(object, NSURL.class)) return [NSString stringWithFormat:@"<NSURL %@>", [object absoluteString]];
    for (Class collection in @[NSArray.class, NSDictionary.class, NSSet.class, NSOrderedSet.class])
        if (DPIsA(object, collection)) return [NSString stringWithFormat:@"<%s %p count=%lu>", DPClassName(object), object, (unsigned long)[object count]];
    return [NSString stringWithFormat:@"<%s %p>", DPClassName(object), object];
}

static NSString *DPDescribeValue(const char *type, void *value) {
    type = DPSkipQualifiers(type);
    switch (*type) {
        case '@': return type[1] == '?' ? [NSString stringWithFormat:@"<block %p>", *(void **)value] : DPDescribeObject(*(__unsafe_unretained id *)value);
        case '#': return DPDescribeObject(*(__unsafe_unretained Class *)value);
        case ':': return *(SEL *)value ? [NSString stringWithFormat:@"@selector(%s)", sel_getName(*(SEL *)value)] : @"NULL";
        case 'B': return *(bool *)value ? @"YES" : @"NO";
        case 'c': return @(*(signed char *)value).stringValue;
        case 'C': return @(*(unsigned char *)value).stringValue;
        case 's': return @(*(short *)value).stringValue;
        case 'S': return @(*(unsigned short *)value).stringValue;
        case 'i': case 'l': return @(*(int *)value).stringValue;
        case 'I': case 'L': return @(*(unsigned *)value).stringValue;
        case 'q': return @(*(long long *)value).stringValue;
        case 'Q': return @(*(unsigned long long *)value).stringValue;
        case 'f': return @(*(float *)value).stringValue;
        case 'd': return @(*(double *)value).stringValue;
        case '^': case '*': return [NSString stringWithFormat:@"%p", *(void **)value];
        case '{':
            if (!strncmp(type, "{CGRect=", 8)) return NSStringFromRect(*(NSRect *)value);
            if (!strncmp(type, "{CGPoint=", 9)) return NSStringFromPoint(*(NSPoint *)value);
            if (!strncmp(type, "{CGSize=", 8)) return NSStringFromSize(*(NSSize *)value);
            if (!strncmp(type, "{_NSRange=", 10)) return NSStringFromRange(*(NSRange *)value);
            if (!strncmp(type, "{NSEdgeInsets=", 14)) {
                NSEdgeInsets i = *(NSEdgeInsets *)value;
                return [NSString stringWithFormat:@"{top %g, left %g, bottom %g, right %g}", i.top, i.left, i.bottom, i.right];
            }
            return [NSString stringWithFormat:@"{%.*s}", (int)strcspn(type + 1, "="), type + 1];
    }
    return @"?";
}

// [Receiver 0x… first:arg second:arg], plus where the method is declared when the receiver is a subclass.
static NSString *DPDescribeCall(DPTraced *traced, void **args) {
    __unsafe_unretained id receiver = *(__unsafe_unretained id *)args[0];
    NSMutableString *out = traced->meta ? [NSMutableString stringWithFormat:@"[%s", class_getName(receiver)]
                                        : [NSMutableString stringWithFormat:@"[%s %p", DPClassName(receiver), receiver];
    NSString *name = NSStringFromSelector(method_getName(traced->method));
    NSArray<NSString *> *parts = [name componentsSeparatedByString:@":"];
    if (traced->count == 2 || parts.count < traced->count - 1) [out appendFormat:@" %@", name];
    else for (unsigned i = 2; i < traced->count; i++) [out appendFormat:@" %@:%@", parts[i - 2], DPDescribeValue(traced->types[i + 1], args[i])];
    [out appendString:@"]"];
    const char *actual = traced->meta ? class_getName(receiver) : DPClassName(receiver);
    if (strcmp(actual, class_getName(traced->cls))) [out appendFormat:@" from %s", class_getName(traced->cls)];
    return out;
}

static void DPTraceCall(ffi_cif *cif, void *result, void **args, void *data) {
    DPTraced *traced = data;
    if (DPInside || !atomic_load_explicit(&DPTracing, memory_order_relaxed)) return ffi_call(cif, FFI_FN(traced->original), result, args);
    unsigned depth = DPDepth;
    DPInside = true;
    @autoreleasepool { DPTraceWrite([DPTracePrefix(depth) stringByAppendingString:DPDescribeCall(traced, args)]); }
    DPInside = false;
    DPDepth = depth + 1;
    ffi_call(cif, FFI_FN(traced->original), result, args);
    DPDepth = depth;
    if (*DPSkipQualifiers(traced->types[0]) == 'v') return;
    DPInside = true;
    @autoreleasepool { DPTraceWrite([NSString stringWithFormat:@"%@= %@", DPTracePrefix(depth), DPDescribeValue(traced->types[0], result)]); }
    DPInside = false;
}

static DPTraced *DPMakeTraced(Class cls, Method method, BOOL meta) {
    unsigned count = method_getNumberOfArguments(method);
    char **types = calloc(count + 1, sizeof *types);
    ffi_type **argTypes = calloc(count, sizeof *argTypes);
    types[0] = method_copyReturnType(method);
    const char *cursor = types[0];
    ffi_type *returnType = DPFFIType(&cursor);
    BOOL ok = returnType != NULL;
    for (unsigned i = 0; i < count; i++) {
        cursor = types[i + 1] = method_copyArgumentType(method, i);
        ok = ok && cursor && (argTypes[i] = DPFFIType(&cursor)) && argTypes[i] != &ffi_type_void;
    }
    DPTraced *traced = calloc(1, sizeof *traced);
    *traced = (DPTraced){.cls = cls, .method = method, .meta = meta, .count = count, .types = types};
    void *code = NULL;
    ffi_closure *closure = ok && ffi_prep_cif(&traced->cif, FFI_DEFAULT_ABI, count, returnType, argTypes) == FFI_OK ? ffi_closure_alloc(sizeof *closure, &code) : NULL;
    if (!closure || ffi_prep_closure_loc(closure, &traced->cif, DPTraceCall, traced, code) != FFI_OK) {
        if (closure) ffi_closure_free(closure);
        for (unsigned i = 0; i <= count; i++) free(types[i]);
        free(types), free(argTypes), free(traced);
        return NULL;
    }
    traced->closure = (IMP)code;
    return traced;
}

// Tracing these would recurse through the tracer itself or the runtime's own memory management.
static BOOL DPUntraceable(NSString *name) {
    static NSSet *names;
    if (!names) names = [NSSet setWithArray:@[@"dealloc", @".cxx_destruct", @".cxx_construct", @"retain", @"release", @"autorelease", @"retainCount",
        @"_tryRetain", @"_isDeallocating", @"allowsWeakReference", @"retainWeakReference", @"class", @"respondsToSelector:", @"isKindOfClass:",
        @"isMemberOfClass:", @"methodSignatureForSelector:", @"forwardInvocation:", @"forwardingTargetForSelector:", @"initialize", @"load"]];
    // Variadic methods take their extra arguments on the stack, which a fixed signature can't forward.
    return [names containsObject:name] || [name hasSuffix:@"Format:"] || [name containsString:@"WithObjects"] || [name containsString:@"AndKeys"];
}

static void DPTraceMethods(Class cls, BOOL meta, NSString *filter, NSMutableArray *traced, NSMutableArray *skipped) {
    unsigned n = 0;
    Method *methods = class_copyMethodList(meta ? object_getClass(cls) : cls, &n);
    for (unsigned i = 0; i < n; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        if ((filter.length && ![name containsString:filter]) || DPUntraceable(name)) continue;
        NSValue *key = [NSValue valueWithPointer:methods[i]];
        DPTraced *t = DPTracedMethods[key].pointerValue ?: DPMakeTraced(cls, methods[i], meta);
        if (!t) {
            [skipped addObject:name];
            continue;
        }
        DPTracedMethods[key] = [NSValue valueWithPointer:t];
        IMP current = method_getImplementation(methods[i]);
        if (current != t->closure) {
            t->original = current;
            method_setImplementation(methods[i], t->closure);
        }
        [traced addObject:name];
    }
    free(methods);
}

void DPTraceMark(NSString *text) {
    DPTraceWrite([NSString stringWithFormat:@"%@== %@", DPTracePrefix(0), text]);
}

void DPTraceTo(NSString *path) {
    DPTracePath = path;
}

// "ClassName" traces all of the class's own methods; "ClassName text" only those whose selector contains text.
void DPTrace(NSString *spec) {
    if (!DPTracedMethods) DPTracedMethods = [NSMutableDictionary dictionary];
    if (!atomic_load(&DPTracing)) {
        os_unfair_lock_lock(&DPTraceLock);
        DPTraceFile = fopen(DPTracePath.fileSystemRepresentation, "w");
        if (DPTraceFile) setvbuf(DPTraceFile, NULL, _IOLBF, 0);
        DPTraceLines = 0;
        DPTraceStart = CFAbsoluteTimeGetCurrent();
        os_unfair_lock_unlock(&DPTraceLock);
        atomic_store(&DPTracing, YES);
    }
    NSArray<NSString *> *words = [spec componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *filter = words.count > 1 ? words[1] : nil;
    Class cls = objc_getClass(words.firstObject.UTF8String) ?: NSClassFromString(words.firstObject);
    if (!cls) return DPTraceMark([NSString stringWithFormat:@"no class named %@", words.firstObject]);
    NSMutableArray *traced = [NSMutableArray array], *skipped = [NSMutableArray array];
    DPTraceMethods(cls, NO, filter, traced, skipped);
    DPTraceMethods(cls, YES, filter, traced, skipped);
    DPTraceMark([NSString stringWithFormat:@"tracing %lu methods of %s%@", (unsigned long)traced.count, class_getName(cls),
                  skipped.count ? [NSString stringWithFormat:@"; can't trace %@", [skipped componentsJoinedByString:@" "]] : @""]);
}

// Puts every traced method back and closes the log. Closures stay allocated: another thread may still be inside one.
void DPUntrace(void) {
    for (NSValue *value in DPTracedMethods.allValues) {
        DPTraced *t = value.pointerValue;
        if (method_getImplementation(t->method) == t->closure) method_setImplementation(t->method, t->original);
    }
    atomic_store(&DPTracing, NO);
    os_unfair_lock_lock(&DPTraceLock);
    if (DPTraceFile) fclose(DPTraceFile);
    DPTraceFile = NULL;
    os_unfair_lock_unlock(&DPTraceLock);
}
