import Foundation

public extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Spaces and tabs only -- keeps newlines (env lines, form fields).
    var whitespaceTrimmed: String {
        trimmingCharacters(in: .whitespaces)
    }

    /// Trimmed text, or `nil` when the result is empty.
    var nonEmptyTrimmed: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    var nonEmptyWhitespaceTrimmed: String? {
        let value = whitespaceTrimmed
        return value.isEmpty ? nil : value
    }

    var strippingBrackets: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }
}

public extension Optional where Wrapped == String {
    var nonEmptyTrimmed: String? {
        self?.nonEmptyTrimmed
    }

    var nonEmptyWhitespaceTrimmed: String? {
        self?.nonEmptyWhitespaceTrimmed
    }
}
