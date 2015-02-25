Pod::Spec.new do |s|
  s.name         = "DropboxBrowser"
  s.version      = "0.1.0"
  s.summary      = "Dropbox Browser provides a simple and effective way to browse, view, and download files using the iOS Dropbox SDK. Follow the simple setup steps and in under ten minutes you'll have a working Dropbox File Browser in your app that lets users browse and download their Dropbox files and folders."
  s.homepage     = "https://github.com/EchoLiao"
  s.author       = { "Echo Liao" => "echoliao8@gmail.com" }
  s.source       = { :git => "https://github.com/EchoLiao/DropboxBrowser.git", :tag => s.version.to_s }
  s.platform     = :ios, '7.0'
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.requires_arc = true
  s.xcconfig     = { 'HEADER_SEARCH_PATHS' => "\"${PODS_ROOT}/Dropbox-iOS-SDK/dropbox-ios-1.3.13/DropboxSDK/Classes\"" } # FIXME: CocoaPods Bug
  s.source_files = '*.{h,m}'
  s.resources    = 'DropboxMedia.xcassets/**/*.png', '*.storyboard'
  s.dependency 'Dropbox-iOS-SDK', '~> 1.3.13'
end
