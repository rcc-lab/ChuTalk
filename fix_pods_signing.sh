#!/bin/bash

# Podsの署名設定を自動署名に変更
echo "Fixing Pods code signing settings..."

# Podfile.lockを確認
if [ -f "Podfile" ]; then
    # Podfileの末尾に署名設定を追加
    if ! grep -q "CODE_SIGN_IDENTITY" Podfile; then
        cat >> Podfile << 'PODFILE_END'

# Auto-signing for all pods
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['CODE_SIGN_IDENTITY'] = ''
      config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    end
  end
end
PODFILE_END
        echo "✅ Added auto-signing configuration to Podfile"
    else
        echo "⚠️ Podfile already has signing configuration"
    fi
else
    echo "❌ Podfile not found"
    exit 1
fi

echo "Done! Now run: pod install"
