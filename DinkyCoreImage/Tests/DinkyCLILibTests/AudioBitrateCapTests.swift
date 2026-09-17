@testable import DinkyCoreAudio
import XCTest

/// Expected ceilings come from the AAC encoder itself (`kAudioConverterApplicableEncodeBitRates`),
/// not from a hand-written table — the previous table allowed values the encoder rejects with
/// `'!dat'` (22.05 kHz mono was capped at 96k when the real ceiling is 64k).
final class AudioBitrateCapTests: XCTestCase {

    private func probe(rate: Double, channels: UInt32) -> AudioCompressor.SourceProbe {
        AudioCompressor.SourceProbe(sampleRate: rate, channelCount: channels, formatID: 0)
    }

    func testUnknownSampleRatePassesThrough() {
        let r = AudioCompressor.cappedAACBitrate(target: 128_000, probe: probe(rate: 0, channels: 0))
        XCTAssertEqual(r, 128_000)
    }

    func test8kHzMonoCappedAt24k() {
        let r = AudioCompressor.cappedAACBitrate(target: 256_000, probe: probe(rate: 8_000, channels: 1))
        XCTAssertEqual(r, 24_000)
    }

    func test8kHzStereoCappedAt48k() {
        let r = AudioCompressor.cappedAACBitrate(target: 256_000, probe: probe(rate: 8_000, channels: 2))
        XCTAssertEqual(r, 48_000)
    }

    func test16kHzMonoCappedAt48k() {
        let r = AudioCompressor.cappedAACBitrate(target: 96_000, probe: probe(rate: 16_000, channels: 1))
        XCTAssertEqual(r, 48_000)
    }

    /// The exact case reported in #13: a 22.05 kHz mono voice recording.
    func test22kHzMonoCappedAt64k() {
        let r = AudioCompressor.cappedAACBitrate(target: 128_000, probe: probe(rate: 22_050, channels: 1))
        XCTAssertEqual(r, 64_000)
    }

    func test44_1kHzStereoArchivalUnchanged() {
        let r = AudioCompressor.cappedAACBitrate(target: 256_000, probe: probe(rate: 44_100, channels: 2))
        XCTAssertEqual(r, 256_000)
    }

    func test48kHzStereoBalancedUnchanged() {
        let r = AudioCompressor.cappedAACBitrate(target: 128_000, probe: probe(rate: 48_000, channels: 2))
        XCTAssertEqual(r, 128_000)
    }

    func testTargetBelowCapIsRespected() {
        let r = AudioCompressor.cappedAACBitrate(target: 16_000, probe: probe(rate: 8_000, channels: 1))
        XCTAssertEqual(r, 16_000)
    }

    /// Whatever ceiling we hand to afconvert has to actually be encodable.
    func testCeilingIsAcceptedByTheEncoder() throws {
        for (rate, channels) in [(8_000.0, UInt32(1)), (16_000.0, UInt32(1)), (22_050.0, UInt32(1)), (44_100.0, UInt32(2))] {
            let ceiling = try XCTUnwrap(AudioCompressor.maxApplicableAACBitrate(sampleRate: rate, channels: channels))
            XCTAssertGreaterThan(ceiling, 0, "no ceiling for \(rate)Hz/\(channels)ch")
        }
    }
}
