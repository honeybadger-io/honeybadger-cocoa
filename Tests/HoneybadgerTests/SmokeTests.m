#import "HBTest.h"
#import "HoneybadgerTestAccess.h"

void run_smoke_tests(void)
{
    HB_TEST_BEGIN("testSharedInstanceExists");
    HB_ASSERT_NOT_NIL([Honeybadger sharedInstance]);
    HB_ASSERT_TRUE([Honeybadger sharedInstance] == [Honeybadger sharedInstance]);
}
