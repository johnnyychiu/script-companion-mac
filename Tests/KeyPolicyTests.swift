// Run with Source/PresentationKeyPolicy.swift; no macOS framework required.
@main
struct KeyPolicyTests {
    static func main() {
        precondition(PresentationKeyPolicy.lineDelta(for: 125) == 1, "Down maps to next script line")
        precondition(PresentationKeyPolicy.lineDelta(for: 126) == -1, "Up maps to previous script line")
        precondition(PresentationKeyPolicy.lineDelta(for: 123) == nil, "Left must pass through unchanged")
        precondition(PresentationKeyPolicy.lineDelta(for: 124) == nil, "Right must pass through unchanged")
        for key in Int64(0)...Int64(127) where key != 125 && key != 126 {
            precondition(PresentationKeyPolicy.lineDelta(for: key) == nil, "Non-line key must not be captured")
        }
        print("PASS shared Swift key-routing policy: Up/Down only; Left/Right and all other tested keycodes pass through.")
    }
}
