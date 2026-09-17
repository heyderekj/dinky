import AVFoundation
import AudioToolbox
import CoreMedia
import DinkyCoreShared
import Foundation
import os

public enum AudioCompressionError: LocalizedError, Sendable {
    case noAudioTrack
    case lameExecutableRequired
    case afconvertFailed(String)
    case unsupportedSourceCodec(fourCC: String)
    case unreadableSource

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return String(localized: "No audio track was found in this file.",
                          comment: "Audio compression error.")
        case .lameExecutableRequired:
            return String(localized: "The LAME encoder is required for MP3 export but wasn’t found in the bundle.",
                          comment: "Audio compression error.")
        case .afconvertFailed(let m): return m
        case .unsupportedSourceCodec(let cc):
            return String(localized: "This audio file uses a codec (\(cc)) that macOS can’t decode. Try converting it with another tool first.",
                          comment: "Audio import error for AMR/3GP and other codecs Apple doesn’t support.")
        case .unreadableSource:
            return String(localized: "Couldn’t read audio data from this file. It may be corrupt or use an unsupported codec.",
                          comment: "Audio import error when AVFoundation can’t open the asset.")
        }
    }
}

public enum AudioCompressor: Sendable {

    private static let log = Logger(subsystem: "dinky", category: "AudioCompressor")

    public struct Resolved: Sendable {
        public let durationSeconds: Double?
        public let format: AudioConversionFormat

        public init(durationSeconds: Double?, format: AudioConversionFormat) {
            self.durationSeconds = durationSeconds
            self.format = format
        }
    }

    public static func makeURLAsset(url: URL) -> AVURLAsset {
        let options: [String: Any] = [
            "AVURLAssetUsesNoPersistentCacheKey": true,
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
        ]
        return AVURLAsset(url: url, options: options)
    }

    /// Cross-converts using `/usr/bin/afconvert` and bundled `lame` (MP3 encode only).
    public static func convert(
        source: URL,
        targetFormat: AudioConversionFormat,
        qualityTier: AudioConversionQualityTier,
        lameExecutable: URL?,
        outputURL: URL,
        progressHandler: (@Sendable (Float) -> Void)? = nil
    ) async throws -> Resolved {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer { CompressionTiming.logPhase("audio.convert", startedAt: t0) }

        let asset = makeURLAsset(url: source)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let firstTrack = audioTracks.first else {
            throw AudioCompressionError.noAudioTrack
        }

        let probe = await Self.probe(firstTrack)
        if unsupportedSourceFormatIDs.contains(probe.formatID) {
            throw AudioCompressionError.unsupportedSourceCodec(fourCC: fourCCString(probe.formatID))
        }

        let durationSeconds: Double?
        do {
            let d = try await asset.load(.duration)
            let s = CMTimeGetSeconds(d)
            durationSeconds = s.isFinite && s > 0 ? s : nil
        } catch {
            durationSeconds = nil
        }

        progressHandler?(0)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if targetFormat == .mp3 {
            guard let lame = lameExecutable else {
                throw AudioCompressionError.lameExecutableRequired
            }
            let tempWav = FileManager.default.temporaryDirectory
                .appendingPathComponent("dinky_audio_\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: tempWav) }

            do {
                try await AFConvertRunner.convert(
                    from: source,
                    to: tempWav,
                    arguments: ["-f", "WAVE", "-d", "LEI16"]
                )
                progressHandler?(0.45)
                try await LameRunner.encodeMP3(
                    fromWAV: tempWav,
                    to: outputURL,
                    bitrateKbps: qualityTier.lameCBRBitrateKbps,
                    lameBinary: lame
                )
            } catch let e as AFConvertError {
                throw Self.mapAFConvertError(e)
            } catch let e as LameRunnerError {
                switch e {
                case .lameMissing:
                    throw AudioCompressionError.lameExecutableRequired
                case .processFailed(_, let stderr):
                    throw AudioCompressionError.afconvertFailed(friendlyAFConvertMessage(for: stderr))
                }
            }
        } else {
            let args = afconvertArguments(for: targetFormat, qualityTier: qualityTier, probe: probe)
            do {
                try await AFConvertRunner.convert(from: source, to: outputURL, arguments: args)
            } catch let e as AFConvertError {
                throw Self.mapAFConvertError(e)
            }
        }

        progressHandler?(1)
        return Resolved(durationSeconds: durationSeconds, format: targetFormat)
    }

    // MARK: - Source probing

    struct SourceProbe: Sendable {
        let sampleRate: Double      // 0 if unknown
        let channelCount: UInt32    // 0 if unknown
        let formatID: AudioFormatID // 0 if unknown
    }

    private static let unsupportedSourceFormatIDs: Set<AudioFormatID> = [
        kAudioFormatAMR, kAudioFormatAMR_WB,
    ]

    private static func probe(_ track: AVAssetTrack) async -> SourceProbe {
        guard let descs = try? await track.load(.formatDescriptions) else {
            return SourceProbe(sampleRate: 0, channelCount: 0, formatID: 0)
        }
        guard let fd = descs.first,
              CMFormatDescriptionGetMediaType(fd) == kCMMediaType_Audio,
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(fd)
        else {
            return SourceProbe(sampleRate: 0, channelCount: 0, formatID: 0)
        }
        let asbd = asbdPtr.pointee
        return SourceProbe(
            sampleRate: asbd.mSampleRate,
            channelCount: asbd.mChannelsPerFrame,
            formatID: asbd.mFormatID
        )
    }

    private static func fourCCString(_ id: AudioFormatID) -> String {
        let bytes: [UInt8] = [
            UInt8((id >> 24) & 0xFF),
            UInt8((id >> 16) & 0xFF),
            UInt8((id >> 8) & 0xFF),
            UInt8(id & 0xFF),
        ]
        if let s = String(bytes: bytes, encoding: .ascii),
           s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }),
           !s.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(format: "0x%08X", id)
    }

    // MARK: - afconvert arg building

    private static func afconvertArguments(
        for format: AudioConversionFormat,
        qualityTier: AudioConversionQualityTier,
        probe: SourceProbe
    ) -> [String] {
        switch format {
        case .aacM4A:
            let cappedBps = cappedAACBitrate(target: qualityTier.aacTotalBitrateBps, probe: probe)
            return ["-f", "m4af", "-d", "aac", "-b", "\(cappedBps)"]
        case .alacM4A:
            return ["-f", "m4af", "-d", "alac"]
        case .flac:
            return ["-f", "flac", "-d", "flac"]
        case .wav:
            return ["-f", "WAVE", "-d", "LEI16"]
        case .aiff:
            return ["-f", "AIFF", "-d", "BEI16"]
        case .mp3:
            preconditionFailure("MP3 handled via LAME")
        }
    }

    /// AAC-LC bitrate ceiling per source sample rate (mono); stereo doubles the cap.
    /// Prevents `kAudioConverterErr_PropertyNotSupported` (`'!dat'`) when afconvert rejects
    /// `-b` for low-sample-rate sources (e.g. 8 kHz mono voice memos).
    /// The AAC encoder refuses bitrates above a ceiling that depends on the source sample rate and
    /// channel count, failing with `'!dat'` rather than degrading. Ask the encoder what it will
    /// accept instead of guessing — a hard-coded table gets this wrong (22.05 kHz mono tops out at
    /// 64 kbps, not 96). afconvert snaps values in between, so only the ceiling matters.
    static func cappedAACBitrate(target: Int, probe: SourceProbe) -> Int {
        guard let ceiling = maxApplicableAACBitrate(sampleRate: probe.sampleRate, channels: probe.channelCount) else {
            return target
        }
        return min(target, ceiling)
    }

    static func maxApplicableAACBitrate(sampleRate: Double, channels: UInt32) -> Int? {
        guard sampleRate > 0, channels > 0 else { return nil }
        var sourceFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2 * channels,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2 * channels,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var destinationFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        var converter: AudioConverterRef?
        guard AudioConverterNew(&sourceFormat, &destinationFormat, &converter) == noErr,
              let converter else { return nil }
        defer { AudioConverterDispose(converter) }

        var size: UInt32 = 0
        guard AudioConverterGetPropertyInfo(converter, kAudioConverterApplicableEncodeBitRates, &size, nil) == noErr,
              size > 0 else { return nil }
        var ranges = [AudioValueRange](
            repeating: AudioValueRange(),
            count: Int(size) / MemoryLayout<AudioValueRange>.size
        )
        guard AudioConverterGetProperty(converter, kAudioConverterApplicableEncodeBitRates, &size, &ranges) == noErr
        else { return nil }

        // The array is over-allocated and tail-padded with zeroes; the real ceiling is the largest.
        let ceiling = ranges.map { Int($0.mMaximum) }.max() ?? 0
        return ceiling > 0 ? ceiling : nil
    }

    // MARK: - Error mapping

    private static func mapAFConvertError(_ e: AFConvertError) -> AudioCompressionError {
        switch e {
        case .afconvertMissing:
            return .afconvertFailed(String(
                localized: "Apple’s audio converter isn’t available on this system.",
                comment: "Audio conversion error when /usr/bin/afconvert is missing."
            ))
        case .outputMissing:
            return .afconvertFailed(String(
                localized: "The audio converter didn’t produce an output file.",
                comment: "Audio conversion error when afconvert exits 0 but writes nothing."
            ))
        case .processFailed(_, let stderr):
            return .afconvertFailed(friendlyAFConvertMessage(for: stderr))
        }
    }

    /// Translates afconvert/LAME stderr into a friendly localized message. Raw stderr is logged for debugging.
    private static func friendlyAFConvertMessage(for stderr: String) -> String {
        log.error("afconvert stderr: \(stderr, privacy: .public)")
        let s = stderr.lowercased()
        if s.contains("'!dat'") || s.contains("couldn't set audio converter property") {
            return String(
                localized: "This audio file uses settings (sample rate or codec) that can’t be re-encoded with the chosen quality. Try a different quality tier or output format.",
                comment: "Audio conversion error when afconvert rejects encoder properties."
            )
        }
        if s.contains("unsupported") || s.contains("'fmt?'") || s.contains("'typ?'") {
            return String(
                localized: "This audio file uses a codec macOS can’t decode. Try converting it with another tool first.",
                comment: "Audio conversion error for unsupported source codec."
            )
        }
        return String(
            localized: "Audio conversion failed. The file may be corrupt or use an unsupported format.",
            comment: "Generic audio conversion failure."
        )
    }
}
