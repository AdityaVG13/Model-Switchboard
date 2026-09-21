import Foundation

extension BumpVersionCommand {
    enum ParsedArguments {
        case help
        case usage(String)
        case ready(targetRaw: String, root: URL, entryDate: String)
    }

    static func parseArguments(_ args: [String]) -> ParsedArguments {
        var entryDate = isoToday()
        var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var positional: [String] = []
        var index = 0
        while index < args.count {
            if let parsed = consumeArgument(
                args[index],
                args: args,
                index: &index,
                entryDate: &entryDate,
                root: &root,
                positional: &positional
            ) {
                return parsed
            }
        }
        guard let targetRaw = positional.first, positional.count == 1 else {
            return .usage("usage: BumpVersion <patch|minor|major|x.y.z> [--date YYYY-MM-DD] [--root PATH]")
        }
        return .ready(targetRaw: targetRaw, root: root, entryDate: entryDate)
    }

    static func takeValue(_ name: String, args: [String], index: inout Int) -> String? {
        index += 1
        guard index < args.count else { return nil }
        let value = args[index]
        index += 1
        return value
    }
}
