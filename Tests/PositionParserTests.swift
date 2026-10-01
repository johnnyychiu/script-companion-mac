import Foundation
@main
struct PositionParserTests {
    static func main() {
        var assertions = 0
        func check(_ ok: @autoclosure () -> Bool, _ title: String) {
            precondition(ok(), title); assertions += 1
        }
        func parse(_ s: String) -> PowerPointPosition? { PowerPointPositionParser.parse(Data(s.utf8)) }
        check(parse("4\t12\t259\n")?.number == 4, "current slide")
        check(parse("4\t12\t259\r\n")?.total == 12, "count and CRLF")
        check(parse("4\t12\t259\n")?.slideID == "259", "stable ID")
        check(parse("1\t1\t\n")?.slideID == "", "missing ID is allowed, never invent it")
        for bad in ["", "1", "1\t3", "0\t3\t1", "4\t3\t1", "1\t2001\t1", "1\t0\t1", "text\t3\t1", "1\t3\t1\t2", "1\t3\tx\ny"] {
            check(parse(bad) == nil, "malformed position rejected")
        }
        check(PowerPointPositionParser.parse(Data([0xff,0xfe])) == nil, "invalid UTF8")
        check(parse("1\t3\t"+String(repeating:"x",count:201)) == nil, "ID length limit")
        check(PowerPointPositionParser.parse(Data(repeating:65,count:2050)) == nil, "output limit")
        for n in 1...2000 { check(parse("\(n)\t2000\t\(n+255)\n")?.number == n, "all supported indexes") }
        print("PASS \(assertions) pure Swift position-parser assertions. AppleScript/macOS execution is not tested.")
    }
}
