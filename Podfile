platform :ios, '15.0'
use_frameworks!
inhibit_all_warnings!

target 'ChuTalk' do
  pod 'GoogleWebRTC'                       # WebRTC（公式Pod）
  pod 'Socket.IO-Client-Swift', '~> 16.1' # Socket.IO
  pod 'KeychainSwift', '~> 24.0'          # Keychain

  post_install do |installer|
    installer.pods_project.targets.each do |t|
      t.build_configurations.each do |config|
        config.build_settings['ENABLE_BITCODE'] = 'NO'
        config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
        config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
        # Exclude x86_64 for simulator (WebRTC only supports ARM64)
        config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'x86_64'
      end
    end

    # Disable sandboxing for the main project
    installer.generated_projects.each do |project|
      project.targets.each do |target|
        target.build_configurations.each do |config|
          config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
          # Exclude x86_64 for simulator
          config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'x86_64'
        end
      end
    end
  end
end
