#pragma once


#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN


@interface Honeybadger : NSObject

- (id) init NS_UNAVAILABLE;

// CONFIG ------------------------------------------------------------------

+ (void) configureWithAPIKey:(NSString*)apiKey
NS_SWIFT_NAME(configure(apiKey:));

+ (void) configureWithAPIKey:(NSString*)apiKey environment:(NSString*)environment
NS_SWIFT_NAME(configure(apiKey:environment:));

// NOTIFY ------------------------------------------------------------------

+ (void) notifyWithString:(NSString*)errorString
NS_SWIFT_NAME(notify(errorString:));

+ (void) notifyWithString:(NSString*)errorString errorClass:(NSString*)errorClass
NS_SWIFT_NAME(notify(errorString:errorClass:));

+ (void) notifyWithString:(NSString*)errorString context:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(notify(errorString:context:));

+ (void) notifyWithString:(NSString*)errorString fingerprint:(NSString*)fingerprint
NS_SWIFT_NAME(notify(errorString:fingerprint:));

+ (void) notifyWithString:(NSString*)errorString errorClass:(NSString*)errorClass context:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(notify(errorString:errorClass:context:));

+ (void) notifyWithString:(NSString*)errorString errorClass:(NSString*)errorClass fingerprint:(NSString*)fingerprint
NS_SWIFT_NAME(notify(errorString:errorClass:fingerprint:));

+ (void) notifyWithString:(NSString*)errorString context:(NSDictionary<NSString*, NSString*>*)context fingerprint:(NSString*)fingerprint
NS_SWIFT_NAME(notify(errorString:context:fingerprint:));

+ (void) notifyWithString:(NSString*)errorString errorClass:(NSString*)errorClass context:(NSDictionary<NSString*, NSString*>*)context fingerprint:(NSString*)fingerprint
NS_SWIFT_NAME(notify(errorString:errorClass:context:fingerprint:));

// ---

+ (void) notifyWithError:(NSError*)error
NS_SWIFT_NAME(notify(error:));

+ (void) notifyWithError:(NSError*)error errorClass:(NSString*)errorClass
NS_SWIFT_NAME(notify(error:errorClass:));

+ (void) notifyWithError:(NSError*)error context:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(notify(error:context:));

+ (void) notifyWithError:(NSError*)error fingerprint:(NSString*)fingerprint
NS_SWIFT_NAME(notify(error:fingerprint:));

+ (void) notifyWithError:(NSError*)error errorClass:(NSString*)errorClass context:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(notify(error:errorClass:context:));

+ (void) notifyWithError:(NSError*)error errorClass:(NSString*)errorClass fingerprint:(NSString*)fingerprint
NS_SWIFT_NAME(notify(error:errorClass:fingerprint:));

+ (void) notifyWithError:(NSError*)error context:(NSDictionary<NSString*, NSString*>*)context fingerprint:(NSString*)fingerprint
NS_SWIFT_NAME(notify(error:context:fingerprint:));

+ (void) notifyWithError:(NSError*)error errorClass:(NSString*)errorClass context:(NSDictionary<NSString*, NSString*>*)context fingerprint:(NSString*)fingerprint
NS_SWIFT_NAME(notify(error:errorClass:context:fingerprint:));

// CONTEXT -----------------------------------------------------------------

+ (void) setContext:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(setContext(context:));

+ (void) resetContext:(NSDictionary<NSString*, NSString*>*)context
NS_SWIFT_NAME(resetContext(context:));

@end


NS_ASSUME_NONNULL_END
