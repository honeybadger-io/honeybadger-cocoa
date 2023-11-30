# Honeybadger for iOS and MacOS

An SDK for integrating [Honeybadger](https://honeybadger.io) into your iOS and MacOS apps. This SDK can be used in both Swift and Objective-C projects.

## Installation

[![SwiftPM compatible](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://swift.org/package-manager)
[![CocoaPods compatible](https://img.shields.io/badge/CocoaPods-compatible-brightgreen.svg)](https://cocoapods.org/)

### CocoaPods

To install via CocoaPods, create/open your **Pods** file and add a pod entry for **'Honeybadger'**. Make sure **use_frameworks!** is specified.

```shell
use_frameworks!

target 'MyApp' do
	pod 'Honeybadger'
end
```

### Swift Package Manager

Open your app in Xcode, then go to **File** > **Swift Packages** > **Add Package Dependency**, and specify the Honeybadger Cocoa GitHub repo: **https://github.com/honeybadger-io/honeybadger-cocoa**

### Initialization

You will need your Honeybadger API key to initialize the Honeybadger library. You can log into your [Honeybadger](https://honeybadger.io) account to obtain your API key.

In your App Delegate, import the Honeybadger library:

#### Swift

```swift
import Honeybadger
```

#### Objective-C

```objc
@import Honeybadger;
```

In your `didFinishLaunchingWithOptions` method, add the following code to initialize Honeybadger:

#### Swift

```swift
Honeybadger.configure(apiKey:"{{PROJECT_API_KEY}}")
```

#### Objective-C
```objc
[Honeybadger configureWithAPIKey:@"{{PROJECT_API_KEY}}"];
```

You can also configure Honeybadger to use an optional custom **environment** parameter, as well as an optional custom **fingerprint** parameter, for error grouping.

#### Swift

```swift
Honeybadger.configure(
	apiKey:"{{PROJECT_API_KEY}}",
	environment: "Staging"
)

Honeybadger.configure(
	apiKey:"{{PROJECT_API_KEY}}",
	fingerprint: "my-custom-error-fingerprint"
)

Honeybadger.configure(
	apiKey:"{{PROJECT_API_KEY}}",
	environment: "Staging",
	fingerprint: "my-custom-error-fingerprint"
)
```

#### Objective-C
```objc
[Honeybadger 
	configureWithAPIKey:@"{{PROJECT_API_KEY}}"
	environment:@"Staging"
];

[Honeybadger 
	configureWithAPIKey:@"{{PROJECT_API_KEY}}"
	fingerprint:@"my-custom-error-fingerprint"
];

[Honeybadger 
	configureWithAPIKey:@"{{PROJECT_API_KEY}}"
	environment:@"Staging"
	fingerprint:@"my-custom-error-fingerprint"
];
```


## Usage Examples
Errors and exceptions will be automatically handled by the Honeybadger library, but you can also use the following API to customize error handling in your application.

### notify
You can use the **notify** methods to manually send an error as a string or Error/NSError object. If available, the Honeybadger library will attempt to extract a stack trace and any relevant information that might be useful. You can also optionally provide **context**, to include any relevant information about the error. You can also provide a custom class name for the notification, via the optional **errorClass** parameter.

#### Swift

```swift

Honeybadger.notify(
	errorString: "My error"
);

Honeybadger.notify(
	errorString: "My error"
	errorClass: "MyCustomErrorType"
);

Honeybadger.notify(
	errorString: "My error", 
	context: ["user_id" : "123abc"]
);

Honeybadger.notify(
	errorString: "My error", 
	errorClass: "MyCustomErrorType"
	context: ["user_id" : "123abc"]
);

Honeybadger.notify(
	error: MyError("This is my custom error.")
);

Honeybadger.notify(
	error: MyError("This is my custom error.")
	errorClass: "MyCustomErrorType"
);

Honeybadger.notify(
	error: MyError("This is my custom error."), 
	context: ["user_id" : "123abc"]
);

Honeybadger.notify(
	error: MyError("This is my custom error."), 
	errorClass: "MyCustomErrorType"
	context: ["user_id" : "123abc"]
);
```

#### Objective-C

```objc
[Honeybadger 
	notifyWithString:@"My error"
];

[Honeybadger 
	notifyWithString:@"My error" 
	errorClass:@"MyCustomErrorType"
];

[Honeybadger 
	notifyWithString:@"My error" 
	context:@{ @"user_id" : @"123abc" }
];

[Honeybadger 
	notifyWithString:@"My error" 
	errorClass:@"MyCustomErrorType"
	context:@{ @"user_id" : @"123abc" }
];

[Honeybadger notifyWithError:
	[[NSError alloc] initWithDomain:@"my.test.error" code:-1 userInfo: @{}]
];

[Honeybadger notifyWithError:
	[[NSError alloc] initWithDomain:@"my.test.error" code:-1 userInfo: @{}]
	errorClass:@"MyCustomErrorType"
];

[Honeybadger 
	notifyWithError:[[NSError alloc] initWithDomain:@"my.test.error" code:-1 userInfo: @{}]
	context:@{ @"user_id" : @"123abc" }
];

[Honeybadger 
	notifyWithError:[[NSError alloc] initWithDomain:@"my.test.error" code:-1 userInfo: @{}]
	errorClass:@"MyCustomErrorType"
	context:@{ @"user_id" : @"123abc" }
];
```

### setContext

If you have data that you would like to include whenever an error or an exception occurs, you can provide that data using the **setContext** method. You can call **setContext** as many times as needed. New context data will be merged with any previously-set context data.

#### Swift

```swift
Honeybadger.setContext(context: ["user_id" : "123abc"]);
```

#### Objective-C

```objc
[Honeybadger setContext:@{@"user_id" : @"123abc"}];
```

### resetContext

If you've used **setContext** to store data, you can use **resetContext** to clear that data.

#### Swift

```swift
Honeybadger.resetContext();
```

#### Objective-C

```objc
[Honeybadger setContext];
```

## License

The Honeybadger iOS/MacOS SDK is MIT-licensed. See the **LICENSE** file in this repository for details.
