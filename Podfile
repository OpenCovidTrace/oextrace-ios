platform :ios, '11.0'

# ignore all warnings from all pods
inhibit_all_warnings!

def pods
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for oextrace
  pod 'Alamofire'
  pod 'AlamofireNetworkActivityIndicator'
  pod 'CryptoSwift'
  pod 'Firebase/Analytics'
  pod 'Firebase/Crashlytics'
  pod 'SwiftLint'
  pod 'R.swift'
end

target 'oextrace DEV' do
    pods
end

target 'oextrace PROD' do
    pods
end

