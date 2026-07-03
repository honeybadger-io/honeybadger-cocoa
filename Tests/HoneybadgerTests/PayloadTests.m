#import "HBTest.h"
#import "HoneybadgerTestAccess.h"

void run_payload_tests(void)
{
    HB_TEST_BEGIN("testBuildPayloadUsesCachedHostname");
    Honeybadger* hb = [Honeybadger sharedInstance];
    hb.cachedHostname = @"test-host.example";
    NSDictionary* payload = [hb buildPayload:@{ @"errorClass" : @"X", @"errorMsg" : @"y" }];
    HB_ASSERT_EQ_OBJ(payload[@"server"][@"hostname"], @"test-host.example");
}
