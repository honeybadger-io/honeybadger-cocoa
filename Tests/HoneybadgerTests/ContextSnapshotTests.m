#import "HBTest.h"
#import "HoneybadgerTestAccess.h"
#include <string.h>

void run_context_snapshot_tests(void)
{
    HB_TEST_BEGIN("testSetContextUpdatesSnapshot");
    [Honeybadger resetContext];
    [Honeybadger setContext:@{ @"user_id" : @"u-42" }];
    HB_ASSERT_TRUE(hb_context_json_length > 0);
    NSData* snap = [NSData dataWithBytes:hb_context_json length:(NSUInteger)hb_context_json_length];
    NSDictionary* parsed = [NSJSONSerialization JSONObjectWithData:snap options:0 error:nil];
    HB_ASSERT_EQ_OBJ(parsed[@"user_id"], @"u-42");

    HB_TEST_BEGIN("testResetContextClearsSnapshotToEmptyObject");
    [Honeybadger resetContext];
    NSData* snap2 = [NSData dataWithBytes:hb_context_json length:(NSUInteger)hb_context_json_length];
    NSDictionary* parsed2 = [NSJSONSerialization JSONObjectWithData:snap2 options:0 error:nil];
    HB_ASSERT_NOT_NIL(parsed2);
    HB_ASSERT_EQ_INT((int)parsed2.count, 0);

    HB_TEST_BEGIN("testOversizedContextOmitsSnapshot");
    NSMutableString* big = [NSMutableString string];
    for ( int i = 0; i < 9000; i++ ) { [big appendString:@"x"]; }
    [Honeybadger setContext:@{ @"big" : big }];
    HB_ASSERT_EQ_INT(hb_context_json_length, 0);
    [Honeybadger resetContext];
}
