#import "HBTest.h"

int hb_test_assertions = 0;
int hb_test_failures = 0;
const char* hb_test_current = "";

void hb_test_begin(const char* name) {
    hb_test_current = name;
    printf("TEST %s\n", name);
}

void hb_test_fail(const char* file, int line, const char* expr) {
    hb_test_failures++;
    printf("FAIL %s %s:%d (%s)\n", hb_test_current, file, line, expr);
}

int hb_test_summary(void) {
    printf("%d assertions, %d failures\n", hb_test_assertions, hb_test_failures);
    return hb_test_failures == 0 ? 0 : 1;
}
