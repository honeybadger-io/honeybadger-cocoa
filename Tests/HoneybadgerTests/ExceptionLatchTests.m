#import "HBTest.h"
#import "HoneybadgerTestAccess.h"

void run_exception_latch_tests(void)
{
    HB_TEST_BEGIN("testLatchResetsWhenProcessSurvives");

    // Capture persists a crash_*.json into the real report directory; snapshot
    // so we can clean up after.
    Honeybadger* hb = [Honeybadger sharedInstance];
    NSString* dir = [hb crashReportDirectory];
    NSFileManager* fm = [NSFileManager defaultManager];
    // persistPayloadToDisk: does not create missing parent directories (only
    // configureWithAPIKey: does, via setupCrashReportDirectory) — ensure the
    // directory exists so the capture below persists a real crash_*.json.
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSSet* before = [NSSet setWithArray:([fm contentsOfDirectoryAtPath:dir error:nil] ?: @[])];

    hb_exception_captured = 0;
    NSException* e = [NSException exceptionWithName:@"HBTest" reason:@"latch test" userInfo:nil];
    hb_capture_exception(e, @"unit-test");
    HB_ASSERT_EQ_INT((int)hb_exception_captured, 1);

    // Prove the capture actually persisted a report to disk.
    NSArray* afterCapture = [fm contentsOfDirectoryAtPath:dir error:nil] ?: @[];
    HB_ASSERT_TRUE(afterCapture.count > before.count);

    // The reset is scheduled on the main queue; spin the runloop to run it —
    // this models "the process survived the capture".
    __block BOOL done = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    while (!done) {
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    HB_ASSERT_EQ_INT((int)hb_exception_captured, 0);

    for ( NSString* f in ([fm contentsOfDirectoryAtPath:dir error:nil] ?: @[]) ) {
        if ( ![before containsObject:f] ) {
            [fm removeItemAtPath:[dir stringByAppendingPathComponent:f] error:nil];
        }
    }
}
