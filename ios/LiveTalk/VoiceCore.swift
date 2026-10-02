import Foundation

enum MobileError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

final class VoiceCore {
    private let worker = DispatchQueue(label: "jp.livetalk.voicevox", qos: .userInitiated)
    private var initialized = false
    func prepare(completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        worker.async {
            do {
                if !self.initialized {
                    guard let voice = Bundle.main.resourceURL?.appendingPathComponent("voice"),
                          FileManager.default.fileExists(atPath: voice.appendingPathComponent("model.vvm").path) else {
                        throw MobileError.message("音声モデルが同梱されていません。準備スクリプトでアプリを作成してください")
                    }
                    let error = lt_open(voice.appendingPathComponent("dictionary").path, voice.appendingPathComponent("model.vvm").path, "")
                    if let error { throw MobileError.message(String(cString: error)) }
                    self.initialized = true
                }
                guard let raw = lt_styles() else { throw MobileError.message(String(cString: lt_error())) }
                defer { lt_json_free(raw) }
                let data = Data(String(cString: raw).utf8)
                guard let styles = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw MobileError.message("話者情報を取得できません") }
                DispatchQueue.main.async { completion(.success(styles)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    func synthesize(text: String, settings: [String: Any], completion: @escaping (Result<Data, Error>) -> Void) {
        worker.async {
            do {
                guard self.initialized else { throw MobileError.message("先に音声を準備してください") }
                let style = UInt32((settings["style"] as? NSNumber)?.uint32Value ?? 3)
                guard let raw = lt_query(text, style) else { throw MobileError.message(String(cString: lt_error())) }
                let data = Data(String(cString: raw).utf8); lt_json_free(raw)
                guard var query = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MobileError.message("音声設定を作成できません") }
                func number(_ key: String, _ fallback: Double) -> Double { (settings[key] as? NSNumber)?.doubleValue ?? fallback }
                query["speedScale"] = number("speed", 1.05); query["pitchScale"] = number("pitch", 0)
                query["intonationScale"] = number("intonation", 1.1); query["volumeScale"] = number("volume", 1)
                query["prePhonemeLength"] = number("pre", 0.02)
                let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines).last.map { "。！？!?".contains($0) } ?? false
                query["postPhonemeLength"] = number("post", 0.03) + (sentence ? number("sentence", 0.12) : 0)
                query["outputSamplingRate"] = 24000; query["outputStereo"] = false
                if var phrases = query["accent_phrases"] as? [[String: Any]] {
                    for i in phrases.indices { if var pause = phrases[i]["pause_mora"] as? [String: Any] { pause["vowel_length"] = number("comma", 0.08); phrases[i]["pause_mora"] = pause } }
                    query["accent_phrases"] = phrases
                }
                let json = String(data: try JSONSerialization.data(withJSONObject: query), encoding: .utf8)!
                var length = 0
                guard let wav = lt_synthesis(json, style, &length) else { throw MobileError.message(String(cString: lt_error())) }
                let result = Data(bytes: wav, count: length); lt_wav_free(wav)
                DispatchQueue.main.async { completion(.success(result)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
}
