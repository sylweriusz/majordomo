import Darwin
import Foundation
import MajordomoCore

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) -> Int {
    if condition() {
        return 0
    }

    fputs("FAIL: \(message)\n", stderr)
    return 1
}

private func testTwoQuickEscapesRequestCancel() -> Int {
    var detector = DoubleEscapeDetector(maximumInterval: 0.45)
    var failures = 0

    failures += expect(detector.recordKey(isEscape: true, at: 10.00) == false, "first Escape should arm detector")
    failures += expect(detector.recordKey(isEscape: true, at: 10.30) == true, "second quick Escape should request cancel")
    return failures
}

private func testSlowEscapesDoNotRequestCancel() -> Int {
    var detector = DoubleEscapeDetector(maximumInterval: 0.45)
    var failures = 0

    failures += expect(detector.recordKey(isEscape: true, at: 10.00) == false, "first Escape should arm detector")
    failures += expect(detector.recordKey(isEscape: true, at: 10.60) == false, "slow second Escape should not request cancel")
    return failures
}

private func testNonEscapeResetsPendingEscape() -> Int {
    var detector = DoubleEscapeDetector(maximumInterval: 0.45)
    var failures = 0

    failures += expect(detector.recordKey(isEscape: true, at: 10.00) == false, "first Escape should arm detector")
    failures += expect(detector.recordKey(isEscape: false, at: 10.10) == false, "non-Escape should not request cancel")
    failures += expect(detector.recordKey(isEscape: true, at: 10.20) == false, "Escape after another key should be treated as first Escape")
    return failures
}

private func testDetectorResetsAfterCancel() -> Int {
    var detector = DoubleEscapeDetector(maximumInterval: 0.45)
    var failures = 0

    failures += expect(detector.recordKey(isEscape: true, at: 10.00) == false, "first Escape should arm detector")
    failures += expect(detector.recordKey(isEscape: true, at: 10.30) == true, "second quick Escape should request cancel")
    failures += expect(detector.recordKey(isEscape: true, at: 10.40) == false, "detector should reset after cancel")
    return failures
}

private func testSupportedAudioFileTypes() -> Int {
    var failures = 0

    failures += expect(SupportedAudioFile.isSupported(URL(fileURLWithPath: "/tmp/input.wav")), "WAV should be accepted")
    failures += expect(SupportedAudioFile.isSupported(URL(fileURLWithPath: "/tmp/input.WAVE")), "WAVE should be accepted case-insensitively")
    failures += expect(SupportedAudioFile.isSupported(URL(fileURLWithPath: "/tmp/input.mp3")), "MP3 should be accepted")
    failures += expect(!SupportedAudioFile.isSupported(URL(fileURLWithPath: "/tmp/input.txt")), "text files should be rejected")
    return failures
}

private func makeIsolatedDefaults(_ suiteName: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func testSettingsStoreDefaults() -> Int {
    let store = SettingsStore(defaults: makeIsolatedDefaults("majordomo.test.defaults"))
    var failures = 0

    failures += expect(store.dictationLanguage == "auto", "dictation language defaults to auto")
    failures += expect(store.indicatorEnabled == true, "indicator is enabled by default")
    failures += expect(store.transcriptionBackendRawValue == nil, "backend is unset by default")
    return failures
}

private func testSettingsStoreRoundTrip() -> Int {
    let store = SettingsStore(defaults: makeIsolatedDefaults("majordomo.test.roundtrip"))
    var failures = 0

    store.dictationLanguage = "pl"
    store.indicatorEnabled = false
    store.transcriptionBackendRawValue = "large-v3-turbo"

    failures += expect(store.dictationLanguage == "pl", "dictation language round-trips")
    failures += expect(store.indicatorEnabled == false, "indicator disabled round-trips")
    failures += expect(store.transcriptionBackendRawValue == "large-v3-turbo", "backend round-trips")
    return failures
}

private func testLegacyBackendMigrationCarriesValue() -> Int {
    let suite = "majordomo.test.migrate"
    let defaults = makeIsolatedDefaults(suite)
    defaults.set("large-v3", forKey: DefaultsKey.legacyWhisperModelProfile)
    let store = SettingsStore(defaults: defaults)
    var failures = 0

    store.migrateLegacyBackendKeyIfNeeded()

    failures += expect(store.transcriptionBackendRawValue == "large-v3", "legacy value is carried to the current key")
    failures += expect(defaults.string(forKey: DefaultsKey.legacyWhisperModelProfile) == nil, "legacy key is cleared after migration")
    return failures
}

private func testLegacyBackendMigrationDoesNotClobber() -> Int {
    let suite = "majordomo.test.migrate.noclobber"
    let defaults = makeIsolatedDefaults(suite)
    defaults.set("large-v3", forKey: DefaultsKey.legacyWhisperModelProfile)
    defaults.set("large-v3-turbo-q8_0", forKey: DefaultsKey.transcriptionBackend)
    let store = SettingsStore(defaults: defaults)
    var failures = 0

    store.migrateLegacyBackendKeyIfNeeded()

    failures += expect(store.transcriptionBackendRawValue == "large-v3-turbo-q8_0", "existing current value is preserved over legacy")
    return failures
}

private func testLegacyBackendMigrationNoOpWhenAbsent() -> Int {
    let store = SettingsStore(defaults: makeIsolatedDefaults("majordomo.test.migrate.absent"))
    var failures = 0

    store.migrateLegacyBackendKeyIfNeeded()

    failures += expect(store.transcriptionBackendRawValue == nil, "migration is a no-op when nothing is stored")
    return failures
}

let failureCount = testTwoQuickEscapesRequestCancel()
    + testSlowEscapesDoNotRequestCancel()
    + testNonEscapeResetsPendingEscape()
    + testDetectorResetsAfterCancel()
    + testSupportedAudioFileTypes()
    + testSettingsStoreDefaults()
    + testSettingsStoreRoundTrip()
    + testLegacyBackendMigrationCarriesValue()
    + testLegacyBackendMigrationDoesNotClobber()
    + testLegacyBackendMigrationNoOpWhenAbsent()

if failureCount == 0 {
    print("MajordomoCoreTestRunner: all tests passed")
    exit(0)
}

fputs("MajordomoCoreTestRunner: \(failureCount) failure(s)\n", stderr)
exit(1)
