// Parses ffmpeg's `-progress pipe:1` key=value stream (PRD §5 queue spec).
//
// Field notes (panel-verified):
// - `out_time_us` is microseconds. `out_time_ms` is ALSO microseconds — an ffmpeg
//   naming bug — so both parse with the same scale.
// - `progress=end` marks completion; a crash mid-encode never emits it.
// - Values can be "N/A" early in an encode.

import Foundation

public struct ProgressSnapshot: Equatable, Sendable {
    public var outTimeSeconds: Double?
    public var frame: Int?
    public var speed: Double?   // "1.23x"
    public var isEnd: Bool
}

public struct ProgressParser {
    private var buffer = ""
    private var current = ProgressSnapshot(outTimeSeconds: nil, frame: nil, speed: nil, isEnd: false)

    public init() {}

    /// Feed raw stdout chunks; returns one snapshot per completed `progress=` block.
    public mutating func consume(_ chunk: String) -> [ProgressSnapshot] {
        buffer += chunk
        var snapshots: [ProgressSnapshot] = []
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline]).trimmingCharacters(in: .whitespaces)
            buffer.removeSubrange(...newline)
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            let value = String(line[line.index(after: equals)...])
            switch key {
            case "out_time_us", "out_time_ms": // both are microseconds (naming bug)
                current.outTimeSeconds = Double(value).map { $0 / 1_000_000 }
            case "out_time": // HH:MM:SS.micro fallback
                current.outTimeSeconds = MediaProbe.seconds(fromTimeExpression: value) ?? current.outTimeSeconds
            case "frame":
                current.frame = Int(value)
            case "speed":
                current.speed = Double(value.replacingOccurrences(of: "x", with: "")
                    .trimmingCharacters(in: .whitespaces))
            case "progress": // terminates a block
                current.isEnd = (value == "end")
                snapshots.append(current)
            default:
                break
            }
        }
        return snapshots
    }

    /// 0…1 for a snapshot given the effective (trimmed) duration; nil when duration
    /// is unknown (UI shows indeterminate spinner per PRD).
    public static func fraction(of snapshot: ProgressSnapshot, effectiveDuration: Double?) -> Double? {
        guard let duration = effectiveDuration, duration > 0,
              let outTime = snapshot.outTimeSeconds else { return nil }
        return min(max(outTime / duration, 0), 1)
    }
}
