@main
struct SlideNavigationPolicyTests {
    static func main() {
        var assertions = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            precondition(value(), name); assertions += 1
        }
        for total in [1, 2, 9, 10, 100, 2000] {
            for current in 1...total {
                check(SlideNavigationPolicy.target(current: current, total: total, direction: "next") == min(total, current + 1), "next stays in bounds")
                check(SlideNavigationPolicy.target(current: current, total: total, direction: "previous") == max(1, current - 1), "previous stays in bounds")
            }
        }
        for total in [-2,0,2001] { check(SlideNavigationPolicy.target(current: 1, total: total, direction: "next") == nil, "invalid totals blocked") }
        check(SlideNavigationPolicy.target(current: 0, total: 5, direction: "next") == nil, "invalid current blocked")
        check(SlideNavigationPolicy.target(current: 2, total: 5, direction: "other") == nil, "unknown direction blocked")
        check(SlideNavigationPolicy.observe(before: 4, target: 5, actual: 5, total: 12) == .confirmed, "actual target confirms")
        check(SlideNavigationPolicy.observe(before: 4, target: 5, actual: 4, total: 12) == .unchanged, "unchanged is not success")
        check(SlideNavigationPolicy.observe(before: 4, target: 5, actual: 7, total: 12) == .changedElsewhere, "other navigation is not success")
        check(SlideNavigationPolicy.observe(before: 4, target: 5, actual: 13, total: 12) == .invalid, "invalid reading blocked")
        check(SlideNavigationPolicy.keyCodes(slide: 14) == [18,21,36], "14 plus Return")
        check(SlideNavigationPolicy.keyCodes(slide: 2000) == [19,29,29,29,36], "2000 plus Return")
        check(SlideNavigationPolicy.keyCodes(slide: 0) == nil, "no slide zero")
        check(SlideNavigationPolicy.keyCodes(slide: 2001) == nil, "oversized target blocked")
        for slide in 1...2000 {
            let keys = SlideNavigationPolicy.keyCodes(slide: slide)!
            check(keys.last == 36 && !keys.contains(53), "Return is terminal; Escape is never sent")
        }
        print("PASS \(assertions) platform-independent slide-navigation assertions. This does not test macOS keyboard delivery.")
    }
}
