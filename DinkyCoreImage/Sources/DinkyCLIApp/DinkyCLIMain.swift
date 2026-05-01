import DinkyCLILib
import Foundation

private final class AsyncResultBox<T>: @unchecked Sendable {
    var value: T?
}

@main
struct Dinky {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args[0] == "help" || args[0] == "-h" || args[0] == "--help" {
            DinkyCLIHelp.printHelp()
            Foundation.exit(0)
        }
        if args[0] == "version" || args[0] == "--version" {
            print("dinky 2.9.0 (CLI)")
            Foundation.exit(0)
        }
        if args[0] == "serve" {
            DinkyServeCommand.runBlocking(args: Array(args.dropFirst()))
        }
        if args[0] == "compress-image" {
            runAsync { await DinkyCompressCommand.run(Array(args.dropFirst())) }
        }
        if args[0] == "compress" {
            FileHandle.standardError.write(
                Data("dinky: warning: `compress` is deprecated; use `compress-image` (same flags).\n".utf8)
            )
            runAsync { await DinkyCompressCommand.run(Array(args.dropFirst())) }
        }
        if args[0] == "compress-video" {
            runAsync { await DinkyVideoCompressCommand.run(Array(args.dropFirst())) }
        }
        if args[0] == "compress-pdf" {
            runAsync { await DinkyPdfCompressCommand.run(Array(args.dropFirst())) }
        }
        if args[0] == "ocr" {
            runAsync { (await DinkyOcrCommand.run(Array(args.dropFirst())), 0) }
        }
        if args[0] == "make-fixtures" {
            runAsync { await DinkyMakeFixturesCommand.run(Array(args.dropFirst())) }
        }
        FileHandle.standardError.write(Data("dinky: unknown command '\(args[0])'. Try dinky help\n".utf8))
        Foundation.exit(1)
    }

    /// Run async CLI work from sync `main` (Swift 6 `sending` / `Task` friendly).
    private static func runAsync(_ work: @Sendable @escaping () async -> (Int32, Int)) {
        let result = unsafeWaitForAsync {
            await work()
        }
        Foundation.exit(result.0)
    }

    private static func unsafeWaitForAsync<T>(
        _ body: @Sendable @escaping () async -> T
    ) -> T {
        let box = AsyncResultBox<T>()
        let sem = DispatchSemaphore(value: 0)
        Task {
            let r = await body()
            box.value = r
            sem.signal()
        }
        sem.wait()
        return box.value!
    }
}
