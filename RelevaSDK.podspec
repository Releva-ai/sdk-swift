Pod::Spec.new do |s|
  s.name             = 'RelevaSDK'
  s.version          = '1.0.0'
  s.summary          = 'Releva SDK for iOS - Push notifications and tracking'
  s.description      = <<-DESC
    Releva SDK provides easy integration with Releva's recommendation engine,
    push notifications, and user tracking capabilities for iOS apps.
    Features include cart management, wishlist tracking, product recommendations,
    and engagement analytics.
                       DESC

  s.homepage         = 'https://releva.ai'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Releva' => 'support@releva.ai' }
  s.source           = { :git => 'https://github.com/releva-ai/releva-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version = '5.7'

  s.source_files = 'Sources/RelevaSDK/**/*.swift'

  # Exclude Notification Extension from main target
  s.exclude_files = 'Sources/RelevaNotificationExtension/**/*.swift'

  # Frameworks
  s.frameworks = 'Foundation', 'UIKit', 'UserNotifications'

  # Dependencies
  s.dependency 'Firebase/Messaging', '~> 11.0'

  # Subspec for Notification Service Extension
  s.subspec 'NotificationExtension' do |ext|
    ext.source_files = 'Sources/RelevaNotificationExtension/**/*.swift'
    ext.frameworks = 'UserNotifications'
    ext.dependency 'Firebase/Messaging', '~> 11.0'
  end

  # Resource bundles (if needed for future features)
  # s.resource_bundles = {
  #   'RelevaSDK' => ['Sources/RelevaSDK/Resources/**/*.{png,json,xib}']
  # }

  # Compiler flags
  s.pod_target_xcconfig = {
    'SWIFT_VERSION' => '5.7',
    'ENABLE_BITCODE' => 'NO',
    'OTHER_SWIFT_FLAGS' => '-DCocoaPods'
  }

  # Documentation
  s.documentation_url = 'https://docs.releva.ai/ios-sdk'
end