#import "HBTest.h"
#import "HoneybadgerTestAccess.h"

void run_endpoint_tests(void)
{
    Honeybadger* hb = [Honeybadger sharedInstance];

    HB_TEST_BEGIN("testNormalizeValidEndpoint");
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@"https://eu-api.honeybadger.io"],
                     @"https://eu-api.honeybadger.io");
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@"http://localhost:8011"],
                     @"http://localhost:8011");
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@"HTTPS://eu-api.honeybadger.io"],
                     @"HTTPS://eu-api.honeybadger.io");

    HB_TEST_BEGIN("testNormalizeTrimsSlashAndWhitespace");
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@"https://eu-api.honeybadger.io/"],
                     @"https://eu-api.honeybadger.io");
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@"  https://eu-api.honeybadger.io  "],
                     @"https://eu-api.honeybadger.io");

    HB_TEST_BEGIN("testNormalizePreservesPathPrefix");
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@"https://proxy.example.com/hb/"],
                     @"https://proxy.example.com/hb");

    HB_TEST_BEGIN("testNormalizeEmptyIsEmpty");
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@""], @"");
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@"   "], @"");

    HB_TEST_BEGIN("testNormalizeRejectsInvalid");
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@"eu-api.honeybadger.io"], @"");      // no scheme
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@"ftp://eu-api.honeybadger.io"], @""); // wrong scheme
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@"https://"], @"");                    // empty host
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@"https://x.example.com?a=b"], @"");   // query
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@"https://x.example.com#frag"], @"");  // fragment
    HB_ASSERT_EQ_OBJ([hb normalizedEndpointBase:@"not a url"], @"");

    HB_TEST_BEGIN("testResolutionDefault");
    HB_ASSERT_EQ_OBJ([hb noticesURLWithEnvOverride:@"" configuredEndpoint:@""],
                     @"https://api.honeybadger.io/v1/notices");

    HB_TEST_BEGIN("testResolutionConfiguredEndpoint");
    HB_ASSERT_EQ_OBJ([hb noticesURLWithEnvOverride:@""
                              configuredEndpoint:@"https://eu-api.honeybadger.io"],
                     @"https://eu-api.honeybadger.io/v1/notices");

    HB_TEST_BEGIN("testResolutionEnvOverrideWins");
    HB_ASSERT_EQ_OBJ([hb noticesURLWithEnvOverride:@"http://localhost:8011"
                              configuredEndpoint:@"https://eu-api.honeybadger.io"],
                     @"http://localhost:8011/v1/notices");

    HB_TEST_BEGIN("testResolutionBlankOrInvalidEnvFallsThrough");
    HB_ASSERT_EQ_OBJ([hb noticesURLWithEnvOverride:@"   "
                              configuredEndpoint:@"https://eu-api.honeybadger.io"],
                     @"https://eu-api.honeybadger.io/v1/notices");
    HB_ASSERT_EQ_OBJ([hb noticesURLWithEnvOverride:@"not a url"
                              configuredEndpoint:@"https://eu-api.honeybadger.io"],
                     @"https://eu-api.honeybadger.io/v1/notices");

    HB_TEST_BEGIN("testResolutionInvalidConfiguredFallsBackToDefault");
    HB_ASSERT_EQ_OBJ([hb noticesURLWithEnvOverride:@"" configuredEndpoint:@"nope"],
                     @"https://api.honeybadger.io/v1/notices");
}
