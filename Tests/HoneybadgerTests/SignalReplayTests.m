#import "HBTest.h"
#import "HoneybadgerTestAccess.h"
#import "../../Sources/ObjC/HoneybadgerCrashTypes.h"
#include <signal.h>
#include <stddef.h>

// Builds a synthetic crash file: SIGSEGV, two frames, two images, and a JSON
// context blob. The image load addresses are deliberately values that cannot
// exist in this test process, proving the payload is built from persisted
// data, not live dyld.
static const char* kSyntheticContextJSON = "{\"user_id\":\"u-42\"}";

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
    header.context_length = (int32_t)strlen(kSyntheticContextJSON);

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
    [data appendBytes:kSyntheticContextJSON length:strlen(kSyntheticContextJSON)];
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
    HB_ASSERT_EQ_OBJ(payload[@"request"][@"context"][@"user_id"], @"u-42");

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

    // Stale format: a v2 file (no context section) must be rejected, not
    // misread as v3 with garbage context bytes.
    NSMutableData* wrongVersion = [synthetic_crash_data() mutableCopy];
    uint32_t two = 2;
    [wrongVersion replaceBytesInRange:NSMakeRange(4, 4) withBytes:&two];
    HB_ASSERT_NIL([hb payloadFromSignalCrashFileData:wrongVersion]);

    // Truncated: header claims context_length bytes but fewer follow.
    NSData* full = synthetic_crash_data();
    NSData* truncated = [full subdataWithRange:NSMakeRange(0, full.length - 1)];
    HB_ASSERT_NIL([hb payloadFromSignalCrashFileData:truncated]);

    // context_length (within the HB_MAX_CONTEXT_JSON cap) claims more bytes
    // than are actually present in the file — exercises the expectedLength
    // bounds check, not just the cap check.
    NSMutableData* overclaimed = [synthetic_crash_data() mutableCopy];
    int32_t overclaimedContextLength = 100;
    [overclaimed replaceBytesInRange:NSMakeRange(offsetof(HBSignalCrashHeader, context_length), sizeof(int32_t))
                           withBytes:&overclaimedContextLength];
    HB_ASSERT_NIL([hb payloadFromSignalCrashFileData:overclaimed]);

    HB_TEST_BEGIN("testReplayToleratesUnparseableContext");
    HBSignalCrashHeader header;
    memset(&header, 0, sizeof(header));
    header.magic = HB_SIGNAL_CRASH_MAGIC;
    header.version = HB_SIGNAL_CRASH_VERSION;
    header.signal_number = SIGSEGV;
    header.address_count = 0;
    header.image_count = 0;
    header.context_length = 4;
    NSMutableData* torn = [NSMutableData dataWithBytes:&header length:sizeof(header)];
    [torn appendBytes:"xxxx" length:4];  // invalid JSON
    NSDictionary* tornPayload = [hb payloadFromSignalCrashFileData:torn];
    HB_ASSERT_NOT_NIL(tornPayload);
    HB_ASSERT_EQ_OBJ(tornPayload[@"request"][@"context"], @{});

    HB_TEST_BEGIN("testReplayToleratesNonTerminatedImageName");
    // A corrupt record whose name field has no NUL terminator must not read
    // past the fixed-size field (the record is the last bytes of the file, so
    // an overrun would run off the end of the NSData).
    HBSignalCrashHeader nameHeader;
    memset(&nameHeader, 0, sizeof(nameHeader));
    nameHeader.magic = HB_SIGNAL_CRASH_MAGIC;
    nameHeader.version = HB_SIGNAL_CRASH_VERSION;
    nameHeader.signal_number = SIGSEGV;
    nameHeader.address_count = 1;
    nameHeader.addresses[0] = 0x3000000100;
    nameHeader.image_count = 1;
    HBBinaryImage unterminated;
    memset(&unterminated, 0, sizeof(unterminated));
    memset(unterminated.name, 'A', sizeof(unterminated.name));  // no NUL
    unterminated.load_address = 0x3000000000;
    NSMutableData* nameData = [NSMutableData dataWithBytes:&nameHeader length:sizeof(nameHeader)];
    [nameData appendBytes:&unterminated length:sizeof(unterminated)];
    NSDictionary* namePayload = [hb payloadFromSignalCrashFileData:nameData];
    HB_ASSERT_NOT_NIL(namePayload);
    NSString* imageName = namePayload[@"binary_images"][0][@"name"];
    HB_ASSERT_EQ_INT((int)imageName.length, (int)sizeof(unterminated.name));
    NSString* frameFile = namePayload[@"error"][@"backtrace"][0][@"file"];
    HB_ASSERT_EQ_INT((int)frameFile.length, (int)sizeof(unterminated.name));
}
