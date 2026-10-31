#!/bin/bash
set -euo pipefail
unset XCODE_XCCONFIG_FILE
# The shared gate is deterministic and must never inspect the user's live database.
export MAC_ISLAND_LIVE_CURSOR_TEST=0
export PYTHONDONTWRITEBYTECODE=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
export BUILD_ROOT="${BUILD_ROOT:-$PROJECT_DIR/build}"
export BUILD_JOBS="${BUILD_JOBS:-2}"
XCCONFIG_PATH="$PROJECT_DIR/Config/SharedWorkspace.xcconfig"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
RESULT_BUNDLE_PATH="$BUILD_ROOT/TestResults/MacIslandProductTests-$(date +%Y%m%d-%H%M%S).xcresult"
mkdir -p "$BUILD_ROOT/TestResults" "$BUILD_ROOT/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/ModuleCache"
CURRENT_STEP="Setup"
write_gate_summary() {
    local result=$?
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        {
            echo "## Mac Island product gate"
            if [[ "$result" -eq 0 ]]; then
                echo "Passed: bridge, serial Prototype tests, Release build and product unit tests."
            else
                echo "Failed during: $CURRENT_STEP (exit $result). See the job log and numeric test summary."
            fi
            echo
            echo "Live client databases, installation and releases are outside this gate."
        } >> "$GITHUB_STEP_SUMMARY" || true
    fi
}
trap write_gate_summary EXIT
run_step() { CURRENT_STEP="$1"; shift; echo "=== $CURRENT_STEP ==="; "$@"; }
run_xcodebuild() {
    xcodebuild -quiet -jobs "$BUILD_JOBS" \
        -project "$PROJECT_DIR/PingIsland.xcodeproj" -scheme MacIsland \
        -destination "platform=macOS" -derivedDataPath "$DERIVED_DATA_PATH" \
        -clonedSourcePackagesDirPath "$BUILD_ROOT/SourcePackages" \
        -xcconfig "$XCCONFIG_PATH" CODE_SIGNING_ALLOWED=NO "$@"
}
PRODUCT_TESTS=(
    -only-testing:PingIslandTests/PublicationSecurityTests
    -only-testing:PingIslandTests/SoundThemeConfigurationTests/testSilentProductOmitsLegacyAudioResources
    -only-testing:PingIslandTests/JSONLInterruptWatcherTests
    -only-testing:PingIslandTests/HookInstallerTemporarySettingsTests
    -only-testing:PingIslandTests/AppTerminationCoordinatorTests
    -only-testing:PingIslandTests/AppLaunchConfigurationTests
    -only-testing:PingIslandTests/AppLanguageTests
    -only-testing:PingIslandTests/MacIslandOnboardingTests
    -only-testing:PingIslandTests/ScreenPrivacyTests
    -only-testing:PingIslandTests/MacIslandDocumentationTests
    -only-testing:PingIslandTests/MacIslandDiagnosticsReportTests
    -only-testing:PingIslandTests/AppSettingsPersistenceTests
    -only-testing:PingIslandTests/MacIslandProductPolicyTests
    -only-testing:PingIslandTests/MacIslandSessionSnapshotTests
    -only-testing:PingIslandTests/MacIslandConversationDetailTests
    -only-testing:PingIslandTests/MacIslandFixturePlayerTests
    -only-testing:PingIslandTests/CodexMonitorHealthTests
    -only-testing:PingIslandTests/CodexMonitorLifecycleTests
    -only-testing:PingIslandTests/CodexOwnedProcessShutdownTests
    -only-testing:PingIslandTests/CodexAppServerMonitorTests
    -only-testing:PingIslandTests/CodexExecutableResolverTests
    -only-testing:PingIslandTests/SessionMonitorStartupTests
    -only-testing:PingIslandTests/CodexAuxiliaryHookFilterTests
    -only-testing:PingIslandTests/CodexConversationMergeTests
    -only-testing:PingIslandTests/CodexHookPlaceholderTests
    -only-testing:PingIslandTests/CodexHookSessionTests
    -only-testing:PingIslandTests/CodexRolloutParserTests
    -only-testing:PingIslandTests/CodexUsageLoaderTests
    -only-testing:PingIslandTests/CursorConversationMonitorTests
    -only-testing:PingIslandTests/CursorUsageLoaderTests
    -only-testing:PingIslandTests/ClaudeUsageLoaderTests
    -only-testing:PingIslandTests/HookInstallerStatusLineTests
    -only-testing:PingIslandTests/OpenCodeIntegrationTests
    -only-testing:PingIslandTests/HermesIntegrationTests
    -only-testing:PingIslandTests/DSHIntegrationTests
    -only-testing:PingIslandTests/IntegrationBackupTests
    -only-testing:PingIslandTests/MacIslandObservedIntegrationTests
    -only-testing:PingIslandTests/ObservedSessionRecoveryTests
    -only-testing:PingIslandTests/PersonalAgentObservationTests
    -only-testing:PingIslandTests/PersonalAgentMonitorTests
    -only-testing:PingIslandTests/SessionContinuationTests
    -only-testing:PingIslandTests/SessionContinuationWindowTests
    -only-testing:PingIslandTests/NotchViewModelTests
    -only-testing:PingIslandTests/SessionStoreLivenessSweepTests
    -only-testing:PingIslandTests/SessionStateTests
    -only-testing:PingIslandTests/UsageSnapshotCacheStoreTests
    -only-testing:PingIslandTests/UsageSummaryPresenterTests
    -only-testing:PingIslandTests/VibeHookMigrationTests
    -only-testing:PingIslandTests/GlobalShortcutTests
    -only-testing:PingIslandTests/SessionActionControllerTests
    -only-testing:PingIslandTests/SessionQuickActionsTests
    -only-testing:PingIslandTests/SessionListKeyboardScopeTests
    -only-testing:PingIslandTests/RecentSessionIndexTests
    -only-testing:PingIslandTests/RecentSessionPresentationTests
    -only-testing:PingIslandTests/SessionListTitleStoreTests
    -only-testing:PingIslandTests/SessionLauncherNavigationTests
    -only-testing:PingIslandTests/TerminalSessionFocuserTests
    -only-testing:PingIslandTests/EnergyGovernorTests
    -only-testing:PingIslandTests/IslandExpandedRouteResolverTests
    -only-testing:PingIslandTests/DetachedIslandWindowControllerTests
    -only-testing:PingIslandTests/SettingsWindowControllerTests
)
cd "$PROJECT_DIR"
run_step "Source Quality and Pages Payload" python3 "$SCRIPT_DIR/check-quality.py"
run_step "Distribution Tool Fixture Tests" python3 "$SCRIPT_DIR/test_prepare_mac_island_release.py"
run_step "Build Test Bridge" swift build --jobs "$BUILD_JOBS" --package-path Prototype --scratch-path "$BUILD_ROOT/Prototype" --product PingIslandBridge
MAC_ISLAND_TEST_BIN_DIR="$(swift build --jobs "$BUILD_JOBS" --package-path Prototype --scratch-path "$BUILD_ROOT/Prototype" --show-bin-path)"
export MAC_ISLAND_TEST_BIN_DIR
# The prototype E2E fixtures use blocking socket/process I/O. Serial test scheduling
# keeps concurrent fixture listeners from exhausting small CI cooperative pools.
run_step "Prototype Tests" swift test --no-parallel --jobs "$BUILD_JOBS" --package-path Prototype --scratch-path "$BUILD_ROOT/Prototype"
run_step "Distribution Legal Sources" python3 "$SCRIPT_DIR/verify-distribution-legal.py"
run_step "Mac Island Release Build" run_xcodebuild -configuration Release build
run_step "Bundled Distribution Legal Resources" python3 "$SCRIPT_DIR/verify-distribution-legal.py" \
    --app "$DERIVED_DATA_PATH/Build/Products/Release/Mac Island.app" \
    --sparkle-license "$BUILD_ROOT/SourcePackages/artifacts/sparkle/Sparkle/LICENSE"
if run_step "Mac Island Product Unit Tests (${#PRODUCT_TESTS[@]} suites)" run_xcodebuild -configuration Debug -parallel-testing-enabled NO -resultBundlePath "$RESULT_BUNDLE_PATH" test "${PRODUCT_TESTS[@]}"; then
    :
else
    test_exit=$?
    # -quiet may omit assertion details. Keep failures readable in CI even when
    # an authenticated binary xcresult download is unavailable to a reviewer.
    xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE_PATH" || true
    exit "$test_exit"
fi
run_step "Mac Island Product Test Summary" xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE_PATH"
echo "Mac Island Product Gate Passed; results retained at $RESULT_BUNDLE_PATH"
