/* Dokey Core - C API for platform layers (Swift, Win32, Kotlin/JNI).
 * Copyright (c) 2026 Do Huy Toan. All rights reserved. */
#ifndef DOKEY_H
#define DOKEY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct dokey_engine dokey_engine;

enum { DOKEY_TELEX = 0, DOKEY_VNI = 1 };
enum { DOKEY_UNICODE = 0, DOKEY_UNICODE_COMBINING = 1 };

typedef struct {
    int method;            /* DOKEY_TELEX or DOKEY_VNI */
    int encoding;          /* DOKEY_UNICODE or DOKEY_UNICODE_COMBINING */
    int modern_tone_style; /* 1: hoà, khoẻ, thuý */
    int check_spelling;    /* 1: keep non-Vietnamese words as typed */
} dokey_options;

#define DOKEY_MAX_EDIT 64

typedef struct {
    int backspaces;                  /* characters to delete first */
    int length;                      /* UTF-16 units in text */
    uint16_t text[DOKEY_MAX_EDIT];   /* text to insert */
} dokey_edit;

dokey_engine* dokey_create(const dokey_options* options);
void dokey_set_options(dokey_engine* engine, const dokey_options* options);
/* Returns 1 if the platform must apply `out` and swallow the key,
 * 0 if the original key should go through unchanged. */
int dokey_key(dokey_engine* engine, uint32_t ch, dokey_edit* out);
void dokey_backspace(dokey_engine* engine);
void dokey_reset(dokey_engine* engine);
void dokey_destroy(dokey_engine* engine);

#ifdef __cplusplus
}
#endif

#endif /* DOKEY_H */
