import Foundation
import BumpVersionCore

@main
struct BumpVersionCommand {
    static func main() {
        switch parseArguments(Array(CommandLine.arguments.dropFirst())) {
        case .help:
            fputs("usage: BumpVersion <patch|minor|major|x.y.z> [--date YYYY-MM-DD] [--root PATH]\n", stderr)
            exit(0)
        case .usage(let message):
            fputs("\(message)\n", stderr)
            exit(1)
        case .ready(let targetRaw, let root, let entryDate):
            runBump(targetRaw: targetRaw, root: root, entryDate: entryDate)
        }
    }

    static func runBump(targetRaw: String, root: URL, entryDate: String) {
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

    static func isoToday() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
