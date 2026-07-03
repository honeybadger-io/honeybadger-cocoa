#import "HBTest.h"
#import "HoneybadgerTestAccess.h"
#import "../../Sources/ObjC/HoneybadgerCrashTypes.h"
#include <signal.h>

// Builds a synthetic crash file: SIGSEGV, two frames, two images. The image
// load addresses are deliberately values that cannot exist in this test
// process, proving the payload is built from persisted data, not live dyld.
static NSData* synthetic_crash_data(void)
{
    HBSignalCrashHeader header;
    memset(&header, 0, sizeof(header));
    header.magic = HB_SIGNAL_CRASH_MAGIC;
    header.version = HB_SIGNAL_CRASH_VERSION;
    header.signal_number = SIGSEGV;
    header.address_count = 2;
    header.addresses[0] = 0x1000000500;  // inside image A
    header.addresses[1] = 0x2000000900;  // inside image B
    header.image_count = 2;

    HBBinaryImage images[2];
    memset(images, 0, sizeof(images));
    strlcpy(images[0].name, "/App/CrashedApp", sizeof(images[0].name));
    images[0].load_address = 0x1000000000;
    images[0].vmaddr_slide = 0x0000000042;
    images[0].has_uuid = 1;
    memset(images[0].uuid, 0xAB, 16);
    strlcpy(images[1].name, "/usr/lib/libFake.dylib", sizeof(images[1].name));
    images[1].load_address = 0x2000000000;

    NSMutableData* data = [NSMutableData dataWithBytes:&header length:sizeof(header)];
    [data appendBytes:images length:sizeof(images)];
    return data;
}

void run_signal_replay_tests(void)
{
    HB_TEST_BEGIN("testReplayUsesPersistedImagesNotLiveProcess");
    NSDictionary* payload = [[Honeybadger sharedInstance] payloadFromSignalCrashFileData:synthetic_crash_data()];
    HB_ASSERT_NOT_NIL(payload);
    NSArray* images = payload[@"binary_images"];
    HB_ASSERT_EQ_INT(images.count, 2u);
    HB_ASSERT_EQ_OBJ(images[0][@"load_address"], @"0x1000000000");
    HB_ASSERT_EQ_OBJ(images[0][@"vmaddr_slide"], @"0x42");
    HB_ASSERT_EQ_OBJ(images[0][@"name"], @"/App/CrashedApp");
    HB_ASSERT_EQ_OBJ(images[0][@"uuid"], @"ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB");
    HB_ASSERT_NIL(images[1][@"uuid"]);  // has_uuid = 0 → omitted

    HB_TEST_BEGIN("testReplayFramesMapAddressesToPersistedImages");
    payload = [[Honeybadger sharedInstance] payloadFromSignalCrashFileData:synthetic_crash_data()];
    NSArray* frames = payload[@"error"][@"backtrace"];
    HB_ASSERT_EQ_INT(frames.count, 2u);
    HB_ASSERT_EQ_OBJ(frames[0][@"address"], @"0x1000000500");
    HB_ASSERT_EQ_OBJ(frames[0][@"file"], @"/App/CrashedApp");
    HB_ASSERT_EQ_OBJ(frames[1][@"file"], @"/usr/lib/libFake.dylib");
    HB_ASSERT_EQ_OBJ(payload[@"error"][@"message"], @"Signal SIGSEGV (11)");

    HB_TEST_BEGIN("testReplayRejectsCorruptData");
    Honeybadger* hb = [Honeybadger sharedInstance];
    HB_ASSERT_NIL([hb payloadFromSignalCrashFileData:[NSData data]]);

    NSMutableData* wrongMagic = [synthetic_crash_data() mutableCopy];
    uint32_t zero = 0;
    [wrongMagic replaceBytesInRange:NSMakeRange(0, 4) withBytes:&zero];
    HB_ASSERT_NIL([hb payloadFromSignalCrashFileData:wrongMagic]);

    // Truncated: header claims 2 images but only one follows.
    NSData* full = synthetic_crash_data();
    NSData* truncated = [full subdataWithRange:NSMakeRange(0, full.length - sizeof(HBBinaryImage))];
    HB_ASSERT_NIL([hb payloadFromSignalCrashFileData:truncated]);
}
