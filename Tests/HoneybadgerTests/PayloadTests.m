#import "HBTest.h"
#import "HoneybadgerTestAccess.h"

void run_payload_tests(void)
{
    HB_TEST_BEGIN("testBuildPayloadOmitsHostname");
    Honeybadger* hb = [Honeybadger sharedInstance];
    NSDictionary* payload = [hb buildPayload:@{ @"errorClass" : @"X", @"errorMsg" : @"y" }];
    HB_ASSERT_NIL(payload[@"server"][@"hostname"]);
}
