#pragma once
#import "Honeybadger.h"
#include <signal.h>
#include <pthread.h>

extern volatile sig_atomic_t hb_exception_captured;
void hb_capture_exception(NSException* exception, NSString* handlerName);

extern int hb_signals[];
extern struct sigaction hb_previous_signal_actions[];
void hb_chain_previous_signal(int signal, siginfo_t* info, void* uap);

extern pid_t hb_hook_install_pid;
extern pthread_key_t hb_thread_alt_stack_key;
void hb_thread_introspection_hook(unsigned int event, pthread_t thread, void* addr, size_t size);
void hb_thread_alt_stack_destructor(void* stackMem);

extern char hb_context_json[];
extern volatile int hb_context_json_length;

extern volatile sig_atomic_t hb_handler_entered;
void hb_signal_handler(int signal, siginfo_t* info, void* uap);
int hb_interrupted_program_counter(void* uap, uint64_t* programCounter);
int hb_build_signal_addresses(void* uap,
                              void* const* unwoundAddresses,
                              int unwoundCount,
                              uint64_t* crashAddresses,
                              int crashCapacity,
                              int32_t* firstFrameIsReturnAddress);

// White-box access to SDK internals for tests. ObjC has no real privacy:
// these declarations let tests message the private methods on the shared
// singleton without changing the shipped header.
@interface Honeybadger (Testing)
+ (instancetype) sharedInstance;
- (NSString*) environment;
- (NSDictionary*) buildPayload:(NSDictionary*)data;
- (NSArray<NSDictionary*>*) framesFromCallStack:(NSDictionary*)data;
- (NSArray*) captureBinaryImages;
- (NSString*) crashReportDirectory;
- (NSString*) uniqueSignalReportPathInDirectory:(NSString*)dir;
- (NSDictionary*) payloadFromSignalCrashFileData:(NSData*)data;
- (void) installSignalHandlers;
- (void) refreshContextSnapshot;
- (NSMutableDictionary*) context;
- (NSString*) normalizedEndpointBase:(NSString*)endpoint;
- (NSString*) noticesURLWithEnvOverride:(NSString*)envOverride configuredEndpoint:(NSString*)configuredEndpoint;
@end
