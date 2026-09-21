#!/bin/bash
set -euo pipefail
cd /Users/mehadehasan/DEV/IOS/CubeGuide/cubeguide
task_device=610EA507-710F-4AA6-943C-AF57C0035F07
task_original_size=$(xcrun simctl ui "$task_device" content_size)
task_original_appearance=$(xcrun simctl ui "$task_device" appearance)
printf '%s\n%s\n' "$task_original_size" "$task_original_appearance" > Artifacts/t07-completion-accessibility-measured/original-ui.txt
restore_ui() {
  xcrun simctl ui "$task_device" content_size "$task_original_size"
  xcrun simctl ui "$task_device" appearance "$task_original_appearance"
}
trap restore_ui EXIT
xcrun simctl ui "$task_device" content_size accessibility-extra-extra-extra-large
xcrun simctl ui "$task_device" appearance dark
xcrun simctl ui "$task_device" content_size > Artifacts/t07-completion-accessibility-measured/test-ui.txt
xcrun simctl ui "$task_device" appearance >> Artifacts/t07-completion-accessibility-measured/test-ui.txt
Scripts/run-logged.sh Artifacts/t07-completion-accessibility-measured/xcode.log xcodebuild test -project cubeguide.xcodeproj -scheme cubeguide -testPlan PR -destination "platform=iOS Simulator,id=$task_device" -derivedDataPath Artifacts/t07-completion-accessibility-measured/build -resultBundlePath Artifacts/t07-completion-accessibility-measured/tests.xcresult -only-testing:cubeguideUITests/ReduceMotionUITests/testSystemReduceMotionShowsStaticGuideWithoutAdvancingProgress CODE_SIGNING_ALLOWED=NO
