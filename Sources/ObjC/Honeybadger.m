//
// Honeybadger iOS/macOS/visionOS
//



#import "Honeybadger.h"
#import <objc/runtime.h>
#include <execinfo.h>
#include <mach-o/utils.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <dlfcn.h>
#include <signal.h>
#include <pthread.h>
#include <pthread/introspection.h>
#include <fcntl.h>
#include <unistd.h>
#include <limits.h>
#include <math.h>
#import "HoneybadgerCrashTypes.h"

// Linkage for SDK-internal globals and functions. Shipped builds keep them
// `static` so a statically linked SDK exports no hb_* symbols that could
// collide with a host app's own. Test builds (HB_TEST_BUILD, defined by the
// HoneybadgerTests target, which compiles this file directly — see
// Tests/HoneybadgerTests/SDKUnderTest.m) give them external linkage for
// white-box access.
#ifdef HB_TEST_BUILD
    #define HB_PRIVATE
#else
    #define HB_PRIVATE static
#endif

#if (TARGET_OS_IOS || TARGET_OS_VISION)
    #import <UIKit/UIKit.h>
#endif



#define HONEYBADGER_APPLE_SDK_VERSION   @"2.0.0"


#if TARGET_OS_IOS
static NSString * const shortPlatformName = @"iOS";
#elif TARGET_OS_OSX
static NSString * const shortPlatformName = @"macOS";
#elif TARGET_OS_VISION
static NSString * const shortPlatformName = @"visionOS";
#else
static NSString * const shortPlatformName = @"unknown";
#endif



// -- SIGNAL HANDLING STATICS ----------------------------------------------

#define HB_SIGNAL_COUNT 6
HB_PRIVATE int hb_signals[HB_SIGNAL_COUNT] = { SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP };
HB_PRIVATE struct sigaction hb_previous_signal_actions[HB_SIGNAL_COUNT];
static char hb_signal_crash_file_path[PATH_MAX];

// Dedicated stack for fatal-signal delivery. A stack-overflow SIGSEGV arrives
// on the exhausted thread stack; without this, the handler's own prologue
// faults and the crash is never recorded. 64KB comfortably exceeds Darwin's
// MINSIGSTKSZ (32KB) and the handler's needs (its large buffers are static).
static char hb_signal_stack[64 * 1024];

// Alternate stacks for threads created after configure. sigaltstack() is
// per-thread and no API can install a stack on another already-running
// thread, so installSignalHandlers covers only its own (configure) thread
// with hb_signal_stack; this pthread introspection hook covers every thread
// born afterward. THREAD_START runs on the new thread itself in normal
// context (malloc is fine here — this is NOT the signal handler). The
// malloc'd stack is virtual until a signal actually touches it. Ownership is
// tracked in thread-specific data so TERMINATE frees only stacks WE
// installed — never the host app's or another SDK's — and a pre-existing
// alt stack is left alone. Threads alive before configure (other than the
// configure thread) remain uncovered.
static pthread_key_t hb_thread_alt_stack_key;
static pthread_introspection_hook_t hb_previous_introspection_hook;

static void hb_thread_introspection_hook(unsigned int event, pthread_t thread, void* addr, size_t size)
{
    if ( event == PTHREAD_INTROSPECTION_THREAD_START ) {
        stack_t existing;
        if ( sigaltstack(NULL, &existing) == 0 && (existing.ss_flags & SS_DISABLE) ) {
            void* stackMem = malloc(sizeof(hb_signal_stack));
            if ( stackMem ) {
                stack_t altStack;
                memset(&altStack, 0, sizeof(altStack));
                altStack.ss_sp = stackMem;
                altStack.ss_size = sizeof(hb_signal_stack);
                if ( sigaltstack(&altStack, NULL) == 0 ) {
                    pthread_setspecific(hb_thread_alt_stack_key, stackMem);
                } else {
                    free(stackMem);
                }
            }
        }
    } else if ( event == PTHREAD_INTROSPECTION_THREAD_TERMINATE ) {
        // Runs on the terminating thread, before TSD teardown.
        void* stackMem = pthread_getspecific(hb_thread_alt_stack_key);
        if ( stackMem ) {
            stack_t disable;
            memset(&disable, 0, sizeof(disable));
            disable.ss_flags = SS_DISABLE;
            sigaltstack(&disable, NULL);
            free(stackMem);
            pthread_setspecific(hb_thread_alt_stack_key, NULL);
        }
    }
    if ( hb_previous_introspection_hook ) {
        hb_previous_introspection_hook(event, thread, addr, size);
    }
}

static NSUncaughtExceptionHandler *hb_previous_exception_handler = NULL;

// Set once an NSException has been captured + persisted by the exception path.
// The signal handler reads it (async-signal-safe via sig_atomic_t) to avoid
// writing a duplicate report for the signal that merely tears the process down
// afterward — AppKit's crash-on-exceptions trap (SIGTRAP) or abort() (SIGABRT).
HB_PRIVATE volatile sig_atomic_t hb_exception_captured = 0;

#if TARGET_OS_OSX
static IMP hb_original_report_exception = NULL;
#endif

HB_PRIVATE void hb_exception_handler(NSException *exception);
HB_PRIVATE void hb_signal_handler(int signal, siginfo_t* info, void* uap);
HB_PRIVATE void hb_capture_exception(NSException *exception, NSString *handlerName);
#if TARGET_OS_OSX
static void hb_install_appkit_exception_hook(void);
#endif

// -- STATIC BINARY IMAGE TABLE ----------------------------------------------
// Rebuilt in normal (non-signal) context — at configure time and whenever dyld
// loads an image — so the crash-time signal handler can persist symbolication
// data from the *crashed* process with nothing but write(). Rebuilding on the
// next launch instead would pair crash addresses with the wrong ASLR slides.
HB_PRIVATE HBBinaryImage hb_binary_images[HB_MAX_BINARY_IMAGES];
HB_PRIVATE volatile int hb_binary_image_count = 0;

HB_PRIVATE void hb_refresh_binary_images(void)
{
    uint32_t dyldCount = _dyld_image_count();
    int out = 0;
    for ( uint32_t i = 0; i < dyldCount && out < HB_MAX_BINARY_IMAGES; i++ ) {
        const struct mach_header* header = _dyld_get_image_header(i);
        if ( !header ) continue;

        HBBinaryImage* img = &hb_binary_images[out];
        memset(img, 0, sizeof(*img));

        const char* name = _dyld_get_image_name(i);
        if ( name ) strlcpy(img->name, name, sizeof(img->name));
        img->load_address = (uint64_t)(uintptr_t)header;
        img->vmaddr_slide = (uint64_t)(uintptr_t)_dyld_get_image_vmaddr_slide(i);
        img->cpu_type = header->cputype;
        img->cpu_subtype = header->cpusubtype;

        BOOL is64 = (header->magic == MH_MAGIC_64 || header->magic == MH_CIGAM_64);
        uintptr_t cursor = (uintptr_t)header + (is64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header));
        uint64_t vmEnd = 0;  // max unslid segment end; slid below
        for ( uint32_t j = 0; j < header->ncmds; j++ ) {
            const struct load_command* cmd = (const struct load_command*)cursor;
            if ( cmd->cmd == LC_UUID ) {
                const struct uuid_command* uuidCmd = (const struct uuid_command*)cursor;
                memcpy(img->uuid, uuidCmd->uuid, 16);
                img->has_uuid = 1;
            } else if ( cmd->cmd == LC_SEGMENT_64 ) {
                const struct segment_command_64* seg = (const struct segment_command_64*)cursor;
                if ( seg->vmaddr + seg->vmsize > vmEnd ) vmEnd = seg->vmaddr + seg->vmsize;
            } else if ( cmd->cmd == LC_SEGMENT ) {
                const struct segment_command* seg = (const struct segment_command*)cursor;
                if ( (uint64_t)seg->vmaddr + seg->vmsize > vmEnd ) vmEnd = (uint64_t)seg->vmaddr + seg->vmsize;
            }
            cursor += cmd->cmdsize;
        }
        // load_address is the slid __TEXT address; vmEnd is unslid, so the
        // mapped extent from load_address is (vmEnd + slide) - load_address.
        uint64_t slidEnd = vmEnd + img->vmaddr_slide;
        img->size = (vmEnd > 0 && slidEnd > img->load_address) ? (slidEnd - img->load_address) : 0;
        out++;
    }
    hb_binary_image_count = out;
}

// Suppresses the dyld callback until initial registration completes:
// _dyld_register_func_for_add_image synchronously invokes the callback once
// per already-loaded image, and each invocation rebuilds the whole table —
// O(N^2) work at configure time for N loaded images. Registration runs with
// the callback suppressed, then a single refresh covers everything loaded up
// to that point; the callback handles later loads.
static volatile sig_atomic_t hb_dyld_registration_complete = 0;

static void hb_on_dyld_image_added(const struct mach_header* header, intptr_t slide)
{
    if ( !hb_dyld_registration_complete ) {
        return;
    }
    // Full rebuild keeps this trivially correct; image loads are rare after
    // startup. Runs in normal context (dyld callbacks are not signal context).
    hb_refresh_binary_images();
}

// -- CONTEXT SNAPSHOT --------------------------------------------------------
// JSON-serialized copy of the user's context, maintained in normal context on
// every setContext/resetContext/configure, so the signal handler can persist
// the CRASHED process's context with a bare write(). Rebuilding context on the
// next launch would lose user/session IDs for exactly the crashes this SDK
// exists to capture. Same accepted torn-read race as hb_binary_images: length
// is invalidated during the copy, and the reader degrades an unparseable
// snapshot to an empty context rather than dropping the report.
HB_PRIVATE char hb_context_json[HB_MAX_CONTEXT_JSON];
HB_PRIVATE volatile int hb_context_json_length = 0;

// -------------------------------------------------------------------------



@interface Honeybadger ()

@property (nonatomic) NSString* apiKey;
@property (nonatomic) NSString* customEnvironment;
@property (nonatomic) NSString* customRevision;
@property (nonatomic) BOOL initialized;
@property (nonatomic) NSMutableDictionary<NSString*, NSString*>* context;
@property (atomic, copy) NSString* cachedHostname;

@end



@implementation Honeybadger

// -- SINGLETON (thread-safe via dispatch_once) ----------------------------
+ (Honeybadger*) sharedInstance {
    static Honeybadger* instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[super allocWithZone:NULL] init];
    });
    return instance;
}
+ (id) allocWithZone:(NSZone*)zone { return [self sharedInstance]; }
- (id) copyWithZone:(NSZone*)zone { return self; }
// -------------------------------------------------------------------------



// CONFIG ------------------------------------------------------------------

+ (void) configureWithAPIKey:(NSString*)apiKey {
    [Honeybadger configureWithAPIKey:apiKey environment:@"" revision:@""];
}

+ (void) configureWithAPIKey:(NSString*)apiKey environment:(NSString*)environment {
    [Honeybadger configureWithAPIKey:apiKey environment:environment revision:@""];
}

+ (void) configureWithAPIKey:(NSString*)apiKey environment:(NSString*)environment revision:(NSString*)revision {
    Honeybadger* hb = [Honeybadger sharedInstance];

    // Ignore repeat calls. Re-running configuration would re-install the
    // exception and signal handlers, capturing Honeybadger's own handlers as
    // the "previous" ones — which causes infinite recursion when chaining on
    // the next crash.
    if ( hb.initialized ) {
        NSLog(@"Honeybadger is already configured; ignoring duplicate configureWithAPIKey: call.");
        return;
    }

    if ( ![hb isSupportedPlatform] ) {
        NSLog(@"Error: The Honeybadger SDK does not currently support this platform.");
        return;
    }

    if ( ![hb isValidAPIKey:apiKey] ) {
        [hb informUserOfInvalidAPIKey];
        return;
    }

    hb.apiKey = [hb safeTrimmedStr:apiKey];
    hb.customEnvironment = [hb safeTrimmedStr:environment];
    hb.customRevision = [hb safeTrimmedStr:revision];

    [hb setupCrashReportDirectory];
    [hb refreshContextSnapshot];
    [hb setExceptionHandler];
    [hb installSignalHandlers];
    hb.initialized = TRUE;

    // -[NSProcessInfo hostName] can perform a blocking reverse-DNS lookup
    // (seconds on a bad network). It must never run on the crash path, where
    // it would stall the handler before the report is persisted — so resolve
    // it once here, off the main thread. sendPendingCrashReports runs in the
    // same block, AFTER the hostname is cached: replayed signal-crash
    // payloads are built there, and building them first would ship an empty
    // server.hostname for exactly the reports the field exists for.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        hb.cachedHostname = [[NSProcessInfo processInfo] hostName] ?: @"";
        [hb sendPendingCrashReports];
    });
}



// NOTIFY ------------------------------------------------------------------

+ (void) notifyWithString:(NSString*)message {
    [Honeybadger notifyWithString:message errorClass:@"" context:@{} fingerprint:@""];
}

+ (void) notifyWithString:(NSString*)message errorClass:(NSString*)errorClass {
    [Honeybadger notifyWithString:message errorClass:errorClass context:@{} fingerprint:@""];
}

+ (void) notifyWithString:(NSString*)message context:(NSDictionary<NSString*, NSString*>*)context {
    [Honeybadger notifyWithString:message errorClass:@"" context:context fingerprint:@""];
}

+ (void) notifyWithString:(NSString*)message fingerprint:(NSString*)fingerprint {
    [Honeybadger notifyWithString:message errorClass:@"" context:@{} fingerprint:fingerprint];
}

+ (void) notifyWithString:(NSString*)message errorClass:(NSString*)errorClass context:(NSDictionary<NSString*, NSString*>*)context {
    [Honeybadger notifyWithString:message errorClass:errorClass context:context fingerprint:@""];
}

+ (void) notifyWithString:(NSString*)message errorClass:(NSString*)errorClass fingerprint:(NSString*)fingerprint {
    [Honeybadger notifyWithString:message errorClass:errorClass context:@{} fingerprint:fingerprint];
}

+ (void) notifyWithString:(NSString*)message context:(NSDictionary<NSString*, NSString*>*)context fingerprint:(NSString*)fingerprint {
    [Honeybadger notifyWithString:message errorClass:@"" context:context fingerprint:fingerprint];
}

+ (void) notifyWithString:(NSString*)message
    errorClass:(NSString*)errorClass
    context:(NSDictionary<NSString*, NSString*>*)context
    fingerprint:(NSString*)fingerprint
{
    Honeybadger* hb = [Honeybadger sharedInstance];

    if ( ![hb isValidAPIKey:hb.apiKey] ) {
        [hb informUserOfInvalidAPIKey];
        return;
    }

    message = [hb safeTrimmedStr:message];

    if ( message.length == 0 ) {
        NSLog(@"Error: Honeybadger notifyWithString - invalid message");
        return;
    }

    NSMutableDictionary<NSString*, NSString*>* contextForThisError = [hb merge:hb.context with:(context ? context : @{})];

    fingerprint = [hb safeTrimmedStr:fingerprint];

    [hb processEvent:@{
        @"initialHandler" : @"notifyWithString",
        @"errorMsg" : message,
        @"customErrorClass" : [hb safeTrimmedStr:errorClass],
        @"context" : contextForThisError,
        @"fingerprint" : fingerprint,
        @"onNotifyCallStackSymbols" : [hb stackTrace:1]
    }];
}

// ---

+ (void) notifyWithError:(NSError*)error {
    [Honeybadger notifyWithError:error errorClass:@"" context:@{} fingerprint:@""];
}

+ (void) notifyWithError:(NSError*)error errorClass:(NSString*)errorClass {
    [Honeybadger notifyWithError:error errorClass:errorClass context:@{} fingerprint:@""];
}

+ (void) notifyWithError:(NSError*)error context:(NSDictionary<NSString*, NSString*>*)context {
    [Honeybadger notifyWithError:error errorClass:@"" context:context fingerprint:@""];
}

+ (void) notifyWithError:(NSError*)error fingerprint:(NSString*)fingerprint {
    [Honeybadger notifyWithError:error errorClass:@"" context:@{} fingerprint:fingerprint];
}

+ (void) notifyWithError:(NSError*)error errorClass:(NSString*)errorClass context:(NSDictionary<NSString*, NSString*>*)context {
    [Honeybadger notifyWithError:error errorClass:errorClass context:context fingerprint:@""];
}

+ (void) notifyWithError:(NSError*)error errorClass:(NSString*)errorClass fingerprint:(NSString*)fingerprint {
    [Honeybadger notifyWithError:error errorClass:errorClass context:@{} fingerprint:fingerprint];
}

+ (void) notifyWithError:(NSError*)error context:(NSDictionary<NSString*, NSString*>*)context fingerprint:(NSString*)fingerprint {
    [Honeybadger notifyWithError:error errorClass:@"" context:context fingerprint:fingerprint];
}

+ (void) notifyWithError:(NSError*)error
    errorClass:(NSString*)errorClass
    context:(NSDictionary<NSString*, NSString*>*)context
    fingerprint:(NSString*)fingerprint
{
    if ( !error ) return;

    Honeybadger* hb = [Honeybadger sharedInstance];

    if ( ![hb isValidAPIKey:hb.apiKey] ) {
        [hb informUserOfInvalidAPIKey];
        return;
    }

    NSMutableDictionary<NSString*, NSString*>* contextForThisError = [hb merge:hb.context with:(context ? context : @{})];

    fingerprint = [hb safeTrimmedStr:fingerprint];

    [hb processEvent:@{
        @"type" : @"Error",
        @"initialHandler" : @"notifyWithError",
        @"userInfo" : error.userInfo ? error.userInfo : @{},
        @"customErrorClass" : [hb safeTrimmedStr:errorClass],
        @"errorDomain" : [hb safeTrimmedStr:error.domain],
        @"localizedDescription" : [hb safeTrimmedStr:error.localizedDescription],
        @"context" : contextForThisError,
        @"fingerprint" : fingerprint,
        @"onNotifyCallStackSymbols" : [hb stackTrace:1]
    }];
}



+ (void) setContext:(NSDictionary<NSString*, NSString*>*)context
{
    if ( context ) {
        Honeybadger* hb = [Honeybadger sharedInstance];
        hb.context = [hb merge:hb.context with:context];
        [hb refreshContextSnapshot];
    }
}



+ (void) resetContext
{
    Honeybadger* hb = [Honeybadger sharedInstance];
    hb.context = [NSMutableDictionary dictionary];
    [hb refreshContextSnapshot];
}



// Refreshes the static JSON snapshot (hb_context_json / hb_context_json_length)
// used by the crash-time signal handler. See the comment on hb_context_json
// for why this exists. Must only run in normal context.
- (void) refreshContextSnapshot
{
    NSData* data = nil;
    if ( _context && [NSJSONSerialization isValidJSONObject:_context] ) {
        data = [NSJSONSerialization dataWithJSONObject:_context options:0 error:nil];
    }
    if ( !data || data.length > HB_MAX_CONTEXT_JSON ) {
        // Unserializable or oversized: omit entirely rather than persist
        // truncated (invalid) JSON.
        hb_context_json_length = 0;
        return;
    }
    hb_context_json_length = 0;  // invalidate while the buffer is mid-copy
    memcpy(hb_context_json, data.bytes, data.length);
    hb_context_json_length = (int)data.length;
}


// -------------------------------------------------------------------------


- (id) init
{
    self = [super init];

    if ( self )
    {
        _apiKey = @"";
        _initialized = FALSE;
        _context = [NSMutableDictionary dictionary];
        _cachedHostname = @"";
    }

    return self;
}



- (BOOL) isValidAPIKey:(NSString*)apiKey
{
    return [self safeTrimmedStr:apiKey].length > 0;
}



- (void) informUserOfInvalidAPIKey
{
    NSLog(@"Error: Please initialize Honeybadger by calling configureWithAPIKey: with a valid Honeybadger.io API key.");
}



// -- CRASH REPORT DIRECTORY -----------------------------------------------

- (NSString*) crashReportDirectory
{
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString* cachesDir = paths.firstObject;
    return [cachesDir stringByAppendingPathComponent:@"HoneybadgerCrashReports"];
}

- (void) setupCrashReportDirectory
{
    NSString* dir = [self crashReportDirectory];
    NSFileManager* fm = [NSFileManager defaultManager];
    if ( ![fm fileExistsAtPath:dir] ) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    // Pre-compute signal crash file path as a C string for async-signal-safe access
    NSString* signalPath = [dir stringByAppendingPathComponent:@"signal_crash.bin"];
    strlcpy(hb_signal_crash_file_path, [signalPath fileSystemRepresentation], PATH_MAX);
}



// -- EXCEPTION HANDLER ----------------------------------------------------

- (void) setExceptionHandler
{
#if TARGET_OS_OSX
    // On macOS, AppKit's event loop wraps every event handler (e.g. button
    // actions) in its own try/catch. Exceptions thrown there are caught by
    // AppKit, so they never become "uncaught" and NSUncaughtExceptionHandler
    // never sees them. hb_install_appkit_exception_hook() hooks AppKit's
    // -[NSApplication reportException:] so Honeybadger captures them anyway.
    //
    // NSApplicationCrashOnExceptions makes AppKit terminate the app after such
    // an exception (rather than swallowing it and continuing in a bad state).
    // registerDefaults: only applies when the host app has not set its own
    // value, so an explicit app setting still wins.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"NSApplicationCrashOnExceptions" : @YES }];
    hb_install_appkit_exception_hook();
#endif

    hb_previous_exception_handler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(&hb_exception_handler);
}

// Builds a Honeybadger notice from an NSException and persists it to disk.
// Shared by the uncaught-exception handler and, on macOS, the AppKit
// -[NSApplication reportException:] hook.
HB_PRIVATE void hb_capture_exception(NSException *exception, NSString *handlerName)
{
    if ( !exception ) {
        return;
    }

    Honeybadger* hb = [Honeybadger sharedInstance];

    [hb processEvent:@{
        @"type" : @"Exception",
        @"name" : [hb safe:exception.name],
        @"reason" : [hb safe:exception.reason],
        @"userInfo" : exception.userInfo ? exception.userInfo : @{},
        @"callStackSymbols" : exception.callStackSymbols ? exception.callStackSymbols : @[],
        @"initialHandler" : handlerName
    } persistOnly:YES];

    // Mark the exception as reported so the signal handler doesn't also write a
    // redundant report for the teardown signal that follows (set only after the
    // report is persisted, so a crash mid-persist still falls back to the
    // signal path).
    hb_exception_captured = 1;

    // If the process survives this capture — macOS reportException: with
    // NSApplicationCrashOnExceptions explicitly disabled by the host app, or a
    // manual reportException: call — a permanently-set latch would silently
    // disable signal reporting forever. Clear it on the next main-runloop
    // turn: a genuinely fatal teardown aborts before this block ever runs, so
    // the latch stays set exactly as long as the teardown needs it.
    dispatch_async(dispatch_get_main_queue(), ^{
        hb_exception_captured = 0;
    });
}

HB_PRIVATE void hb_exception_handler(NSException *exception)
{
    if ( !exception ) {
        if ( hb_previous_exception_handler ) {
            hb_previous_exception_handler(exception);
        }
        return;
    }

    hb_capture_exception(exception, @"hb_exception_handler");

    if ( hb_previous_exception_handler ) {
        hb_previous_exception_handler(exception);
    }
}

#if TARGET_OS_OSX

// AppKit's main event loop wraps every event handler in a try/catch. An
// NSException thrown there is caught by AppKit, so it never becomes an
// "uncaught" exception — NSUncaughtExceptionHandler never sees it. AppKit
// instead routes it through -[NSApplication reportException:]. We replace
// that method's implementation so Honeybadger can capture the exception
// in-process, at crash time, with an accurate backtrace and binary images.
static void hb_swizzled_report_exception(id self, SEL _cmd, NSException *exception)
{
    hb_capture_exception(exception, @"reportException");

    // Call through to the original -[NSApplication reportException:].
    if ( hb_original_report_exception ) {
        ((void (*)(id, SEL, NSException *))hb_original_report_exception)(self, _cmd, exception);
    }
}

static void hb_install_appkit_exception_hook(void)
{
    // Guarded so repeated configureWithAPIKey: calls cannot swap twice
    // (which would restore the original implementation).
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Resolve NSApplication at runtime so the SDK carries no AppKit link
        // dependency. A macOS host with no AppKit simply skips the hook.
        Class appClass = NSClassFromString(@"NSApplication");
        if ( !appClass ) {
            return;
        }
        Method method = class_getInstanceMethod(appClass, @selector(reportException:));
        if ( !method ) {
            return;
        }
        hb_original_report_exception = method_getImplementation(method);
        method_setImplementation(method, (IMP)hb_swizzled_report_exception);
    });
}

#endif



// -- SIGNAL HANDLERS ------------------------------------------------------

- (void) installSignalHandlers
{
    static dispatch_once_t dyldOnce;
    dispatch_once(&dyldOnce, ^{
        // Callback is suppressed during registration (see
        // hb_dyld_registration_complete); the refresh below covers every image
        // loaded up to this point, and the callback covers later loads.
        _dyld_register_func_for_add_image(&hb_on_dyld_image_added);
        hb_dyld_registration_complete = 1;
    });
    hb_refresh_binary_images();

    // sigaltstack is per-thread; this call covers the thread calling
    // configure (in practice the main thread). Threads created afterward are
    // covered by hb_thread_introspection_hook below; threads already alive
    // stay uncovered — no API can reach them.
    stack_t altStack;
    memset(&altStack, 0, sizeof(altStack));
    altStack.ss_sp = hb_signal_stack;
    altStack.ss_size = sizeof(hb_signal_stack);
    sigaltstack(&altStack, NULL);

    static dispatch_once_t introspectionOnce;
    dispatch_once(&introspectionOnce, ^{
        if ( pthread_key_create(&hb_thread_alt_stack_key, NULL) == 0 ) {
            hb_previous_introspection_hook =
                pthread_introspection_hook_install(hb_thread_introspection_hook);
        }
    });

    // Pre-warm backtrace()'s lazy unwinder/dyld state from a normal context so
    // the crash-time call in hb_signal_handler takes no initialization paths.
    void* warmup[2];
    backtrace(warmup, 2);

    for ( int i = 0; i < HB_SIGNAL_COUNT; i++ ) {
        struct sigaction action;
        memset(&action, 0, sizeof(action));
        // Block the other fatal signals while the handler runs so a
        // same-thread async signal can't interrupt it mid-write. Cross-thread
        // concurrent crashes are handled by hb_handler_entered in the handler.
        sigfillset(&action.sa_mask);
        action.sa_sigaction = hb_signal_handler;
        action.sa_flags = SA_ONSTACK | SA_SIGINFO;
        sigaction(hb_signals[i], &action, &hb_previous_signal_actions[i]);
    }
}

// Hands the signal to the previously installed handler with full fidelity.
// A SA_SIGINFO predecessor (Crashlytics, Sentry, PLCrashReporter) is invoked
// DIRECTLY with the original siginfo_t/ucontext_t — re-raising instead would
// deliver a synthetic signal (si_code SI_USER-like, no fault address) and
// corrupt the co-installed reporter's crash data. Plain handlers are invoked
// directly with the signal number. SIG_DFL restores and re-raises so the
// default action (terminate) runs; SIG_IGN does nothing. In every case our
// own disposition is replaced first, so a predecessor that returns without
// terminating re-faults into the predecessor, not back through us.
// Async-signal-safe: sigaction(), raise(), and direct calls only.
HB_PRIVATE void hb_chain_previous_signal(int signal, siginfo_t* info, void* uap)
{
    for ( int i = 0; i < HB_SIGNAL_COUNT; i++ ) {
        if ( hb_signals[i] != signal ) {
            continue;
        }
        struct sigaction previous = hb_previous_signal_actions[i];

        // Remove ourselves from the delivery path before chaining.
        sigaction(signal, &previous, NULL);

        if ( previous.sa_flags & SA_SIGINFO ) {
            if ( previous.sa_sigaction ) {
                previous.sa_sigaction(signal, info, uap);
            }
        } else if ( previous.sa_handler == SIG_DFL ) {
            // raise() alone would only mark the signal pending: sa_mask has
            // it blocked for the duration of our handler, so the default
            // (terminating) action would run only after we return — leaving
            // a window where the re-armed entry latch could let a concurrent
            // crash truncate the just-written crash file. Unblock it first so
            // the re-raise delivers immediately and never returns.
            // pthread_sigmask is async-signal-safe (POSIX); sigemptyset/
            // sigaddset are plain bitmask operations on Darwin.
            sigset_t unblock;
            sigemptyset(&unblock);
            sigaddset(&unblock, signal);
            pthread_sigmask(SIG_UNBLOCK, &unblock, NULL);
            raise(signal);
        } else if ( previous.sa_handler != SIG_IGN && previous.sa_handler ) {
            previous.sa_handler(signal);
        }
        // SIG_IGN: swallow, matching the predecessor's declared intent.
        break;
    }
}

// One-shot entry latch for the capture path. The handler writes shared static
// buffers and a single crash file, so a second fatal signal — another thread
// crashing concurrently (sa_mask is per-thread and can't prevent that), or a
// fault inside the handler itself — must not re-enter the capture path; it
// chains straight to the predecessor instead. __sync_lock_test_and_set is
// lock-free and async-signal-safe on all supported targets.
HB_PRIVATE volatile sig_atomic_t hb_handler_entered = 0;

HB_PRIVATE void hb_signal_handler(int signal, siginfo_t* info, void* uap)
{
    if ( __sync_lock_test_and_set((sig_atomic_t*)&hb_handler_entered, 1) ) {
        hb_chain_previous_signal(signal, info, uap);
        return;
    }

    // If an NSException was already captured and persisted by the exception
    // path, this signal is just the process teardown that follows it (AppKit's
    // crash-on-exceptions trap, or abort() after an uncaught exception). Don't
    // write a second, redundant report for the same crash — only chain so the
    // process still terminates.
    if ( hb_exception_captured ) {
        hb_chain_previous_signal(signal, info, uap);
        // The chain returned, so the process survived this delivery (e.g. a
        // SIG_IGN'd or non-terminating predecessor). Re-arm the one-shot
        // latch — its owner is the only path that reaches this store — so a
        // later real crash is still captured. Mirrors hb_exception_captured's
        // own reset (see hb_capture_exception); a fatal chain never returns.
        hb_handler_entered = 0;
        return;
    }

    // The entry latch makes crash handling one-shot per process, so static
    // buffers are safe here and keep ~5KB of state off the (possibly
    // exhausted) crashing stack.
    static HBSignalCrashHeader header;
    memset(&header, 0, sizeof(header));
    header.magic = HB_SIGNAL_CRASH_MAGIC;
    header.version = HB_SIGNAL_CRASH_VERSION;
    header.signal_number = signal;

    // backtrace() is not formally async-signal-safe; it is the one documented
    // exception to the signal-safety rule in this handler. It is pre-warmed at
    // install time so no lazy initialization runs here. Issue #13 tracks
    // replacing it with a hand-rolled frame-pointer walk.
    static void* addresses[HB_MAX_CRASH_ADDRESSES];
    int count = backtrace(addresses, HB_MAX_CRASH_ADDRESSES);

    // Frames 0 and 1 are this handler and the kernel trampoline (_sigtramp);
    // skip them so reports group by the faulting frame, not by Honeybadger.
    int skip = (count > 2) ? 2 : 0;
    header.address_count = count - skip;
    for ( int i = 0; i < header.address_count; i++ ) {
        header.addresses[i] = (uint64_t)(uintptr_t)addresses[i + skip];
    }

    // Persist the pre-captured image table (see hb_refresh_binary_images):
    // symbolication data must come from THIS process's address space — the
    // next launch has different ASLR slides.
    header.image_count = hb_binary_image_count;

    // Same accepted-race treatment for the context snapshot (see
    // hb_context_json): clamp what could only be a torn/invalid length rather
    // than trust it blindly.
    int contextLength = hb_context_json_length;
    if ( contextLength < 0 || contextLength > HB_MAX_CONTEXT_JSON ) {
        contextLength = 0;
    }
    header.context_length = contextLength;

    // Accepted race: if a dyld image load is rebuilding hb_binary_images on
    // another thread at the instant of the crash, the persisted table can be
    // torn. The reader validates lengths so it can't fault; worst case is
    // degraded symbolication for a crash that coincided with a dylib load.
    int fd = open(hb_signal_crash_file_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if ( fd >= 0 ) {
        write(fd, &header, sizeof(header));
        write(fd, hb_binary_images, (size_t)header.image_count * sizeof(HBBinaryImage));
        if ( contextLength > 0 ) {
            write(fd, hb_context_json, (size_t)contextLength);
        }
        close(fd);
    }

    // Chain to the previously installed handler (see hb_chain_previous_signal):
    // a SA_SIGINFO predecessor is invoked directly with the original
    // siginfo_t/ucontext_t, a plain handler is invoked directly with the
    // signal number, SIG_DFL restores and re-raises so the default action
    // runs, and SIG_IGN is swallowed — and in every case our handler is
    // removed from the delivery path first, so a predecessor that returns
    // without terminating can't loop back through us and re-fault.
    hb_chain_previous_signal(signal, info, uap);

    // See the exception-captured branch above: a returning chain means the
    // process survived, so re-arm the one-shot latch for the next crash.
    hb_handler_entered = 0;
}

- (NSString*) signalName:(int)sig
{
    switch ( sig ) {
        case SIGABRT: return @"SIGABRT";
        case SIGSEGV: return @"SIGSEGV";
        case SIGBUS:  return @"SIGBUS";
        case SIGFPE:  return @"SIGFPE";
        case SIGILL:  return @"SIGILL";
        case SIGTRAP: return @"SIGTRAP";
        default:      return @"UNKNOWN";
    }
}



// -- PENDING CRASH REPORTS ------------------------------------------------

// A unique destination for a signal crash report converted from the binary
// crash file. A fixed name could overwrite an earlier, still-unsent report
// whose async send is in flight — whose completion handler would then delete
// the newer report on success.
- (NSString*) uniqueSignalReportPathInDirectory:(NSString*)dir
{
    NSString* filename = [NSString stringWithFormat:@"crash_signal_%@.json", [[NSUUID UUID] UUIDString]];
    return [dir stringByAppendingPathComponent:filename];
}

- (void) sendPendingCrashReports
{
    NSString* dir = [self crashReportDirectory];
    NSFileManager* fm = [NSFileManager defaultManager];
    NSArray* files = [fm contentsOfDirectoryAtPath:dir error:nil];

    for ( NSString* filename in files ) {
        NSString* path = [dir stringByAppendingPathComponent:filename];

        if ( [filename hasSuffix:@".json"] ) {
            NSData* data = [NSData dataWithContentsOfFile:path];
            if ( data ) {
                [self sendPayloadData:data filePath:path];
            }
        } else if ( [filename hasSuffix:@".bin"] ) {
            NSData* data = [NSData dataWithContentsOfFile:path];
            NSDictionary* payload = data ? [self payloadFromSignalCrashFileData:data] : nil;
            if ( !payload ) {
                // Unreadable, foreign, or stale-format file: delete it so it
                // isn't reprocessed on every launch.
                [fm removeItemAtPath:path error:nil];
                continue;
            }
            NSData* jsonData = [self toNSData:payload];
            if ( !jsonData ) {
                [fm removeItemAtPath:path error:nil];
                continue;
            }
            // Convert to a uniquely-named JSON report on disk, then send from
            // the JSON path so the report survives a failed send.
            NSString* jsonPath = [self uniqueSignalReportPathInDirectory:dir];
            if ( ![jsonData writeToFile:jsonPath atomically:YES] ) {
                // JSON write failed (disk full, permissions): keep the .bin —
                // it's the only persisted copy — and retry conversion on the
                // next launch.
                continue;
            }
            [fm removeItemAtPath:path error:nil];
            [self sendPayloadData:jsonData filePath:jsonPath];
        }
    }
}

// Rebuilds a notice from a persisted signal crash file. Every piece of
// address-space data (frames' image mapping, binary_images) comes from the
// persisted file — never from live dyld/dladdr, which describe THIS launch's
// address space, not the crashed one.
- (NSDictionary*) payloadFromSignalCrashFileData:(NSData*)data
{
    if ( data.length < sizeof(HBSignalCrashHeader) ) return nil;
    HBSignalCrashHeader header;
    [data getBytes:&header length:sizeof(header)];
    if ( header.magic != HB_SIGNAL_CRASH_MAGIC || header.version != HB_SIGNAL_CRASH_VERSION ) return nil;

    int32_t addressCount = header.address_count;
    if ( addressCount < 0 ) addressCount = 0;
    if ( addressCount > HB_MAX_CRASH_ADDRESSES ) addressCount = HB_MAX_CRASH_ADDRESSES;

    int32_t imageCount = header.image_count;
    if ( imageCount < 0 || imageCount > HB_MAX_BINARY_IMAGES ) return nil;

    int32_t contextLength = header.context_length;
    if ( contextLength < 0 || contextLength > HB_MAX_CONTEXT_JSON ) return nil;

    NSUInteger expectedLength = sizeof(HBSignalCrashHeader) + (NSUInteger)imageCount * sizeof(HBBinaryImage) + (NSUInteger)contextLength;
    if ( data.length < expectedLength ) return nil;

    const HBBinaryImage* images = (const HBBinaryImage*)((const uint8_t*)data.bytes + sizeof(HBSignalCrashHeader));

    // A torn or unparseable snapshot degrades to an empty context; the crash
    // report itself is never dropped over context.
    NSDictionary* persistedContext = @{};
    if ( contextLength > 0 ) {
        NSData* contextData = [data subdataWithRange:
            NSMakeRange(sizeof(HBSignalCrashHeader) + (NSUInteger)imageCount * sizeof(HBBinaryImage),
                        (NSUInteger)contextLength)];
        id parsed = [NSJSONSerialization JSONObjectWithData:contextData options:0 error:nil];
        if ( [parsed isKindOfClass:[NSDictionary class]] ) {
            persistedContext = parsed;
        }
    }

    NSMutableArray* frames = [NSMutableArray arrayWithCapacity:(NSUInteger)addressCount];
    for ( int32_t i = 0; i < addressCount; i++ ) {
        uint64_t addr = header.addresses[i];
        NSString* addressStr = [NSString stringWithFormat:@"0x%llx", (unsigned long long)addr];

        // Attribute the address to the recorded image whose mapped range
        // [load_address, load_address + size) contains it. With the table
        // capped (HB_MAX_BINARY_IMAGES), an address inside a dropped image
        // must stay honestly unattributed ("") rather than be blamed on the
        // nearest recorded image below it. size == 0 (unknown) falls back to
        // the nearest-below heuristic for that image.
        NSString* file = @"";
        uint64_t bestLoad = 0;
        for ( int32_t j = 0; j < imageCount; j++ ) {
            uint64_t load = images[j].load_address;
            if ( load > addr || load < bestLoad ) continue;
            if ( images[j].size != 0 && addr >= load + images[j].size ) continue;
            bestLoad = load;
            file = [self stringFromImageName:&images[j]];
        }
        [frames addObject:@{ @"file" : file, @"method" : addressStr, @"number" : @"", @"address" : addressStr }];
    }

    NSString* signalName = [self signalName:header.signal_number];
    NSMutableArray* binaryImages = [NSMutableArray arrayWithCapacity:(NSUInteger)imageCount];
    for ( int32_t i = 0; i < imageCount; i++ ) {
        [binaryImages addObject:[self dictionaryFromBinaryImage:&images[i]]];
    }

    NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:@{
        @"notifier" : @{
            @"name" : @"Honeybadger Cocoa Notifier",
            @"url" : @"https://github.com/honeybadger-io/honeybadger-cocoa",
            @"version" : HONEYBADGER_APPLE_SDK_VERSION
        },
        @"error" : @{
            @"class" : [NSString stringWithFormat:@"%@ Signal", shortPlatformName],
            @"message" : [NSString stringWithFormat:@"Signal %@ (%d)", signalName, header.signal_number],
            @"backtrace" : frames
        },
        @"request" : @{
            @"context" : persistedContext
        },
        @"server" : @{
            @"environment_name" : [self environment],
            @"hostname" : (self.cachedHostname ?: @""),
            @"pid" : @(0)  // the crashed process's pid is gone; 0 = unknown
        },
        @"binary_images" : binaryImages
    }];

    [self addServerRevisionToPayload:payload];

    return payload;
}



// -- PROCESS EVENT --------------------------------------------------------

- (void) processEvent:(NSDictionary*)data
{
    [self processEvent:data persistOnly:NO];
}

- (void) processEvent:(NSDictionary*)data persistOnly:(BOOL)persistOnly
{
    // Do we have a custom error class name provided by the user?
    NSString* errorClass = [self stringValueForKey:@"customErrorClass" fromDictionary:data defaultValue:@""];
    if ( !errorClass || errorClass.length == 0 ) {
        // ... we don't; generate a fallback/default error class name.
        errorClass = [NSString stringWithFormat:@"%@ %@", [self platformName], [self stringValueForKey:@"type" fromDictionary:data defaultValue:@"Error"]];
    }

    NSDictionary* payloadData = @{
        @"errorClass" : errorClass,
        @"errorMsg" : [self errorMessageFromEventData:data],
        @"details" : @{
            @"errorDomain" : [self stringValueForKey:@"errorDomain" fromDictionary:data defaultValue:@""],
            @"initialHandler" : [self stringValueForKey:@"initialHandler" fromDictionary:data defaultValue:@""],
            @"userInfo" : data[@"userInfo"] ? data[@"userInfo"] : @{},
            @"architecture" : [self currentArchitectureName]
        },
        @"context" : (data[@"context"] ? data[@"context"] : (_context ? _context : @{})),
        @"fingerprint" : (data[@"fingerprint"] ? data[@"fingerprint"] : @""),
        @"backTrace" : [self framesFromCallStack:data]
    };

    NSDictionary* payload = [self buildPayload:payloadData];

    if ( persistOnly ) {
        [self persistPayloadToDisk:payload];
    } else {
        [self sendToHoneybadger:payload];
    }
}



- (NSArray<NSDictionary*>*) framesFromCallStack:(NSDictionary*)data
{
    NSArray<NSString*>* stackLines = @[];

    if ( data[@"onNotifyCallStackSymbols"] ) {
        stackLines = data[@"onNotifyCallStackSymbols"];
    }
    else if ( data[@"callStackSymbols"] ) {
        stackLines = data[@"callStackSymbols"];
    }
    else {
        NSString* localizedDescription = [self stringValueForKey:@"localizedDescription" fromDictionary:data defaultValue:@""];
        if ( localizedDescription.length > 0 ) {
            stackLines = [localizedDescription componentsSeparatedByString:@"\n"];
        }
    }

    NSMutableArray<NSDictionary*>* frames = [NSMutableArray array];

    for ( NSString* line in stackLines ) {
        [frames addObject:[self extractValuesFromStackFrame:line]];
    }

    return frames;
}



- (NSString*) errorMessageFromEventData:(NSDictionary*)data {
    if ( !data ) return @"";

    NSString* errorMsg = [self safeTrimmedStr:data[@"errorMsg"]];
    if ( errorMsg.length > 0 ) return errorMsg;

    NSString* localizedDescription = [self safeTrimmedStr:data[@"localizedDescription"]];
    if ( localizedDescription.length > 0 ) {
        NSUInteger startOfCallStackIndex = [localizedDescription rangeOfString:@"callstack: (\n"].location;
        if ( startOfCallStackIndex == NSNotFound ) {
            NSArray<NSString*>* lines = [localizedDescription componentsSeparatedByString:@"\n"];
            return lines.count == 0 ? localizedDescription : [self safeTrimmedStr:lines.firstObject];
        } else {
            return [self safeTrimmedStr:[localizedDescription substringToIndex:startOfCallStackIndex]];
        }
    }

    NSString* name = [self safeTrimmedStr:data[@"name"]];
    NSString* reason = [self safeTrimmedStr:data[@"reason"]];
    if ( name.length > 0 || reason.length > 0 ) {
        return [self safeTrimmedStr:[NSString stringWithFormat:@"%@ : %@", name, reason]];
    }

    return @"";
}


- (NSString*) safe:(NSString*)s
{
    return s != nil ? s : @"";
}


- (NSString*) safeTrimmedStr:(NSString*)str
{
    return [[self safe:str] stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}


- (NSString*) stringValueForKey:(NSString*)key fromDictionary:(NSDictionary*)dict defaultValue:(NSString*)defaultValue {
    if ( !dict ) return defaultValue;

    NSObject* obj = [dict objectForKey:key];
    if ( !obj ) return defaultValue;

    if ( [obj isKindOfClass:[NSString class]] ) return (NSString*)obj;
    if ( [obj isKindOfClass:[NSNumber class]] ) return [(NSNumber*)obj stringValue];

    return defaultValue;
}


- (NSMutableDictionary*) merge:(NSDictionary*)dict1 with:(NSDictionary*)dict2
{
    NSMutableDictionary* mergedDictionary = [NSMutableDictionary dictionary];

    if ( dict1 ) {
        [mergedDictionary addEntriesFromDictionary:dict1];
    }

    if ( dict2 ) {
        [mergedDictionary addEntriesFromDictionary:dict2];
    }

    return mergedDictionary;
}



// -- BUILD PAYLOAD --------------------------------------------------------

- (NSDictionary*) buildPayload:(NSDictionary*)data
{
    NSMutableDictionary* errorObj = [NSMutableDictionary dictionaryWithDictionary:@{
        @"class" : [self stringValueForKey:@"errorClass" fromDictionary:data defaultValue:[NSString stringWithFormat:@"%@ Error", shortPlatformName]],
        @"message" : [self stringValueForKey:@"errorMsg" fromDictionary:data defaultValue:@"Unknown Error"],
        @"backtrace" : data[@"backTrace"] ? data[@"backTrace"] : @[]
    }];

    NSString* fingerprint = [self stringValueForKey:@"fingerprint" fromDictionary:data defaultValue:@""];
    if ( fingerprint.length > 0 ) {
        errorObj[@"fingerprint"] = fingerprint;
    }

    NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:@{
        @"notifier" : @{
            @"name" : @"Honeybadger Cocoa Notifier",
            @"url" : @"https://github.com/honeybadger-io/honeybadger-cocoa",
            @"version" : HONEYBADGER_APPLE_SDK_VERSION
        },
        @"error" : errorObj,
        @"request" : @{
            @"context" : data[@"context"] ? data[@"context"] : @{}
        },
        @"server" : @{
            @"environment_name" : [self environment],
            @"hostname" : (self.cachedHostname ?: @""),
            @"pid" : @([[NSProcessInfo processInfo] processIdentifier])
        }
    }];

    // Fix: use direct dictionary access instead of stringValueForKey: (details is an NSDictionary)
    id details = data[@"details"];
    if ( details && [details isKindOfClass:[NSDictionary class]] ) {
        payload[@"details"] = @{
            shortPlatformName : details
        };
    }

    NSArray* binaryImages = [self captureBinaryImages];
    if ( binaryImages ) {
        payload[@"binary_images"] = binaryImages;
    }

    [self addServerRevisionToPayload:payload];

    return payload;
}



// Adds the configured revision (if any) to the payload's server block. The
// notices schema defines revision at server.revision; it's omitted entirely
// when no revision was configured.
- (void) addServerRevisionToPayload:(NSMutableDictionary*)payload
{
    NSString* revision = self.customRevision;
    if ( revision.length > 0 ) {
        NSMutableDictionary* server = [payload[@"server"] mutableCopy];
        server[@"revision"] = revision;
        payload[@"server"] = server;
    }
}



// -- PERSIST & SEND -------------------------------------------------------

- (void) persistPayloadToDisk:(NSDictionary*)payload
{
    NSData* data = [self toNSData:payload];
    if ( !data ) return;

    NSString* filename = [NSString stringWithFormat:@"crash_%f.json", [[NSDate date] timeIntervalSince1970]];
    NSString* path = [[self crashReportDirectory] stringByAppendingPathComponent:filename];
    [data writeToFile:path atomically:YES];
}

- (void) sendToHoneybadger:(NSDictionary*)payload
{
    if ( !payload || ![self isValidAPIKey:_apiKey] ) {
        return;
    }

    NSData* dataToSend = [self toNSData:payload];
    if ( !dataToSend ) {
        return;
    }

    // Persist to disk first so data survives if the process dies before the network request completes
    NSString* filename = [NSString stringWithFormat:@"crash_%f.json", [[NSDate date] timeIntervalSince1970]];
    NSString* filePath = [[self crashReportDirectory] stringByAppendingPathComponent:filename];
    [dataToSend writeToFile:filePath atomically:YES];

    [self sendPayloadData:dataToSend filePath:filePath];
}

- (void) sendPayloadData:(NSData*)dataToSend filePath:(NSString*)filePath
{
    NSString* url = @"https://api.honeybadger.io/v1/notices";

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"text/json, application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:_apiKey forHTTPHeaderField:@"X-API-Key"];
    [request setValue:[self buildUserAgent] forHTTPHeaderField:@"User-Agent"];
    [request setHTTPBody:dataToSend];

    NSURLSession* session = [NSURLSession sharedSession];
    NSURLSessionDataTask* task = [session dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
        BOOL success = !error && httpResponse.statusCode >= 200 && httpResponse.statusCode < 300;
        if ( success ) {
            NSLog(@"Honeybadger successful report");
            if ( filePath ) {
                [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
            }
        } else {
            NSLog(@"Honeybadger report error: %@ (HTTP %ld)",
                  error ? error.localizedDescription : @"server error",
                  (long)httpResponse.statusCode);
        }
    }];

    [task resume];
}


- (NSString*) buildUserAgent
{
    NSString* clientName = @"Honeybadger Cocoa";
    NSString* clientVersion = HONEYBADGER_APPLE_SDK_VERSION;
    NSString* platformName = [self platformName];
    NSString* platformVersion = [self platformVersion];

    return [NSString stringWithFormat:@"%@ %@; %@; %@",
        clientName, clientVersion, platformVersion, platformName];
}



- (NSString*) platformName
{
#if (TARGET_OS_IOS || TARGET_OS_VISION)
    return [[UIDevice currentDevice] systemName];
#elif TARGET_OS_OSX
    return @"macOS";
#else
    NSLog(@"Error: unsupported platform.");
    return @"";
#endif
}



- (NSString*) currentArchitectureName
{
    const struct mach_header* header = _dyld_get_image_header(0);
    const char* name = header ? macho_arch_name_for_mach_header(header) : NULL;
    return name ? [NSString stringWithUTF8String:name] : @"";
}



- (NSString*) platformVersion
{
#if (TARGET_OS_IOS || TARGET_OS_VISION)
     return [[UIDevice currentDevice] systemVersion];
#elif TARGET_OS_OSX
    return [[NSProcessInfo processInfo] operatingSystemVersionString];
#else
    NSLog(@"Error: unsupported platform.");
    return @"";
#endif
}



- (NSString*) environment
{
    if ( self.customEnvironment && self.customEnvironment.length > 0 ) {
        return self.customEnvironment;
    }

#if TARGET_OS_SIMULATOR
    return @"simulator";
#elif DEBUG
    // Both SPM and CocoaPods compile this SDK from source with the host
    // app's build configuration, so DEBUG here tracks the app's Debug builds.
    return @"development";
#else
    return @"production";
#endif
}



// Recursively coerces an object graph into JSON-safe types. Strings, finite
// numbers, and NSNull pass through; arrays and dictionaries are sanitized
// element-by-element (non-string dictionary keys become their description);
// anything else — NSError, NSURL, NSData, NSDate, custom objects, and
// non-finite numbers (NaN/infinity) — is replaced with its string description.
// This prevents a notice from being dropped when, e.g., an NSError userInfo
// contains values that NSJSONSerialization can't encode.
// Upper bound on nesting depth while sanitizing, so a deeply nested or
// self-referential (cyclic) container can't overflow the stack.
#define HB_JSON_MAX_DEPTH 100

- (id) jsonSafeValue:(id)value
{
    return [self jsonSafeValue:value depth:0];
}

- (id) jsonSafeValue:(id)value depth:(NSInteger)depth
{
    if ( value == nil || [value isKindOfClass:[NSNull class]] ) {
        return [NSNull null];
    }
    if ( [value isKindOfClass:[NSString class]] ) {
        return value;
    }
    if ( [value isKindOfClass:[NSNumber class]] ) {
        double d = [(NSNumber*)value doubleValue];
        if ( isnan(d) || isinf(d) ) {
            return [value description];
        }
        return value;
    }

    // Stop descending into containers past the depth limit. This bounds both
    // pathologically deep structures and cycles (e.g. a container that, via an
    // NSError userInfo, references itself), which would otherwise recurse until
    // the stack overflows while building a crash payload.
    if ( depth >= HB_JSON_MAX_DEPTH ) {
        return @"<max depth exceeded>";
    }

    if ( [value isKindOfClass:[NSArray class]] ) {
        NSMutableArray* result = [NSMutableArray arrayWithCapacity:[(NSArray*)value count]];
        for ( id element in (NSArray*)value ) {
            [result addObject:[self jsonSafeValue:element depth:depth + 1]];
        }
        return result;
    }
    if ( [value isKindOfClass:[NSDictionary class]] ) {
        NSMutableDictionary* result = [NSMutableDictionary dictionary];
        [(NSDictionary*)value enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL* stop) {
            NSString* safeKey = [key isKindOfClass:[NSString class]] ? key : [key description];
            if ( safeKey ) {
                result[safeKey] = [self jsonSafeValue:obj depth:depth + 1];
            }
        }];
        return result;
    }
    return [value description];
}

- (NSData*) toNSData:(NSDictionary*)dict
{
    // Fast path: serialize directly. +isValidJSONObject: does NOT reject every
    // input -dataWithJSONObject: will choke on — most notably NaN/infinity
    // NSNumbers, which pass the validity check but throw at write time. So on
    // any failure, coerce the payload to JSON-safe types and retry once. This
    // ensures a notice is never silently dropped at serialization time, while
    // leaving valid payloads untouched on the common path.
    NSData* jsonData = [self serializeJSONObject:dict];
    if ( jsonData ) {
        return jsonData;
    }

    jsonData = [self serializeJSONObject:[self jsonSafeValue:dict]];
    if ( !jsonData ) {
        NSLog(@"HB Error: JSON serialization failed even after sanitizing the payload.");
    }
    return jsonData;
}

- (NSData*) serializeJSONObject:(id)object
{
    if ( ![NSJSONSerialization isValidJSONObject:object] ) {
        return nil;
    }
    @try
    {
        NSError* error = nil;
        NSData* jsonData = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingWithoutEscapingSlashes error:&error];
        if ( error ) {
            return nil;
        }
        return jsonData;
    }
    @catch (NSException* exception)
    {
        // e.g. NaN/infinity NSNumber: isValidJSONObject: returns YES but the
        // write throws. Caller falls back to the sanitized payload.
        return nil;
    }
}



- (BOOL) isSupportedPlatform
{
#if (TARGET_OS_IOS || TARGET_OS_OSX || TARGET_OS_VISION)
    return TRUE;
#endif
    return FALSE;
}



- (NSArray<NSString*>*) stackTrace:(NSUInteger)numTopFramesToRemove {
    numTopFramesToRemove++; // including the call to this method
    NSMutableArray<NSString*>* frames = [NSMutableArray array];
    for ( NSString* frame in [NSThread callStackSymbols] ) {
        if ( numTopFramesToRemove > 0 ) {
            numTopFramesToRemove--;
            continue;
        }
        [frames addObject:frame];
    }
    return frames;
}



- (NSDictionary*) extractValuesFromStackFrame:(NSString*)line
{
    NSMutableDictionary* values = [NSMutableDictionary dictionaryWithDictionary:@{
        @"file" : @"",
        @"number" : @"",
        @"method" : @"",
        @"address" : @""
    }];

    if ( !line ) {
        return values;
    }

    line = [self safeTrimmedStr:line];

    if ( line.length == 0 ) {
        return values;
    }

    NSString* pattern = @"\\d+\\s+(?<moduleName>\\S+)\\s+(?<stackAddress>\\S+)\\s(?<loadAddress>.+)\\s\\+\\s(?<symbolOffset>\\d+)";

    NSError* error = nil;
    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
    if ( error ) {
        NSLog(@"HB Error: %@", error);
        return values;
    }

    NSArray* matches = [regex matchesInString:line options:0 range:NSMakeRange(0, line.length)];
    for ( NSTextCheckingResult* match in matches ) {
        NSString* moduleName = [line substringWithRange:[match rangeWithName:@"moduleName"]];
        NSString* stackAddress = [line substringWithRange:[match rangeWithName:@"stackAddress"]];
        NSString* loadAddress = [line substringWithRange:[match rangeWithName:@"loadAddress"]];

        values[@"file"] = moduleName ? moduleName : @"";
        values[@"method"] = loadAddress ? loadAddress : @"";
        values[@"address"] = stackAddress ? stackAddress : @"";
    }

    return values;
}



// -- BINARY IMAGE CAPTURE -------------------------------------------------

- (NSArray*) captureBinaryImages
{
    hb_refresh_binary_images();
    int count = hb_binary_image_count;
    NSMutableArray* images = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for ( int i = 0; i < count; i++ ) {
        [images addObject:[self dictionaryFromBinaryImage:&hb_binary_images[i]]];
    }
    return images;
}

// The name field of a persisted image record is untrusted input: a torn or
// corrupt crash file may not be NUL-terminated, and stringWithUTF8String:
// would read past the fixed-size field (past the end of the NSData for the
// last record). Copy into a bounded buffer and force-terminate first.
- (NSString*) stringFromImageName:(const HBBinaryImage*)img
{
    char name[sizeof(img->name) + 1];
    memcpy(name, img->name, sizeof(img->name));
    name[sizeof(img->name)] = '\0';
    return [NSString stringWithUTF8String:name] ?: @"";
}

- (NSDictionary*) dictionaryFromBinaryImage:(const HBBinaryImage*)img
{
    NSMutableDictionary* imageDict = [NSMutableDictionary dictionary];
    imageDict[@"name"] = [self stringFromImageName:img];
    imageDict[@"load_address"] = [NSString stringWithFormat:@"0x%llx", (unsigned long long)img->load_address];
    imageDict[@"vmaddr_slide"] = [NSString stringWithFormat:@"0x%llx", (unsigned long long)img->vmaddr_slide];
    imageDict[@"size"] = [NSString stringWithFormat:@"0x%llx", (unsigned long long)img->size];
    if ( img->has_uuid ) {
        const uint8_t* uuid = img->uuid;
        imageDict[@"uuid"] = [NSString stringWithFormat:
            @"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            uuid[0], uuid[1], uuid[2], uuid[3],
            uuid[4], uuid[5],
            uuid[6], uuid[7],
            uuid[8], uuid[9],
            uuid[10], uuid[11], uuid[12], uuid[13], uuid[14], uuid[15]];
    }
    const char* archName = macho_arch_name_for_cpu_type(img->cpu_type, img->cpu_subtype);
    if ( archName ) {
        imageDict[@"arch"] = [NSString stringWithUTF8String:archName] ?: @"";
    }
    return imageDict;
}

@end
