Pod::Spec.new do |spec|
	spec.name = "Honeybadger"
  	spec.version = "0.0.1"
  	spec.summary = "Honeybadger.io for iOS"
  	spec.description = "This is the Honeybadger.io SDK for iOS."
  	spec.homepage = "https://honeybadger.io"
  	spec.license = { :type => "MIT", :file => "LICENSE" }
  	spec.author = { "Andrey Butov" => "andreybutov@antair.com" }
  	spec.platform = :ios, "13.0"
  	spec.source = { :git => "https://github.com/honeybadger-io/honeybadger-cocoa.git", :tag => spec.version.to_s }
	spec.default_subspecs = "Core"
	spec.subspec "Core" do |subspec|
		subspec.source_files = "Sources/ObjC/**/*.{h,m}"
	end
	spec.subspec "Swift" do |subspec|
		subspec.dependency "Honeybadger/Core"
		subspec.source_files = "Sources/Swift/**/*.swift"
	end
end
