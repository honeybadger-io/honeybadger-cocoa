#import "HBTest.h"
#import "HoneybadgerTestAccess.h"

void run_environment_tests(void)
{
    HB_TEST_BEGIN("testDefaultEnvironmentTracksBuildConfiguration");
    Honeybadger* hb = [Honeybadger sharedInstance];
    [hb setValue:@"" forKey:@"customEnvironment"];
    NSString* env = [hb environment];
#if TARGET_OS_SIMULATOR
    HB_ASSERT_EQ_OBJ(env, @"simulator");
#elif DEBUG
    // The test target and SDK target build with the same configuration, so
    // a debug test run must see the debug default.
    HB_ASSERT_EQ_OBJ(env, @"development");
#else
    HB_ASSERT_EQ_OBJ(env, @"production");
#endif

    HB_TEST_BEGIN("testCustomEnvironmentWins");
    [hb setValue:@"staging" forKey:@"customEnvironment"];
    HB_ASSERT_EQ_OBJ([hb environment], @"staging");
    [hb setValue:@"" forKey:@"customEnvironment"];
}
