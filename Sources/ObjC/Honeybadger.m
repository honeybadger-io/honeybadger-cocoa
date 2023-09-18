//
// Honeybadger iOS/MacOS
//



#import "Honeybadger.h"
#include <execinfo.h>
#import <mach-o/arch.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>

#if TARGET_OS_IOS
    #import <UIKit/UIKit.h>
#endif



#define HONEYBADGER_APPLE_SDK_VERSION   @"0.0.5"



@interface Honeybadger ()

@property (nonatomic) NSString* apiKey;
@property (nonatomic) BOOL initialized;
@property (nonatomic) NSMutableDictionary<NSString*, NSString*>* context;

@end



@implementation Honeybadger

// -- SINGLETON ---
static Honeybadger* sharedInstance = nil;
+ (Honeybadger*) sharedInstance { if ( sharedInstance == nil ) { sharedInstance = [[super allocWithZone:NULL] init]; } return sharedInstance; }
+ (id) allocWithZone:(NSZone*)zone { return [self sharedInstance]; }
- (id) copyWithZone:(NSZone*)zone { return self; }
// --


+ (void) configureWithAPIKey:(NSString*)apiKey
{
    Honeybadger* hb = [Honeybadger sharedInstance];
    if ( ![hb isSupportedPlatform] ) {
        NSLog(@"Error: The Honeybadger SDK does not currently support this platform.");
        return;
    }

    if ( ![hb isValidAPIKey:apiKey] ) {
        [hb informUserOfInvalidAPIKey];
        return;
    }
    
    hb.apiKey = [hb safeTrimmedStr:apiKey];
    [hb setExceptionHandler];
    hb.initialized = TRUE;
}


+ (void) notifyWithString:(NSString*)message
{
    Honeybadger* hb = [Honeybadger sharedInstance];
    
    if ( ![hb isValidAPIKey:hb.apiKey] ) {
        [hb informUserOfInvalidAPIKey];
        return;
    }
    
    message = [hb safeTrimmedStr:message];
    
    if ( message.length == 0 ) {
        NSLog(@"Error: Honeybadger notifyWithString - invalid message");
        return;
    }
    
    [hb processEvent:@{
        @"initialHandler" : @"notifyWithString",
        @"errorMsg" : message,
        @"onNotifyCallStackSymbols" : [hb stackTrace:1]
    }];
}


+ (void) notifyWithString:(NSString*)message context:(NSDictionary<NSString*, NSString*>*)context
{
    Honeybadger* hb = [Honeybadger sharedInstance];
    
    if ( ![hb isValidAPIKey:hb.apiKey] ) {
        [hb informUserOfInvalidAPIKey];
        return;
    }
    
    message = [hb safeTrimmedStr:message];
    
    if ( message.length == 0 ) {
        NSLog(@"Error: Honeybadger notifyWithString - invalid message");
        return;
    }
    
    NSMutableDictionary<NSString*, NSString*>* contextForThisError = [hb merge:hb.context with:(context ? context : @{})];

    [hb processEvent:@{
        @"initialHandler" : @"notifyWithString",
        @"errorMsg" : message,
        @"context" : contextForThisError,
        @"onNotifyCallStackSymbols" : [hb stackTrace:1]
    }];
}



+ (void) notifyWithError:(NSError*)error
{
    if ( !error ) return;
    
    Honeybadger* hb = [Honeybadger sharedInstance];
    
    if ( ![hb isValidAPIKey:hb.apiKey] ) {
        [hb informUserOfInvalidAPIKey];
        return;
    }
    
    [hb processEvent:@{
        @"type" : @"Error",
        @"initialHandler" : @"notifyWithError",
        @"userInfo" : error.userInfo ? error.userInfo : @{},
        @"errorDomain" : [hb safeTrimmedStr:error.domain],
        @"localizedDescription" : [hb safeTrimmedStr:error.localizedDescription],
        @"onNotifyCallStackSymbols" : [hb stackTrace:1]
    }];
}



+ (void) notifyWithError:(NSError*)error context:(NSDictionary<NSString*, NSString*>*)context
{
    if ( !error ) return;
    
    Honeybadger* hb = [Honeybadger sharedInstance];
    
    if ( ![hb isValidAPIKey:hb.apiKey] ) {
        [hb informUserOfInvalidAPIKey];
        return;
    }
    
    NSMutableDictionary<NSString*, NSString*>* contextForThisError = [hb merge:hb.context with:(context ? context : @{})];

    [hb processEvent:@{
        @"type" : @"Error",
        @"initialHandler" : @"notifyWithError",
        @"userInfo" : error.userInfo ? error.userInfo : @{},
        @"errorDomain" : [hb safeTrimmedStr:error.domain],
        @"localizedDescription" : [hb safeTrimmedStr:error.localizedDescription],
        @"context" : contextForThisError,
        @"onNotifyCallStackSymbols" : [hb stackTrace:1]
    }];
}



+ (void) setContext:(NSDictionary<NSString*, NSString*>*)context
{
    if ( context ) {
        Honeybadger* hb = [Honeybadger sharedInstance];
        hb.context = [hb merge:hb.context with:context];
    }
}



+ (void) resetContext:(NSDictionary<NSString*, NSString*>*)context
{
    [Honeybadger sharedInstance].context =
        [NSMutableDictionary dictionaryWithDictionary:(context ? context : @{})];
}



// ----------------------------------------------------------------------------



- (id) init
{
    self = [super init];
    
    if ( self )
    {
        _apiKey = @"";
        _initialized = FALSE;
        _context = [NSMutableDictionary dictionary];
    }
    
    return self;
}



- (BOOL) isValidAPIKey:(NSString*)apiKey
{
    return [self safeTrimmedStr:apiKey].length > 0;
}



- (void) informUserOfInvalidAPIKey
{
    NSLog(@"Error: Please initialize Honeybadger by calling configureWithAPIKey: with a valid Honeybadger.io API key.");
}



- (void) setExceptionHandler
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    
    [NSNotificationCenter.defaultCenter
        addObserver: self
        selector:@selector(onCFuncCaughtException:)
        name: @"notification-c-func-caught-exception"
        object: nil];
        
    NSSetUncaughtExceptionHandler(&c_func_on_exception);

    [NSNotificationCenter.defaultCenter
        addObserver:self
        selector:@selector(onCFuncCaughtSignal:)
        name:@"notification-c-func-caught-signal"
        object:nil];
}



- (void) onCFuncCaughtException:(NSNotification*)notification
{
    if ( !notification || !notification.userInfo ) {
        return;
    }
    
    NSException* e = notification.userInfo[@"exception"];
    
    if ( e )
    {
        [self processEvent:@{
            @"type" : @"Exception",
            @"name" : [self safe:e.name],
            @"reason" : [self safe:e.reason],
            @"userInfo" : e.userInfo ? e.userInfo : @{},
            @"callStackSymbols" : e.callStackSymbols ? e.callStackSymbols : @[],
            @"initialHandler" : [self stringValueForKey:@"initialHandler" fromDictionary:notification.userInfo defaultValue:@"onCFuncCaughtException"]
        }];
    }
}



- (void) onCFuncCaughtSignal:(NSNotification*)notification
{
    if ( notification && notification.userInfo ) {
        [self processEvent:@{
            @"type" : @"Signal",
            @"initialHandler" : [self stringValueForKey:@"initialHandler" fromDictionary:notification.userInfo defaultValue:@"onCFuncCaughtSignal"]
        }];
    }
}



void c_func_on_exception(NSException* e)
{
    if ( !e ) {
        return;
    }

    [NSNotificationCenter.defaultCenter
        postNotificationName:@"notification-c-func-caught-exception"
        object:nil
        userInfo:@{
            @"exception" : e,
            @"initialHandler" : @"c_func_on_exception"
        }
    ];
}


- (void) processEvent:(NSDictionary*)data
{
    NSDictionary* payloadData = @{
        @"errorClass" : [NSString stringWithFormat:@"%@ %@", [self platformName], [self stringValueForKey:@"type" fromDictionary:data defaultValue:@"Error"]],
        @"errorMsg" : [self errorMessageFromEventData:data],
        @"details" : @{
            @"errorDomain" : [self stringValueForKey:@"errorDomain" fromDictionary:data defaultValue:@""],
            @"initialHandler" : [self stringValueForKey:@"initialHandler" fromDictionary:data defaultValue:@""],
            @"userInfo" : data[@"userInfo"] ? data[@"userInfo"] : @{},
            @"architecture" : [NSString stringWithUTF8String:NXGetLocalArchInfo()->name]
        },
        @"context" : (data[@"context"] ? data[@"context"] : (_context ? _context : @{})),
        @"backTrace" : [self framesFromCallStack:data]
    };

    [self sendToHoneybadger:[self buildPayload:payloadData]];
}



- (NSArray<NSDictionary*>*) framesFromCallStack:(NSDictionary*)data
{
    NSArray<NSString*>* stackLines = @[];
    
    if ( data[@"onNotifyCallStackSymbols"] ) {
        stackLines = data[@"onNotifyCallStackSymbols"];
    }
    else if ( data[@"callStackSymbols"] ) {
        stackLines = data[@"callStackSymbols"];
    }
    else {
        NSString* localizedDescription = [self stringValueForKey:@"localizedDescription" fromDictionary:data defaultValue:@""];
        if ( localizedDescription.length > 0 ) {
            stackLines = [localizedDescription componentsSeparatedByString:@"\n"];
        }
    }

    NSMutableArray<NSDictionary*>* frames = [NSMutableArray array];

    for ( NSString* line in stackLines ) {
        [frames addObject:[self extractValuesFromStackFrame:line]];
    }
    
    return frames;
}



- (NSString*) errorMessageFromEventData:(NSDictionary*)data {
    if ( !data ) return @"";
    
    NSString* errorMsg = [self safeTrimmedStr:data[@"errorMsg"]];
    if ( errorMsg.length > 0 ) return errorMsg;
    
    NSString* localizedDescription = [self safeTrimmedStr:data[@"localizedDescription"]];
    if ( localizedDescription.length > 0 ) {
        NSUInteger startOfCallStackIndex = [localizedDescription rangeOfString:@"callstack: (\n"].location;
        if ( startOfCallStackIndex == NSNotFound ) {
            NSArray<NSString*>* lines = [localizedDescription componentsSeparatedByString:@"\n"];
            return lines.count == 0 ? localizedDescription : [self safeTrimmedStr:lines.firstObject];
        } else {
            return [self safeTrimmedStr:[localizedDescription substringToIndex:startOfCallStackIndex]];
        }
    }
    
    NSString* name = [self safeTrimmedStr:data[@"name"]];
    NSString* reason = [self safeTrimmedStr:data[@"reason"]];
    if ( name.length > 0 || reason.length > 0 ) {
        return [self safeTrimmedStr:[NSString stringWithFormat:@"%@ : %@", name, reason]];
    }
    
    return @"";
}


- (NSString*) safe:(NSString*)s
{
    return s != nil ? s : @"";
}



- (NSString*) safeTrimmedStr:(NSString*)str
{
    return [[self safe:str] stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}


- (NSString*) stringValueForKey:(NSString*)key fromDictionary:(NSDictionary*)dict defaultValue:(NSString*)defaultValue {
    if ( !dict ) return defaultValue;
    
    NSObject* obj = [dict objectForKey:key];
    if ( !obj ) return defaultValue;

    if ( [obj isKindOfClass:[NSString class]] ) return (NSString*)obj;
    if ( [obj isKindOfClass:[NSNumber class]] ) return [(NSNumber*)obj stringValue];

    return defaultValue;
}


- (NSMutableDictionary*) merge:(NSDictionary*)dict1 with:(NSDictionary*)dict2
{
    NSMutableDictionary* mergedDictionary = [NSMutableDictionary dictionary];
    
    if ( dict1 ) {
        [mergedDictionary addEntriesFromDictionary:dict1];
    }
    
    if ( dict2 ) {
        [mergedDictionary addEntriesFromDictionary:dict2];
    }
    
    return mergedDictionary;
}


- (NSDictionary*) buildPayload:(NSDictionary*)data
{
    NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:@{
        
        @"notifier" : @{
            @"name" : @"Honeybadger Cocoa Notifier",
            @"url" : @"https://github.com/honeybadger-io/honeybadger-cocoa",
            @"version" : HONEYBADGER_APPLE_SDK_VERSION
        },

        @"error" : @{
            @"class" : [self stringValueForKey:@"errorClass" fromDictionary:data defaultValue:@"iOS Error"],
            @"message" : [self stringValueForKey:@"errorMsg" fromDictionary:data defaultValue:@"Unknown Error"],
            @"backtrace" : data[@"backTrace"] ? data[@"backTrace"] : @{}
        },
        
        @"request" : @{
            @"context" : data[@"context"] ? data[@"context"] : @{}
        },

        @"server" : @{
            @"environment_name" : [self environment]
        }
    
    }];
    
    NSString* details = [self stringValueForKey:@"details" fromDictionary:data defaultValue:@""];
    if ( details.length > 0 ) {
        payload[@"details"] = @{
            @"iOS" : details
        };
    }

    return payload;
}


- (void) sendToHoneybadger:(NSDictionary*)payload {
    if ( !payload || ![self isValidAPIKey:_apiKey] ) {
        return;
    }
    
    // NSLog(@"SENDING: %@", payload);
    
    NSData* dataToSend = [self toNSData:payload];
    if ( !dataToSend ) {
        return;
    }

    NSString* url = @"https://api.honeybadger.io/v1/notices/js";
    // url = @"https://7430698f8d32.ngrok.io";
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"text/json, application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:_apiKey forHTTPHeaderField:@"X-API-Key"];
    [request setValue:[self buildUserAgent] forHTTPHeaderField:@"User-Agent"];
    [request setHTTPBody:dataToSend];
    
    NSURLSession* session = [NSURLSession sharedSession];
    NSURLSessionDataTask* task = [session dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
        if ( error ) {
            NSLog(@"Error: %@", error);
        } else {
            NSLog(@"Honeybadger successful post: %@", response);
        }
    }];

    [task resume];
}


- (NSString*) buildUserAgent
{
    NSString* clientName = @"Honeybadger Cocoa";
    NSString* clientVersion = HONEYBADGER_APPLE_SDK_VERSION;
    NSString* platformName = [self platformName];
    NSString* platformVersion = [self platformVersion];
    
    return [NSString stringWithFormat:@"%@ %@; %@; %@",
        clientName, clientVersion, platformVersion, platformName];
}



- (NSString*) platformName
{
#if TARGET_OS_IOS
    return [[UIDevice currentDevice] systemName];
#elif TARGET_OS_OSX
    return [[NSHost currentHost] name];
#else
    NSLog(@"Error: unsupported platform.");
    return @"";
#endif
}



- (NSString*) platformVersion
{
#if TARGET_OS_IOS
    return [[UIDevice currentDevice] systemVersion];
#elif TARGET_OS_OSX
    return [[NSProcessInfo processInfo] operatingSystemVersionString];
#else
    NSLog(@"Error: unsupported platform.");
    return @"";
#endif
}



- (NSString*) environment
{
#if TARGET_OS_SIMULATOR
    return @"simulator";
#elif DEBUG
    return @"development";
#else
    return @"production";
#endif
}



- (NSData*) toNSData:(NSDictionary*)dict
{
    @try
    {
        NSData* jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
        if (!jsonData) return nil;
        // NSJSONSerializes automatically escapes forward slashes; we revert this behavior:
        NSString* jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        NSString* cleanJSONStr = [jsonStr stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
        // Now back to data
        return [cleanJSONStr dataUsingEncoding:NSUTF8StringEncoding];
    }
    @catch (NSException* exception)
    {
        NSLog(@"HB Error: %@", exception);
        return nil;
    }
}



- (BOOL) isSupportedPlatform
{
#if (TARGET_OS_IOS || TARGET_OS_OSX)
    return TRUE;
#endif
    return FALSE;
}



- (NSArray<NSString*>*) stackTrace:(NSUInteger)numTopFramesToRemove {
    numTopFramesToRemove++; // including the call to this method
    NSMutableArray<NSString*>* frames = [NSMutableArray array];
    for ( NSString* frame in [NSThread callStackSymbols] ) {
        if ( numTopFramesToRemove > 0 ) {
            numTopFramesToRemove--;
            continue;
        }
        [frames addObject:frame];
    }
    return frames;
}



- (NSDictionary*) extractValuesFromStackFrame:(NSString*)line
{
    NSMutableDictionary* values = [NSMutableDictionary dictionaryWithDictionary:@{
        @"file" : @"",
        @"line" : @"",
        @"method" : @"",
        @"stack_address" : @""
    }];
    
    if ( !line ) {
        return values;
    }
    
    line = [self safeTrimmedStr:line];
    
    if ( line.length == 0 ) {
        return values;
    }
    
    // \d+\s+(?<moduleName>\S+)\s+(?<stackAddress>\S+)\s(?<loadAddress>.+)\s\+\s(?<symbolOffset>\d+)(\s+\((?<file>\S+):(?<line>\S+)\))?
    NSString* pattern = @"\\d+\\s+(?<moduleName>\\S+)\\s+(?<stackAddress>\\S+)\\s(?<loadAddress>.+)\\s\\+\\s(?<symbolOffset>\\d+)";
    
    NSError* error = nil;
    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
    if ( error ) {
        NSLog(@"HB Error: %@", error);
        return values;
    }
    
    NSArray* matches = [regex matchesInString:line options:0 range:NSMakeRange(0, line.length)];
    for ( NSTextCheckingResult* match in matches ) {
        NSString* moduleName = [line substringWithRange:[match rangeWithName:@"moduleName"]];
        NSString* stackAdress = [line substringWithRange:[match rangeWithName:@"stackAddress"]];
        NSString* loadAddress = [line substringWithRange:[match rangeWithName:@"loadAddress"]];
        // NSString* symbolOffset = [line substringWithRange:[match rangeWithName:@"symbolOffset"]];
        
        values[@"file"] = moduleName ? moduleName : @"";
        values[@"method"] = loadAddress ? loadAddress : @"";
        values[@"stack_address"] = stackAdress ? stackAdress : @"";
    }
    
    return values;
}

@end
