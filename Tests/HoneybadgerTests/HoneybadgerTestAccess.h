#pragma once
#import "Honeybadger.h"
#include <signal.h>

extern volatile sig_atomic_t hb_exception_captured;
void hb_capture_exception(NSException* exception, NSString* handlerName);

// White-box access to SDK internals for tests. ObjC has no real privacy:
// these declarations let tests message the private methods on the shared
// singleton without changing the shipped header.
@interface Honeybadger (Testing)
+ (instancetype) sharedInstance;
- (NSString*) environment;
- (NSDictionary*) buildPayload:(NSDictionary*)data;
- (NSArray*) captureBinaryImages;
- (NSString*) crashReportDirectory;
- (NSString*) uniqueSignalReportPathInDirectory:(NSString*)dir;
- (NSDictionary*) payloadFromSignalCrashFileData:(NSData*)data;
- (void) installSignalHandlers;
@property (atomic, copy) NSString* cachedHostname;
@end
