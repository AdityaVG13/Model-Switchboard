import Foundation
import BumpVersionCore

@main
struct BumpVersionCommand {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        var entryDate = isoToday()
        var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var positional: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg == "--date" {
                index += 1
                guard index < args.count else {
                    fputs("missing value for --date\n", stderr)
                    exit(1)
                }
                entryDate = args[index]
            } else if arg == "--root" {
                index += 1
                guard index < args.count else {
                    fputs("missing value for --root\n", stderr)
                    exit(1)
                }
                root = URL(fileURLWithPath: args[index]).standardizedFileURL
            } else if arg == "--help" || arg == "-h" {
                fputs("usage: BumpVersion <patch|minor|major|x.y.z> [--date YYYY-MM-DD] [--root PATH]\n", stderr)
                exit(0)
            } else if arg.hasPrefix("-") {
                fputs("unknown option: \(arg)\n", stderr)
                exit(1)
            } else {
                positional.append(arg)
            }
            index += 1
        }
        guard let targetRaw = positional.first, positional.count == 1 else {
            fputs("usage: BumpVersion <patch|minor|major|x.y.z> [--date YYYY-MM-DD] [--root PATH]\n", stderr)
            exit(1)
        }
        do {
            let result = try BumpVersionCore.bump(root: root, targetRaw: targetRaw, entryDate: entryDate)
            print("old_version=\(result.old)")
            print("new_version=\(result.new)")
        } catch let error as BumpVersionError {
            fputs("\(error.description)\n", stderr)
            exit(1)
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
    }

    private static func isoToday() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
