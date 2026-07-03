#import "HBTest.h"
#import "HoneybadgerTestAccess.h"
#import "../../Sources/ObjC/HoneybadgerCrashTypes.h"
#include <mach-o/dyld.h>

extern void hb_refresh_binary_images(void);
extern HBBinaryImage hb_binary_images[HB_MAX_BINARY_IMAGES];
extern volatile int hb_binary_image_count;

void run_binary_image_tests(void)
{
    HB_TEST_BEGIN("testStaticTableMatchesDyld");
    hb_refresh_binary_images();
    HB_ASSERT_TRUE(hb_binary_image_count > 0);
    // First dyld image is the running executable; the table must record the
    // header address dyld reports for it, in this process.
    const struct mach_header* header = _dyld_get_image_header(0);
    HB_ASSERT_EQ_INT(hb_binary_images[0].load_address, (uint64_t)(uintptr_t)header);
    HB_ASSERT_TRUE(strlen(hb_binary_images[0].name) > 0);

    HB_TEST_BEGIN("testCaptureBinaryImagesReflectsStaticTable");
    NSArray* images = [[Honeybadger sharedInstance] captureBinaryImages];
    HB_ASSERT_EQ_INT((int)images.count, hb_binary_image_count);
    NSDictionary* first = images.firstObject;
    HB_ASSERT_TRUE([first[@"load_address"] hasPrefix:@"0x"]);
    // Every UUID present must be canonical 8-4-4-4-12 uppercase hex.
    NSRegularExpression* re = [NSRegularExpression regularExpressionWithPattern:
        @"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$" options:0 error:nil];
    for ( NSDictionary* img in images ) {
        NSString* uuid = img[@"uuid"];
        if ( uuid ) {
            HB_ASSERT_EQ_INT([re numberOfMatchesInString:uuid options:0 range:NSMakeRange(0, uuid.length)], 1);
        }
    }
}
