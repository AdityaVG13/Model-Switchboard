import Foundation

extension BumpVersionCore {
    public static func insertChangelogEntry(_ text: String, version: String, entryDate: String) throws -> String {
        let header = "## [\(version)]"
        if text.contains(header) {
            throw BumpVersionError.changelogAlreadyContains(header)
        }
        let entry = """
        \(header) - \(entryDate)

        ### Added
        - TBD

        ### Changed
        - TBD

        ### Fixed
        - TBD

        """
        if let marker = text.range(of: "\n## [") {
            let afterNewline = text.index(after: marker.lowerBound)
            return String(text[..<afterNewline]) + entry + String(text[afterNewline...])
        }
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) + "\n\n" + entry
    }

    public static func validateISODate(_ raw: String) throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard formatter.date(from: raw) != nil else {
            throw BumpVersionError.invalidDate(raw)
        }
    }
}
