// The test target compiles the SDK implementation directly instead of
// linking the Honeybadger library product: internals ship as `static`
// (see HB_PRIVATE in Honeybadger.m), and HB_TEST_BUILD — defined only for
// this target — gives them external linkage so test files can extern them.
#import "../../Sources/ObjC/Honeybadger.m"
