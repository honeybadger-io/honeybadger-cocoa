# Honeybadger for iOS, macOS, and visionOS

An SDK for integrating [Honeybadger](https://honeybadger.io) into your iOS, macOS, and visionOS apps. This SDK can be used in both Swift and Objective-C projects.

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

You can also configure Honeybadger to use an optional custom **environment** parameter.

#### Swift

```swift
Honeybadger.configure(
	apiKey:"{{PROJECT_API_KEY}}",
	environment:"Staging"
)
```

#### Objective-C
```objc
[Honeybadger 
	configureWithAPIKey:@"{{PROJECT_API_KEY}}"
	environment:@"Staging"
];
```

You can also supply an optional **revision** to track which release an error came from (e.g. a version string, build number, or git SHA). Use the same value when uploading dSYMs (see [dSYM Upload for Symbolication](#dsym-upload-for-symbolication)) so dSYMs and the errors they symbolicate are tagged with the same revision.

#### Swift

```swift
Honeybadger.configure(
	apiKey:"{{PROJECT_API_KEY}}",
	environment:"Staging",
	revision:"1.4.2"
)
```

#### Objective-C
```objc
[Honeybadger 
	configureWithAPIKey:@"{{PROJECT_API_KEY}}"
	environment:@"Staging"
	revision:@"1.4.2"
];
```


## Usage Examples
Errors and exceptions will be automatically handled by the Honeybadger library, but you can also use the following API to customize error handling in your application.

### notify
You can use the **notify** methods to manually send an error as a string or Error/NSError object. If available, the Honeybadger library will attempt to extract a stack trace and any relevant information that might be useful. You can provide an optional **context**, to include any relevant information about the error. You can also provide a custom class name for the notification, via the optional **errorClass** parameter, and a custom fingerprint for error grouping, via the optional **fingerprint** parameter.

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
	fingerprint: "my-custom-error-fingerprint"
);

Honeybadger.notify(
	errorString: "My error", 
	errorClass: "MyCustomErrorType"
	context: ["user_id" : "123abc"]
);

Honeybadger.notify(
	errorString: "My error", 
	errorClass: "MyCustomErrorType"
	fingerprint: "my-custom-error-fingerprint"
);

Honeybadger.notify(
	errorString: "My error", 
	context: ["user_id" : "123abc"]
	fingerprint: "my-custom-error-fingerprint"
);

Honeybadger.notify(
	errorString: "My error", 
	errorClass: "MyCustomErrorType"
	context: ["user_id" : "123abc"]
	fingerprint: "my-custom-error-fingerprint"
);

// ---

Honeybadger.notify(
	error: MyError("This is my custom error.")
);

Honeybadger.notify(
	error: MyError("This is my custom error.")
	errorClass: "MyCustomErrorType"
);

Honeybadger.notify(
	error: MyError("This is my custom error.")
	context: ["user_id" : "123abc"]
);

Honeybadger.notify(
	error: MyError("This is my custom error.")
	fingerprint: "my-custom-error-fingerprint"
);

Honeybadger.notify(
	error: MyError("This is my custom error.")
	errorClass: "MyCustomErrorType"
	context: ["user_id" : "123abc"]
);

Honeybadger.notify(
	error: MyError("This is my custom error.")
	errorClass: "MyCustomErrorType"
	fingerprint: "my-custom-error-fingerprint"
);

Honeybadger.notify(
	error: MyError("This is my custom error.")
	errorClass: "MyCustomErrorType"
	context: ["user_id" : "123abc"]
	fingerprint: "my-custom-error-fingerprint"
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
	fingerprint:@"my-custom-error-fingerprint"
];

[Honeybadger 
	notifyWithString:@"My error" 
	errorClass:@"MyCustomErrorType"
	context:@{ @"user_id" : @"123abc" }
];

[Honeybadger 
	notifyWithString:@"My error" 
	errorClass:@"MyCustomErrorType"
	fingerprint:@"my-custom-error-fingerprint"
];

[Honeybadger 
	notifyWithString:@"My error" 
	context:@{ @"user_id" : @"123abc" }
	fingerprint:@"my-custom-error-fingerprint"
];

[Honeybadger 
	notifyWithString:@"My error" 
	errorClass:@"MyCustomErrorType"
	context:@{ @"user_id" : @"123abc" }
	fingerprint:@"my-custom-error-fingerprint"
];

// ---

[Honeybadger notifyWithError:
	[[NSError alloc] initWithDomain:@"my.test.error" code:-1 userInfo: @{}]
];

[Honeybadger notifyWithError:
	[[NSError alloc] initWithDomain:@"my.test.error" code:-1 userInfo: @{}]
	errorClass:@"MyCustomErrorType"
];

[Honeybadger notifyWithError:
	[[NSError alloc] initWithDomain:@"my.test.error" code:-1 userInfo: @{}]
	context:@{ @"user_id" : @"123abc" }
];

[Honeybadger notifyWithError:
	[[NSError alloc] initWithDomain:@"my.test.error" code:-1 userInfo: @{}]
	fingerprint:@"my-custom-error-fingerprint"
];

[Honeybadger notifyWithError:
	[[NSError alloc] initWithDomain:@"my.test.error" code:-1 userInfo: @{}]
	errorClass:@"MyCustomErrorType"
	context:@{ @"user_id" : @"123abc" }
];

[Honeybadger notifyWithError:
	[[NSError alloc] initWithDomain:@"my.test.error" code:-1 userInfo: @{}]
	errorClass:@"MyCustomErrorType"
	fingerprint:@"my-custom-error-fingerprint"
];

[Honeybadger notifyWithError:
	[[NSError alloc] initWithDomain:@"my.test.error" code:-1 userInfo: @{}]
	context:@{ @"user_id" : @"123abc" }
	fingerprint:@"my-custom-error-fingerprint"
];

[Honeybadger notifyWithError:
	[[NSError alloc] initWithDomain:@"my.test.error" code:-1 userInfo: @{}]
	errorClass:@"MyCustomErrorType"
	context:@{ @"user_id" : @"123abc" }
	fingerprint:@"my-custom-error-fingerprint"
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
[Honeybadger resetContext];
```

## dSYM Upload for Symbolication

When Xcode builds your app for distribution, it strips debug symbols from the binary to reduce file size. These symbols are saved separately in a `.dSYM` bundle alongside your build. Without uploading these bundles to Honeybadger, crash reports will show raw memory addresses instead of the function names, file names, and line numbers you need to diagnose the crash.

Uploading dSYMs lets Honeybadger display fully symbolicated stack traces like:

```
triggerExceptionCrash()   ViewController.swift:42
AppDelegate.application   AppDelegate.swift:18
```

The upload is handled by `bin/upload-dsyms.sh`. It automatically reads
`DWARF_DSYM_FOLDER_PATH` (which Xcode sets during a build), so no extra
configuration is needed. Store your API key in an Xcode build setting or
environment variable rather than hardcoding it.

### Xcode Build Phase (Recommended)

Add the script as a Run Script build phase so dSYMs upload automatically whenever you archive a build:

1. In Xcode, select your app target and go to **Build Phases**.
2. Click **+** and select **New Run Script Phase**.
3. Drag the new phase **below** the existing "Copy dSYMs" phase.
4. Add the run script for your installation method (below).

**CocoaPods** — the script is installed with the pod, so reference it from `${PODS_ROOT}`:

```shell
bash "${PODS_ROOT}/Honeybadger/bin/upload-dsyms.sh" --api-key "${HB_API_KEY}"
```

**Swift Package Manager** — SPM does not install standalone scripts to a referenceable location. Download `bin/upload-dsyms.sh` from this repository, add it to your project (e.g. at `Scripts/upload-dsyms.sh`), and reference it:

```shell
bash "${SRCROOT}/Scripts/upload-dsyms.sh" --api-key "${HB_API_KEY}"
```

### Manual / CI Upload

To upload dSYMs manually or from a CI pipeline, run the script directly with an explicit path:

```shell
bash upload-dsyms.sh --api-key YOUR_API_KEY --dsym-path /path/to/dSYMs/
```

The script uploads all `.dSYM` bundles found in the specified directory.

### Revision (optional)

If you configure a **revision** in the SDK (the `revision:` parameter of `configure`), pass the **same value** to the upload script with `--revision` so the uploaded dSYMs and the errors they symbolicate share one revision:

```shell
bash upload-dsyms.sh --api-key YOUR_API_KEY --revision "1.4.2"
```

Revision is purely for release tracking — dSYM-to-crash matching is done by build UUID, so it works with or without a revision.

## License

The Honeybadger iOS/macOS SDK is MIT-licensed. See the **LICENSE** file in this repository for details.
