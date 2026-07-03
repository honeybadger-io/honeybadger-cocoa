#pragma once
#import "Honeybadger.h"
#include <signal.h>

// White-box access to SDK internals for tests. ObjC has no real privacy:
// these declarations let tests message the private methods on the shared
// singleton without changing the shipped header.
@interface Honeybadger (Testing)
+ (instancetype) sharedInstance;
- (NSString*) environment;
- (NSDictionary*) buildPayload:(NSDictionary*)data;
- (NSArray*) captureBinaryImages;
- (NSString*) crashReportDirectory;
@end
