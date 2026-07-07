// Integration-test harness: a tiny CLI that links the SDK source directly.
// Modes:
//   crash          - configure, record own load address, die via SIGSEGV
//   overflow       - configure, die via stack-overflow SIGSEGV (proves SA_ONSTACK)
//   overflow-thread - configure, die via stack-overflow SIGSEGV on a thread
//                     created after configure (proves per-thread alt stacks)
//   replay         - configure (triggers pending-report conversion), record
//                     own load address, spin briefly so the .bin -> .json
//                     conversion runs
#import <Foundation/Foundation.h>
#import "Honeybadger.h"
#include <mach-o/dyld.h>

static uint64_t recurse(uint64_t n) {
    volatile char pad[1024];
    pad[0] = (char)n;
    return recurse(n + 1) + (uint64_t)pad[0];
}

int main(int argc, char** argv) {
    @autoreleasepool {
        NSString* mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";
        NSString* outDir = argc > 2 ? [NSString stringWithUTF8String:argv[2]] : NSTemporaryDirectory();

        [Honeybadger configureWithAPIKey:@"integration-test-key" environment:@"integration"];
        [Honeybadger setContext:@{ @"integration_user" : @"user-42" }];

        const struct mach_header* header = _dyld_get_image_header(0);
        NSString* marker = [NSString stringWithFormat:@"0x%lx", (unsigned long)header];
        NSString* markerPath = [outDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"load_address_%@.txt", mode]];
        [marker writeToFile:markerPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

        if ( [mode isEqualToString:@"crash"] ) {
            volatile int* p = NULL;
            *p = 42;  // SIGSEGV
        } else if ( [mode isEqualToString:@"overflow"] ) {
            return (int)recurse(0);  // stack-overflow SIGSEGV
        } else if ( [mode isEqualToString:@"overflow-thread"] ) {
            // Stack overflow on a thread created AFTER configure — captured
            // only if the introspection hook gave that thread an alt stack.
            [NSThread detachNewThreadWithBlock:^{ recurse(0); }];
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:10]];
        } else if ( [mode isEqualToString:@"replay"] ) {
            // Let sendPendingCrashReports convert the .bin and attempt (and
            // fail, with the bogus key) the network send, leaving the .json.
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:5]];
        }
    }
    return 0;
}
