import DinkyCLILib
import Foundation

@main
struct Dinky {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args[0] == "help" || args[0] == "-h" || args[0] == "--help" {
            DinkyCLIHelp.printHelp()
            Foundation.exit(0)
        }
        if args[0] == "version" || args[0] == "--version" {
            print("dinky 0.1.0 (DinkyCoreImage)")
            Foundation.exit(0)
        }
        if args[0] == "serve" {
            DinkyServeCommand.runBlocking(args: Array(args.dropFirst()))
        }
        if args[0] == "compress" {
            let sem = DispatchSemaphore(value: 0)
            var outCode: Int32 = 1
            Task {
                (outCode, _) = await DinkyCompressCommand.run(Array(args.dropFirst()))
                sem.signal()
            }
            sem.wait()
            Foundation.exit(Int32(outCode))
        }
        FileHandle.standardError.write(Data("dinky: unknown command '\(args[0])'. Try dinky help\n".utf8))
        Foundation.exit(1)
    }
}
