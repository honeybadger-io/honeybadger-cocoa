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
    // Device info (#3): a "Device" group in details carries the hardware
    // model, OS name/version, and locale so the error page can show what
    // the app was running on. It sits alongside the platform group so
    // notices from `notify` keep their existing errorDomain/userInfo block.
    HB_TEST_BEGIN("testBuildPayloadIncludesDeviceDetails");
    NSDictionary* p3 = [hb buildPayload:@{ @"errorClass" : @"X", @"errorMsg" : @"y" }];
    NSDictionary* device = p3[@"details"][@"Device"];
    HB_ASSERT_NOT_NIL(device);
    HB_ASSERT_TRUE([device[@"model"] length] > 0);
    HB_ASSERT_TRUE([device[@"os"] length] > 0);
    HB_ASSERT_TRUE([device[@"os_version"] length] > 0);
    HB_ASSERT_TRUE([device[@"architecture"] length] > 0);
    HB_ASSERT_TRUE([device[@"locale"] length] > 0);

    HB_TEST_BEGIN("testBuildPayloadDeviceDetailsDoNotReplacePlatformDetails");
    NSDictionary* p4 = [hb buildPayload:@{ @"errorClass" : @"X", @"errorMsg" : @"y",
                                           @"details" : @{ @"errorDomain" : @"d" } }];
    HB_ASSERT_EQ_INT((int)[p4[@"details"] count], 2);
    HB_ASSERT_NOT_NIL(p4[@"details"][@"Device"]);
    NSString* platformKey = [[p4[@"details"] allKeys] filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"SELF != 'Device'"]].firstObject;
    HB_ASSERT_EQ_OBJ(p4[@"details"][platformKey][@"errorDomain"], @"d");
    // On the iOS/visionOS simulator, hw.machine is the host CPU ("arm64"),
    // not the simulated device. Xcode exports SIMULATOR_MODEL_IDENTIFIER
    // ("iPhone16,2") into the simulated process, so that wins when present.
    // It is never set on a real device or macOS, so this is safe everywhere.
    HB_TEST_BEGIN("testDeviceModelPrefersSimulatorModelIdentifier");
    setenv("SIMULATOR_MODEL_IDENTIFIER", "iPhone16,2", 1);
    NSDictionary* p5 = [hb buildPayload:@{ @"errorClass" : @"X", @"errorMsg" : @"y" }];
    HB_ASSERT_EQ_OBJ(p5[@"details"][@"Device"][@"model"], @"iPhone16,2");
    unsetenv("SIMULATOR_MODEL_IDENTIFIER");

    HB_TEST_BEGIN("testDeviceModelFallsBackToSysctlWithoutSimulatorVar");
    NSDictionary* p6 = [hb buildPayload:@{ @"errorClass" : @"X", @"errorMsg" : @"y" }];
    NSString* model = p6[@"details"][@"Device"][@"model"];
    HB_ASSERT_TRUE(model.length > 0);
    HB_ASSERT_FALSE([model isEqualToString:@"iPhone16,2"]);
}
