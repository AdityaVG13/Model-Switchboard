import Foundation

extension BumpVersionCommand {
    static func consumeArgument(
        _ arg: String,
        args: [String],
        index: inout Int,
        entryDate: inout String,
        root: inout URL,
        positional: inout [String]
    ) -> ParsedArguments? {
        if arg == "--help" || arg == "-h" {
            return .help
        }
        if arg == "--date" || arg == "--root" {
            return applyFlag(arg, args: args, index: &index, entryDate: &entryDate, root: &root)
        }
        if arg.hasPrefix("-") {
            return .usage("unknown option: \(arg)")
        }
        positional.append(arg)
        index += 1
        return nil
    }

    static func applyFlag(
        _ arg: String,
        args: [String],
        index: inout Int,
        entryDate: inout String,
        root: inout URL
    ) -> ParsedArguments? {
        guard let value = takeValue(arg, args: args, index: &index) else {
            return .usage("missing value for \(arg)")
        }
        if arg == "--date" {
            entryDate = value
            return nil
        }
        if arg == "--root" {
            root = URL(fileURLWithPath: value).standardizedFileURL
            return nil
        }
        return nil
    }
}
