import Foundation
var passed = 0
func check(_ value: Bool, _ label: String) { precondition(value, label); passed += 1 }
func rejects(_ label: String, _ work: () throws -> Void) { do { try work(); fatalError(label) } catch { passed += 1 } }
let date = ISO8601DateFormatter().date(from: "2026-10-06T15:02:00Z")!, tokyo = TimeZone(identifier: "Asia/Tokyo")!, utc = TimeZone(secondsFromGMT: 0)!
check(ConversationOptions.context(date: date, zone: tokyo).contains("2026年10月7日"), "local date after UTC midnight boundary")
check(ConversationOptions.context(date: date, zone: utc).contains("2026年10月6日"), "UTC date differs")
check(ConversationOptions.localAnswer("今日の日付を教えて。", date: date, zone: tokyo) == "今日は2026年10月7日、水曜日です。", "exact clock answer")
check(ConversationOptions.localAnswer("今何時？", date: date, zone: tokyo) == "今は0時2分です。", "local clock time")
check(ConversationOptions.localAnswer("今日の日付とニュースを教えて", date: date, zone: tokyo) == nil, "compound question must reach GPT")
check(ConversationOptions.supported(["slug": "unknown-model"]).isEmpty, "unknown model has no invented controls")
check(ConversationOptions.supported(["supported_reasoning_efforts": [["effort": "xhigh"], ["effort": "none"], ["effort": "made_up"]]]) == ["none", "xhigh"], "validated server metadata")
check(try ConversationOptions.effort("instant", supported: ["low", "medium"], search: true) == "low", "instant uses fastest valid effort")
check(try ConversationOptions.effort("instant", supported: ["none", "low"], search: true) == "none", "instant without reasoning")
check(try ConversationOptions.effort("instant", supported: ["minimal", "low"], search: true) == "low", "minimal search compatibility")
rejects("unsupported effort") { _ = try ConversationOptions.effort("xhigh", supported: ["low"], search: true) }
let input = [["role": "user", "content": "今日のニュースを調べて"]]
let payload = try ConversationOptions.payload(model: "fixture", input: input, instructions: "自然な会話", options: ["effort": "xhigh"], supported: ["none", "low", "xhigh"], date: date, zone: tokyo)
check(payload["store"] as? Bool == false && payload["stream"] as? Bool == true, "official plan flow fields")
check(payload["tool_choice"] as? String == "required", "explicit research requires search")
check((payload["tools"] as? [[String: String]])?.first?["type"] == "web_search", "live search tool")
check((payload["reasoning"] as? [String: String])?["effort"] == "xhigh", "selected level is transmitted")
check(!ConversationOptions.needsFresh("今日は元気だよ"), "casual greeting must not force search")
check(ConversationOptions.needsFresh("この製品について調べて"), "research need not be news")
let off = try ConversationOptions.payload(model: "fixture", input: input, instructions: "", options: ["webSearch": "off"], supported: [], date: date, zone: tokyo)
check(off["tools"] == nil && off["reasoning"] == nil, "unknown model and disabled search omit unsupported parameters")
check((off["instructions"] as? String)?.contains("最新の出来事を確認済みとして答えない") == true, "no fake freshness")
let citation: [String: Any] = ["type": "url_citation", "title": "Example", "url": "https://example.org/news"]
let sources = WebSources.extract(["response": ["output": [["content": [["annotations": [citation, citation, ["type": "url_citation", "url": "javascript:alert(1)"], ["type": "url_citation", "url": "https://secret@example.org"]]]]]]]])
check(sources.count == 1 && sources[0]["title"] == "Example", "deduplicate and reject unsafe citation URLs")
check(ConversationOptions.error(code: nil, message: "web_search is not supported", status: 400, search: true).contains("最新情報は未確認"), "search capability failure remains honest")
check(ConversationOptions.error(code: nil, message: "unsupported reasoning effort", status: 400, search: false).contains("モデル標準"), "reasoning failure recovery")
var chunks = VoiceChunkBuffer()
check(chunks.take("こんにちは。続きです", done: false) == "こんにちは。", "first sentence before completion")
check(chunks.take("こんにちは。続きです", done: false) == nil, "wait for natural boundary")
check(chunks.take("こんにちは。続きです", done: false, flush: true) == "続きです", "bounded idle flush")
check(chunks.take("こんにちは。続きです", done: true) == nil, "do not replay heard buffer")
check(VoiceChunkBuffer.clean("最新です。\u{E200}cite\u{E202}turn1\u{E201}") == "最新です。", "do not pronounce citation markers")
print("Conversation options/date/search/citations/chunks tests passed: \(passed)")
