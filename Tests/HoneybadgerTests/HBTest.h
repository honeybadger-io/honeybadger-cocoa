#pragma once
#import <Foundation/Foundation.h>

// Minimal ObjC test harness. XCTest is unavailable under Command Line Tools
// (no Xcode), so tests are a plain executable: each suite file defines
// run_<suite>_tests(), main.m calls each one, and the process exits nonzero
// if any assertion failed.

extern int hb_test_assertions;
extern int hb_test_failures;
extern const char* hb_test_current;

void hb_test_begin(const char* name);
int  hb_test_summary(void);
void hb_test_fail(const char* file, int line, const char* expr);

#define HB_TEST_BEGIN(name) hb_test_begin(name)

#define HB_ASSERT_TRUE(expr) do { \
    hb_test_assertions++; \
    if ( !(expr) ) { hb_test_fail(__FILE__, __LINE__, #expr); } \
} while (0)

#define HB_ASSERT_FALSE(expr)      HB_ASSERT_TRUE(!(expr))
#define HB_ASSERT_NIL(expr)        HB_ASSERT_TRUE((expr) == nil)
#define HB_ASSERT_NOT_NIL(expr)    HB_ASSERT_TRUE((expr) != nil)
#define HB_ASSERT_EQ_INT(a, b)     HB_ASSERT_TRUE((a) == (b))

#define HB_ASSERT_EQ_OBJ(a, b) do { \
    hb_test_assertions++; \
    id _hbA = (a); id _hbB = (b); \
    if ( !(_hbA == _hbB || [_hbA isEqual:_hbB]) ) { \
        hb_test_fail(__FILE__, __LINE__, \
            [[NSString stringWithFormat:@"%s == %s (got %@, want %@)", #a, #b, _hbA, _hbB] UTF8String]); \
    } \
} while (0)
