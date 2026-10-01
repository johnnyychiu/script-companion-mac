// The same policy is used by the macOS event tap and the portable unit tests.
// A nil result means pass the original event through, not synthesize another key.
enum PresentationKeyPolicy {
    static func lineDelta(for keyCode: Int64) -> Int? {
        switch keyCode {
        case 125: return 1   // Down: next script line
        case 126: return -1  // Up: previous script line
        default: return nil // In particular, Left=123 and Right=124 are untouched.
        }
    }
}
