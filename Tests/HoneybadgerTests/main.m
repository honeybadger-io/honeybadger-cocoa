#import "HBTest.h"

// One declaration + one call per suite. Later tasks append theirs here.
void run_smoke_tests(void);

int main(int argc, char** argv)
{
    @autoreleasepool {
        run_smoke_tests();
        return hb_test_summary();
    }
}
