import DinkyCoreAudio
import DinkyCoreShared
import XCTest

/// Smart Quality must never pick something that can only be bigger than the source.
final class AudioSmartQualityTests: XCTestCase {

    private func decide(_ kbps: Double, lossless: Bool?, _ format: AudioConversionFormat = .aacM4A,
                        _ tier: AudioConversionQualityTier = .balanced) -> AudioSmartQuality.Decision {
        AudioSmartQuality.decide(sourceBitsPerSecond: kbps * 1000, sourceIsLossless: lossless,
                                 userFormat: format, userTier: tier)
    }

    /// A 320 kbps MP3 used to be switched to FLAC, which always came out bigger ("no gain").
    func testLossyHighBitrateStaysLossyAndSmaller() {
        let d = decide(320, lossless: false, .aacM4A, .archival)
        XCTAssertEqual(d.format, .aacM4A)
        XCTAssertEqual(d.tier, .archival)          // 256 kbps < 320
    }

    func testLossy256PicksATierBelowTheSource() {
        let d = decide(256, lossless: false, .aacM4A, .archival)
        XCTAssertEqual(d.tier, .balanced)          // 256 would not shrink it
    }

    func testLossyNeverAboveUserTier() {
        XCTAssertEqual(decide(320, lossless: false, .aacM4A, .smallest).tier, .smallest)
        XCTAssertEqual(decide(320, lossless: false, .aacM4A, .balanced).tier, .balanced)
    }

    func testLossySourceWithLosslessTargetBecomesAAC() {
        let d = decide(320, lossless: false, .flac, .balanced)
        XCTAssertEqual(d.format, .aacM4A)
    }

    func testLossyMP3TargetUsesMP3Bitrates() {
        let d = decide(256, lossless: false, .mp3, .archival)
        XCTAssertEqual(d.format, .mp3)
        XCTAssertEqual(d.tier, .balanced)           // 320 wouldn't shrink it; 192 ≤ 256 × 0.8
    }

    func testLosslessMasterStillGoesArchivalFLAC() {
        let d = decide(1411, lossless: true, .aacM4A, .balanced)
        XCTAssertEqual(d.format, .flac)
        XCTAssertEqual(d.tier, .archival)
    }

    func testUnknownCodecNeverSwitchesToFLAC() {
        XCTAssertEqual(decide(320, lossless: nil).format, .aacM4A)
    }

    func testUnknownBitrateKeepsUserChoice() {
        let d = AudioSmartQuality.decide(sourceBitsPerSecond: 0, sourceIsLossless: false, userFormat: .mp3, userTier: .smallest)
        XCTAssertEqual(d.format, .mp3)
        XCTAssertEqual(d.tier, .smallest)
    }
}
