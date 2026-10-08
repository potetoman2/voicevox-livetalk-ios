import Foundation

enum MobileError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

final class VoiceCore {
    private let worker = DispatchQueue(label: "jp.livetalk.voicevox", qos: .userInitiated)
    private var initialized = false
    private var validStyles = Set<UInt32>()
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
                guard var styles = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                      let voice = Bundle.main.resourceURL?.appendingPathComponent("voice"),
                      let inventory = try JSONSerialization.jsonObject(with: Data(contentsOf: voice.appendingPathComponent("inventory.json"))) as? [String: Any],
                      let speakers = inventory["speakers"] as? [[String: Any]] else { throw MobileError.message("話者情報を取得できません") }
                for i in styles.indices {
                    let name = styles[i]["name"] as? String
                    guard let entry = speakers.first(where: { ($0["name"] as? String) == name }),
                          let credit = entry["credit"] as? String, !credit.isEmpty, credit.count <= 120 else { throw MobileError.message("音声のクレジット情報を確認できません") }
                    styles[i]["credit"] = credit
                }
                self.validStyles = Set(styles.flatMap { ($0["styles"] as? [[String: Any]]) ?? [] }.compactMap { ($0["id"] as? NSNumber)?.uint32Value })
                DispatchQueue.main.async { completion(.success(styles)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    func synthesize(text: String, settings: [String: Any], completion: @escaping (Result<Data, Error>) -> Void) {
        worker.async {
            do {
                guard self.initialized else { throw MobileError.message("先に音声を準備してください") }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= 200 else { throw MobileError.message("読み上げる短文の長さが正しくありません") }
                let numberStyle = (settings["style"] as? NSNumber)?.doubleValue ?? Double(self.validStyles.min() ?? 0)
                guard numberStyle.isFinite, numberStyle >= 0, numberStyle <= Double(UInt32.max), numberStyle.rounded() == numberStyle else { throw MobileError.message("音声スタイルが正しくありません") }
                let style = UInt32(numberStyle); guard self.validStyles.contains(style) else { throw MobileError.message("この音声スタイルは同梱されていません。設定で声を選び直してください。") }
                guard let raw = lt_query(text, style) else { throw MobileError.message(String(cString: lt_error())) }
                let data = Data(String(cString: raw).utf8); lt_json_free(raw)
                guard var query = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MobileError.message("音声設定を作成できません") }
                func number(_ key: String, _ fallback: Double) -> Double {
                    let limits: [String: (Double, Double)] = ["speed": (0.5, 2), "pitch": (-0.15, 0.15), "intonation": (0, 2), "volume": (0, 2), "pre": (0, 1), "post": (0, 1), "comma": (0, 1), "sentence": (0, 1)]
                    let value = (settings[key] as? NSNumber)?.doubleValue ?? fallback
                    guard value.isFinite, let range = limits[key] else { return fallback }
                    return min(range.1, max(range.0, value))
                }
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
