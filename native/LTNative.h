#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// All core calls are serialized internally. Strings/WAVs must be released below.
const char *lt_open(const char *dictionary, const char *model, const char *runtime);
const char *lt_error(void);
char *lt_styles(void);
char *lt_query(const char *text, uint32_t style);
uint8_t *lt_synthesis(const char *query, uint32_t style, size_t *length);
void lt_json_free(char *json);
void lt_wav_free(uint8_t *wav);
void lt_close(void);
#ifdef __cplusplus
}
#endif
