#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build >/dev/null
harness_dir="$PWD/.build/usage-ui"
harness_app="$harness_dir/SkillboxUsageUIHarness.app"
mkdir -p "$harness_app/Contents/MacOS" "$harness_app/Contents/Resources"
resource_accessor="$(find .build -path '*/debug/Skillbox.build/DerivedSources/resource_bundle_accessor.swift' -print -quit)"
xcrun swiftc -parse-as-library \
  Sources/Skillbox/Models/ProviderUsage.swift \
  Sources/Skillbox/Models/ProviderUsageStore.swift \
  Sources/Skillbox/Services/ProviderUsageService.swift \
  Sources/Skillbox/Services/ProviderUsageIdentity.swift \
  Sources/Skillbox/Services/ClaudeUsageCredentials.swift \
  Sources/Skillbox/Services/ClaudeCLIUsageReader.swift \
  Sources/Skillbox/Services/ClaudeBinaryLocator.swift \
  Sources/Skillbox/Services/GrokUsageCredentials.swift \
  Sources/Skillbox/Views/ProviderUsageLogo.swift \
  Sources/Skillbox/Views/TabHeaderView.swift \
  Sources/Skillbox/Views/UsageOverviewView.swift \
  Sources/Skillbox/Views/UsageSnapshotEditor.swift \
  Sources/Skillbox/Views/UsageSnapshotScene.swift \
  "$resource_accessor" Tests/UsageUIHarness/UsageUIHarness.swift \
  -o "$harness_app/Contents/MacOS/SkillboxUsageUIHarness"
cp -R .build/debug/Skillbox_Skillbox.bundle "$harness_app/Contents/Resources/"
cat > "$harness_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SkillboxUsageUIHarness</string>
<key>CFBundleIdentifier</key><string>ai.skillbox.usage-ui-harness</string>
<key>CFBundleName</key><string>SkillboxUsageUIHarness</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
xcrun swiftc scripts/native-ui-click.swift -o "$harness_dir/native-ui-click"
python3 scripts/test-usage-ui.py "$harness_app"
