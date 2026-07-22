#import "HBTest.h"
#import "HoneybadgerTestAccess.h"

void run_payload_tests(void)
{
    HB_TEST_BEGIN("testBuildPayloadOmitsHostname");
    Honeybadger* hb = [Honeybadger sharedInstance];
    NSDictionary* payload = [hb buildPayload:@{ @"errorClass" : @"X", @"errorMsg" : @"y" }];
    HB_ASSERT_NIL(payload[@"server"][@"hostname"]);

    // buildPayload is only used for notify/exception — leaf-less, return-address
    // stacks with no faulting PC — so it always marks frame 0 as a return
    // address. Crash reports build their payload elsewhere and omit this.
    HB_TEST_BEGIN("testBuildPayloadMarksFirstFrameReturnAddress");
    NSDictionary* p2 = [hb buildPayload:@{ @"errorClass" : @"X", @"errorMsg" : @"y" }];
    HB_ASSERT_EQ_OBJ(p2[@"first_frame_is_return_address"], @YES);

    // Raw return addresses build frames in the crash-compatible shape
    // (address is a hex string; method mirrors it; number is empty) so the
    // server symbolicates them against the dSYM like a crash.
    HB_TEST_BEGIN("testFramesFromReturnAddressesUseCrashCompatibleShape");
    NSArray* frames = [hb framesFromCallStack:@{ @"onNotifyCallStackReturnAddresses" : @[ @0x1000, @0x2abc ] }];
    HB_ASSERT_EQ_INT((int)frames.count, 2);
    HB_ASSERT_EQ_OBJ(frames[0][@"address"], @"0x1000");
    HB_ASSERT_EQ_OBJ(frames[0][@"method"], @"0x1000");
    HB_ASSERT_EQ_OBJ(frames[0][@"number"], @"");
    HB_ASSERT_NOT_NIL(frames[0][@"file"]);
    HB_ASSERT_EQ_OBJ(frames[1][@"address"], @"0x2abc");

    // With no return addresses, it falls back to parsing callStackSymbols —
    // still a return-address stack, so the address is extracted into `address`
    // and the flag above stays correct for the fallback too.
    HB_TEST_BEGIN("testFramesFallBackToCallStackSymbols");
    NSArray* fb = [hb framesFromCallStack:@{ @"onNotifyCallStackSymbols" : @[ @"0   MyApp   0x0000000100abc000   -[Foo bar] + 42" ] }];
    HB_ASSERT_EQ_INT((int)fb.count, 1);
    HB_ASSERT_EQ_OBJ(fb[0][@"address"], @"0x0000000100abc000");
    HB_ASSERT_EQ_OBJ(fb[0][@"file"], @"MyApp");
}
