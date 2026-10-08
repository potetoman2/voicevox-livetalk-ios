#include "LTNative.h"
#include <cstdint>
#include <cstring>
#include <iostream>

// Actual inference via the iOS bridge on macOS; phone latency needs device tests.
int main(int argc, char **argv) {
    if (argc != 4) return 2;
    if (const char *error = lt_open(argv[1], argv[2], argv[3])) { std::cerr << error << '\n'; return 1; }
    const uint32_t styles[] = {10005,10007,10004,10003,10008,10006,10001,10000,10002};
    std::cout << "{\"platform\":\"macOS\",\"credit\":\"VOICEVOX Nemo\",\"voices\":[";
    bool first = true;
    for (auto style : styles) {
        char *query = lt_query("音声の確認です。", style);
        if (!query) { std::cerr << lt_error() << '\n'; lt_close(); return 1; }
        size_t length = 0; auto *wav = lt_synthesis(query, style, &length); lt_json_free(query);
        if (!wav || length <= 44 || std::memcmp(wav,"RIFF",4) || std::memcmp(wav+8,"WAVE",4)) {
            std::cerr << "Missing WAV for style " << style << '\n';
            if (wav) lt_wav_free(wav); lt_close(); return 1;
        }
        bool audible = false;
        for (size_t offset=12; offset<=length-8;) {
            uint32_t count=uint32_t(wav[offset+4]) | (uint32_t(wav[offset+5])<<8)
                | (uint32_t(wav[offset+6])<<16) | (uint32_t(wav[offset+7])<<24);
            if (count>length-offset-8) break;
            if (!std::memcmp(wav+offset,"data",4)) {
                for (size_t i=offset+8; i<offset+8+count; ++i) if (wav[i]) { audible=true; break; }
                break;
            }
            offset += 8 + size_t(count) + (count & 1);
        }
        lt_wav_free(wav);
        if (!audible) { std::cerr << "Silent WAV for style " << style << '\n'; lt_close(); return 1; }
        if (!first) std::cout << ',';
        first = false;
        std::cout << "{\"style\":" << style << ",\"wav_bytes\":" << length << '}';
    }
    lt_close(); std::cout << "]}\n";
}
