platform :ios, '10.0'

target 'ReactionCam' do
  use_frameworks!

  pod 'ActiveLabel'
  pod 'Alamofire'
  pod 'AlamofireImage'
  pod 'Crashlytics'
  pod 'DateTools'
  pod 'Fabric'
  pod 'FBSDKCoreKit'
  pod 'FBSDKLoginKit'
  pod 'FBSDKShareKit'
  pod 'FBSDKMessengerShareKit'
  pod 'Firebase/Core'
  pod 'GrowingTextView'
  pod 'iRate'
  pod 'OpenGraph'
  pod 'pop'
  pod 'SDAVAssetExportSession', :git => 'https://github.com/rs/SDAVAssetExportSession.git'
  pod 'Starscream'
  pod 'SwipeView'
  pod 'TagListView', '1.2.0'
  pod 'TMTumblrSDK/APIClient'
  pod 'TwitterKit'
  pod 'XLActionController'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    if ['TagListView'].include? target.name
      target.build_configurations.each do |config|
        config.build_settings['SWIFT_VERSION'] = '3.2'
      end
    end
  end
end
