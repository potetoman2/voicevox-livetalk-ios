#include "LTNative.h"
#include "voicevox_core.h"
#include <mutex>
#include <string>

namespace {
std::mutex coreMutex;
VoicevoxSynthesizer *synth=nullptr;
thread_local std::string lastError;
bool check(VoicevoxResultCode result) {
    if(result==VOICEVOX_RESULT_OK){lastError.clear();return true;}
    lastError=voicevox_error_result_to_message(result);return false;
}
bool ready(){if(synth)return true;lastError="VOICEVOX is not initialized";return false;}
}
const char *lt_open(const char *dictionary,const char *model,const char *runtime) {
    std::lock_guard<std::mutex> lock(coreMutex);
    if(synth){voicevox_synthesizer_delete(synth);synth=nullptr;}
    const VoicevoxOnnxruntime *ort=nullptr;
#if defined(VOICEVOX_LINK_ONNXRUNTIME)
    if(!check(voicevox_onnxruntime_init_once(&ort)))return lastError.c_str();
#else
    auto load=voicevox_make_default_load_onnxruntime_options();load.filename=runtime;
    if(!check(voicevox_onnxruntime_load_once(load,&ort)))return lastError.c_str();
#endif
    OpenJtalkRc *jt=nullptr;
    if(!check(voicevox_open_jtalk_rc_new(dictionary,&jt)))return lastError.c_str();
    auto options=voicevox_make_default_initialize_options();
    options.acceleration_mode=VOICEVOX_ACCELERATION_MODE_CPU;options.cpu_num_threads=2;
    bool created=check(voicevox_synthesizer_new(ort,jt,options,&synth));
    voicevox_open_jtalk_rc_delete(jt);
    if(!created)return lastError.c_str();
    VoicevoxVoiceModelFile *vvm=nullptr;
    if(!check(voicevox_voice_model_file_open(model,&vvm))){voicevox_synthesizer_delete(synth);synth=nullptr;return lastError.c_str();}
    bool loaded=check(voicevox_synthesizer_load_voice_model(synth,vvm,voicevox_make_default_load_voice_model_options()));
    voicevox_voice_model_file_delete(vvm);
    if(!loaded){voicevox_synthesizer_delete(synth);synth=nullptr;return lastError.c_str();}
    return nullptr;
}
const char *lt_error(){return lastError.c_str();}
char *lt_styles(){std::lock_guard<std::mutex> lock(coreMutex);return ready()?voicevox_synthesizer_create_metas_json(synth):nullptr;}
char *lt_query(const char *text,uint32_t style) {
    std::lock_guard<std::mutex> lock(coreMutex);char *query=nullptr;
    if(ready()&&check(voicevox_synthesizer_create_audio_query(synth,text,style,&query)))return query;
    return nullptr;
}
uint8_t *lt_synthesis(const char *query,uint32_t style,size_t *length) {
    std::lock_guard<std::mutex> lock(coreMutex);uint8_t *wav=nullptr;
    if(ready()&&check(voicevox_synthesizer_synthesis(synth,query,style,voicevox_make_default_synthesis_options(),length,&wav)))return wav;
    return nullptr;
}
void lt_json_free(char *json){voicevox_json_free(json);}
void lt_wav_free(uint8_t *wav){voicevox_wav_free(wav);}
void lt_close(){std::lock_guard<std::mutex> lock(coreMutex);if(synth){voicevox_synthesizer_delete(synth);synth=nullptr;}}
