import Foundation
let valid = URL(string: "livetalk://read?text=%E3%81%93%E3%82%93%E3%81%AB%E3%81%A1%E3%81%AF")!
assert(IncomingText.parse(valid) == "こんにちは")
for raw in ["https://read?text=hello", "livetalk://wrong?text=hello", "livetalk://read?text=one&text=two", "livetalk://read?text=", "livetalk://read/path?text=hello"] {
    assert(IncomingText.parse(URL(string: raw)!) == nil)
}
assert(IncomingText.parse(URL(string: "livetalk://read?text=" + String(repeating: "a", count: 12001))!) == nil)
assert(IncomingText.parse(URL(string: "livetalk://read?text=%2520")!) == "%20")
print("Incoming URL intake: 8 assertions passed")
