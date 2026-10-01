// Platform-independent decisions used by the macOS adapter and executable tests.
// A request sends ONE absolute shortcut. Verification reads never resend keys.
enum SlideNavigationPolicy {
    static func target(current: Int, total: Int, direction: String) -> Int? {
        guard total > 0, total <= 2000, (1...total).contains(current) else { return nil }
        switch direction {
        case "next": return min(current + 1, total)
        case "previous": return max(current - 1, 1)
        default: return nil
        }
    }
    enum Observation: Equatable { case confirmed, unchanged, changedElsewhere, invalid }
    static func observe(before: Int, target: Int, actual: Int, total: Int) -> Observation {
        guard total > 0, total <= 2000, (1...total).contains(before),
              (1...total).contains(target), (1...total).contains(actual) else { return .invalid }
        if actual == target { return .confirmed }
        if actual == before { return .unchanged }
        return .changedElsewhere
    }
    static func keyCodes(slide: Int) -> [UInt16]? {
        guard (1...2000).contains(slide) else { return nil }
        let digits: [Character: UInt16] = ["0":29,"1":18,"2":19,"3":20,"4":21,"5":23,"6":22,"7":26,"8":28,"9":25]
        return String(slide).compactMap { digits[$0] } + [36] // Return, not Escape.
    }
}
