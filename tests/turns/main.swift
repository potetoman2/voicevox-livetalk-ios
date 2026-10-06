import Foundation
var count = 0
func check(_ value: Bool, _ label: String) { precondition(value, label); count += 1 }
var detector = SpeechTurnDetector()
check(!detector.feed(levelDB: -25, now: 0, hasTranscript: false), "speech onset")
check(!detector.feed(levelDB: -26, now: 0.9, hasTranscript: true), "unchanged transcript while speaking")
check(!detector.feed(levelDB: -65, now: 1.2, hasTranscript: true), "short pause")
check(!detector.feed(levelDB: -24, now: 1.3, hasTranscript: true), "resume speech")
check(!detector.feed(levelDB: -65, now: 1.6, hasTranscript: true), "short pause again")
check(detector.feed(levelDB: -65, now: 2.05, hasTranscript: true), "end on actual silence")
check(!detector.feed(levelDB: -65, now: 4, hasTranscript: true), "once per utterance")
var empty = SpeechTurnDetector()
check(!empty.feed(levelDB: -65, now: 10, hasTranscript: false), "never send empty question")
check(!empty.feed(levelDB: .nan, now: 11, hasTranscript: true), "reject invalid meter")
print("Speech turn detection: \(count) assertions passed")
