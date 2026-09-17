import Foundation

enum EventTime {
    static func rfc3339Milliseconds(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func parseRFC3339(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return wholeSeconds.date(from: value)
    }

    static func encoder(prettyPrinted: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(rfc3339Milliseconds(date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = parseRFC3339(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected RFC 3339 timestamp with UTC offset"
                )
            }
            return date
        }
        return decoder
    }

    static func date(unixSeconds: Int64?) -> Date? {
        unixSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    static func date(unixMilliseconds: Int64?) -> Date? {
        unixMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) }
    }

    static func compactDuration(milliseconds: Int64?) -> String {
        guard let milliseconds else { return "—" }
        let totalSeconds = max(0, milliseconds / 1_000)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return String(format: "%lldh %02lldm", hours, minutes) }
        if minutes > 0 { return String(format: "%lldm %02llds", minutes, seconds) }
        return String(format: "%llds", seconds)
    }

    static func relativeDescription(from date: Date, to now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        if seconds < 3_600 { return "\(seconds / 60) 分钟前" }
        if seconds < 86_400 { return "\(seconds / 3_600) 小时前" }
        return "\(seconds / 86_400) 天前"
    }
}
