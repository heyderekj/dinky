import DinkyCoreImage
import DinkyCoreShared
import XCTest

/// A result is only finalized once it's being kept, and the original is only ever touched after
/// the output is safe — or, when replacing it in place, restored if the swap fails.
final class OutputFinalizerTests: XCTestCase {

    private var dir: URL!
    private var trash: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("dinky-finalize-\(UUID().uuidString)", isDirectory: true)
        trash = dir.appendingPathComponent("FakeTrash", isDirectory: true)
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir)
    }

    /// Stands in for the real Trash so tests don't litter the user's.
    private var fakeDispose: OutputFinalizer.Disposer {
        { [trash, fm] url, action, backup in
            switch action {
            case .keep: return nil
            case .trash:
                let dest = trash!.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try fm.moveItem(at: url, to: dest)
                return dest
            case .backup:
                guard let backup else { throw OriginalsHandlerError.missingBackupFolder }
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                let dest = OriginalsHandler.uniqueDestination(in: backup, for: url)
                try fm.moveItem(at: url, to: dest)
                return dest
            }
        }
    }

    private func write(_ name: String, _ contents: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func read(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    private func finalize(
        source: URL, produced: URL, staged: URL? = nil,
        action: OriginalsAction, backup: URL? = nil, urlDownload: Bool = false,
        dispose: OutputFinalizer.Disposer? = nil
    ) throws -> OutputFinalizer.Result {
        try OutputFinalizer.finalize(
            source: source, produced: produced, stagedDestination: staged,
            action: action, backupFolder: backup, isURLDownloadSource: urlDownload,
            collisionStyle: .finderDuplicate, customPattern: "",
            dispose: dispose ?? fakeDispose
        )
    }

    func testKeepLeavesOriginalUntouched() throws {
        let src = try write("photo.jpg", "original")
        let out = try write("photo-dinky.webp", "compressed")
        let r = try finalize(source: src, produced: out, action: .keep)
        XCTAssertEqual(r.outputURL, out)
        XCTAssertNil(r.originalRecoveryURL)
        XCTAssertEqual(try read(src), "original")
    }

    func testTrashMovesOriginalAfterOutputIsPlaced() throws {
        let src = try write("photo.jpg", "original")
        let out = try write("photo-dinky.webp", "compressed")
        let r = try finalize(source: src, produced: out, action: .trash)
        XCTAssertFalse(fm.fileExists(atPath: src.path))
        XCTAssertEqual(try read(XCTUnwrap(r.originalRecoveryURL)), "original")
        XCTAssertEqual(try read(r.outputURL), "compressed")
    }

    func testBackupReturnsRecoveryURL() throws {
        let src = try write("photo.jpg", "original")
        let out = try write("photo-dinky.webp", "compressed")
        let backup = dir.appendingPathComponent("Backup", isDirectory: true)
        let r = try finalize(source: src, produced: out, action: .backup, backup: backup)
        let recovery = try XCTUnwrap(r.originalRecoveryURL)
        XCTAssertEqual(recovery.deletingLastPathComponent().standardizedFileURL, backup.standardizedFileURL)
        XCTAssertEqual(try read(recovery), "original")
    }

    /// A failed Trash/Backup after the output is in place leaves the original where it was.
    func testFailedDisposalOnSeparateOutputKeepsOriginal() throws {
        let src = try write("photo.jpg", "original")
        let out = try write("photo-dinky.webp", "compressed")
        let r = try finalize(source: src, produced: out, action: .backup, backup: nil)
        XCTAssertNil(r.originalRecoveryURL)
        XCTAssertEqual(try read(src), "original")
        XCTAssertEqual(try read(r.outputURL), "compressed")
    }

    func testStagedOutputMovesToDestination() throws {
        let src = try write("photo.jpg", "original")
        let tmp = try write("staged.tmp", "compressed")
        let dest = dir.appendingPathComponent("out/photo.webp")
        let r = try finalize(source: src, produced: tmp, staged: dest, action: .keep)
        XCTAssertEqual(r.outputURL.standardizedFileURL, dest.standardizedFileURL)
        XCTAssertFalse(fm.fileExists(atPath: tmp.path))
        XCTAssertEqual(try read(src), "original")
    }

    /// Replace original, same name: the original has to move out of the way even under "keep",
    /// and the new file takes its place.
    func testReplacingSourceDisposesFirstThenMoves() throws {
        let src = try write("photo.webp", "original")
        let tmp = try write("staged.tmp", "compressed")
        let r = try finalize(source: src, produced: tmp, staged: src, action: .keep)
        XCTAssertEqual(r.outputURL.standardizedFileURL, src.standardizedFileURL)
        XCTAssertEqual(try read(src), "compressed")
        XCTAssertEqual(try read(XCTUnwrap(r.originalRecoveryURL)), "original")
    }

    func testReplacingSourceWhenDisposalFailsLeavesOriginal() throws {
        let src = try write("photo.webp", "original")
        let tmp = try write("staged.tmp", "compressed")
        struct Boom: Error {}
        XCTAssertThrowsError(try finalize(source: src, produced: tmp, staged: src, action: .trash, dispose: { _, _, _ in throw Boom() }))
        XCTAssertEqual(try read(src), "original")
        XCTAssertFalse(fm.fileExists(atPath: tmp.path), "temp output is cleaned up")
    }

    func testReplacingSourceRestoresOriginalWhenMoveFails() throws {
        let src = try write("photo.webp", "original")
        let missingTemp = dir.appendingPathComponent("never-written.tmp")
        XCTAssertThrowsError(try finalize(source: src, produced: missingTemp, staged: src, action: .trash))
        XCTAssertEqual(try read(src), "original")
    }

    func testURLDownloadRemovesTempSourceAndNeverTrashes() throws {
        let src = try write("download.jpg", "downloaded")
        let out = try write("download.webp", "compressed")
        var disposed = false
        let r = try finalize(source: src, produced: out, action: .trash, urlDownload: true,
                             dispose: { _, _, _ in disposed = true; return nil })
        XCTAssertFalse(disposed)
        XCTAssertNil(r.originalRecoveryURL)
        XCTAssertFalse(fm.fileExists(atPath: src.path))
        XCTAssertEqual(try read(r.outputURL), "compressed")
    }
}
