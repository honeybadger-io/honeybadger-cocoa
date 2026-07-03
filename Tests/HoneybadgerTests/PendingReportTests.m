#import "HBTest.h"
#import "HoneybadgerTestAccess.h"

void run_pending_report_tests(void)
{
    HB_TEST_BEGIN("testSignalReportPathsAreUnique");
    Honeybadger* hb = [Honeybadger sharedInstance];
    NSString* a = [hb uniqueSignalReportPathInDirectory:@"/tmp/x"];
    NSString* b = [hb uniqueSignalReportPathInDirectory:@"/tmp/x"];
    HB_ASSERT_FALSE([(a) isEqual:(b)]);
    HB_ASSERT_TRUE([a.lastPathComponent hasPrefix:@"crash_signal_"]);
    HB_ASSERT_TRUE([a hasSuffix:@".json"]);
    HB_ASSERT_TRUE([a hasPrefix:@"/tmp/x/"]);
}
