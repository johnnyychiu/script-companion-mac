// Pure, platform-independent validation of the position-only AppleScript response.
import Foundation
struct PowerPointPosition {
    let number: Int
    let total: Int
    let slideID: String
}
enum PowerPointPositionParser {
    static func parse(_ data: Data) -> PowerPointPosition? {
        guard data.count <= 2048, let raw = String(data: data, encoding: .utf8) else { return nil }
        let fields = raw.trimmingCharacters(in: .newlines)
            .split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 3, let number = Int(fields[0]), let total = Int(fields[1]),
              number > 0, number <= total, total <= 2000, fields[2].count <= 200,
              !fields[2].contains("\n"), !fields[2].contains("\r") else { return nil }
        return PowerPointPosition(number: number, total: total, slideID: fields[2])
    }
}
