import Foundation
import ModelSwitchboardCore

extension ProfileRepository {
    func parseValue(_ raw: String, file: URL, line: Int) throws -> String {
        guard let first = raw.first, first == "\"" || first == "'" else {
            return raw.split(separator: "#", maxSplits: 1).first.map(String.init)?.trimmingCharacters(
                in: .whitespaces) ?? ""
        }
        guard raw.last == first, raw.count >= 2 else {
            throw ControllerError.invalidProfile("\(file.path):\(line): invalid quoted value")
        }
        let inner = String(raw.dropFirst().dropLast())
        if first == "'" { return inner }
        return unescapeDoubleQuoted(inner)
    }

    func unescapeDoubleQuoted(_ inner: String) -> String {
        var value = ""
        var escaped = false
        for character in inner {
            if escaped {
                value.append(Self.unescapedDoubleQuote(character))
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                value.append(character)
            }
        }
        if escaped { value.append("\\") }
        return value
    }

    static func unescapedDoubleQuote(_ character: Character) -> Character {
        switch character {
        case "n": return "\n"
        case "t": return "\t"
        default: return character
        }
    }
}
