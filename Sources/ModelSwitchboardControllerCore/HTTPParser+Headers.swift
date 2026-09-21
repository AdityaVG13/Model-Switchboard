import Foundation
import ModelSwitchboardCore

extension HTTPParser {
    static func bodySlice(_ data: Data, bodyStart: Data.Index, contentLength: Int) -> Data? {
        guard data.count >= bodyStart + contentLength else { return nil }
        return data.subdata(in: bodyStart..<(bodyStart + contentLength))
    }

    static func headerMap(_ lines: ArraySlice<String>) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...])
                .whitespaceTrimmed
        }
        return headers
    }

    static func parsedContentLength(_ headers: [String: String]) -> Int? {
        guard let raw = headers["content-length"] else { return 0 }
        guard let parsed = Int(raw), parsed >= 0 else { return nil }
        return parsed
    }
}
