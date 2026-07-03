#import "HBTest.h"

// One declaration + one call per suite. Later tasks append theirs here.
void run_smoke_tests(void);
void run_environment_tests(void);
void run_payload_tests(void);
void run_pending_report_tests(void);
void run_binary_image_tests(void);
void run_signal_replay_tests(void);
void run_exception_latch_tests(void);
void run_signal_install_tests(void);

int main(int argc, char** argv)
{
    @autoreleasepool {
        run_smoke_tests();
        run_environment_tests();
        run_payload_tests();
        run_pending_report_tests();
        run_binary_image_tests();
        run_signal_replay_tests();
        run_exception_latch_tests();
        run_signal_install_tests();
        return hb_test_summary();
    }
}
