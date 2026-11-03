// MP3, Ogg Vorbis and WAV from memory, read as stereo float.

#define MINIMP3_IMPLEMENTATION
#define MINIMP3_FLOAT_OUTPUT
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#include "minimp3/minimp3_ex.h"
#pragma clang diagnostic pop

// The declarations only; vorbis.c has the code.
#define STB_VORBIS_HEADER_ONLY
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_PUSHDATA_API
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#include "stb_vorbis/stb_vorbis.h"
#pragma clang diagnostic pop

#include "decoder.h"

#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { KIND_MP3, KIND_VORBIS, KIND_WAV };

#define WAV_PCM 1
#define WAV_FLOAT 3
#define WAV_EXTENSIBLE 0xFFFE

struct decoder {
    int kind;
    int channels;
    unsigned hz;
    uint64_t frames;
    mp3dec_ex_t mp3;
    stb_vorbis *vorbis;
    struct {
        const uint8_t *data;  // the first frame
        int format, bytes;    // WAV_PCM or WAV_FLOAT; bytes per sample
        size_t block;         // bytes per frame
        uint64_t pos;
    } wav;
};

static void set_err(char *err, size_t len, const char *fmt, ...) {
    if (!err || !len) return;
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(err, len, fmt, ap);
    va_end(ap);
}

static unsigned u16le(const uint8_t *p) { return p[0] | p[1] << 8; }
static uint32_t u32le(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

// Finds the `fmt ` and `data` chunks. 0, or -1 with a message.
static int wav_open(decoder *d, const uint8_t *data, size_t len, char *err, size_t err_len) {
    const uint8_t *fmt = NULL, *body = NULL;
    size_t fmt_len = 0, body_len = 0;
    for (size_t at = 12; at + 8 <= len;) {
        uint32_t size = u32le(data + at + 4);
        size_t room = len - at - 8;
        if (!memcmp(data + at, "fmt ", 4)) {
            fmt = data + at + 8;
            fmt_len = size < room ? size : room;
        } else if (!memcmp(data + at, "data", 4)) {
            body = data + at + 8;
            body_len = size < room ? size : room;  // streamed WAVs leave the size unset
            break;
        }
        if (size >= room) break;
        at += 8 + (size_t)size + (size & 1);
    }
    if (!fmt || fmt_len < 16 || !body) {
        set_err(err, err_len, "WAV without fmt or data chunk");
        return -1;
    }
    int format = (int)u16le(fmt);
    if (format == WAV_EXTENSIBLE && fmt_len >= 26) format = (int)u16le(fmt + 24);  // the subformat GUID
    d->channels = (int)u16le(fmt + 2);
    d->hz = u32le(fmt + 4);
    d->wav.block = u16le(fmt + 12);
    unsigned bits = u16le(fmt + 14);
    int usable = format == WAV_PCM ? (bits == 8 || bits == 16 || bits == 24 || bits == 32)
               : format == WAV_FLOAT ? (bits == 32 || bits == 64) : 0;
    if (!usable || d->channels < 1 || d->hz == 0 || d->wav.block < (size_t)d->channels * bits / 8) {
        set_err(err, err_len, "WAV format %d with %u bits not supported", format, bits);
        return -1;
    }
    d->wav.format = format;
    d->wav.bytes = (int)bits / 8;
    d->wav.data = body;
    d->frames = body_len / d->wav.block;
    return 0;
}

static float wav_sample(const decoder *d, const uint8_t *p) {
    if (d->wav.format == WAV_FLOAT) {
        if (d->wav.bytes == 8) {
            double v;
            memcpy(&v, p, 8);
            return (float)v;
        }
        float v;
        memcpy(&v, p, 4);
        return v;
    }
    switch (d->wav.bytes) {
    case 1: return (p[0] - 128) / 128.0f;
    case 2: return (int16_t)u16le(p) / 32768.0f;
    case 3: return (int32_t)((uint32_t)p[0] << 8 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 24) / 2147483648.0f;
    default: return (int32_t)u32le(p) / 2147483648.0f;
    }
}

decoder *decoder_open(const uint8_t *data, size_t len, char *err, size_t err_len) {
    decoder *d = calloc(1, sizeof(*d));
    if (len >= 12 && !memcmp(data, "RIFF", 4) && !memcmp(data + 8, "WAVE", 4)) {
        d->kind = KIND_WAV;
        if (wav_open(d, data, len, err, err_len)) {
            free(d);
            return NULL;
        }
    } else if (len >= 4 && !memcmp(data, "OggS", 4)) {
        d->kind = KIND_VORBIS;
        int error = 0;
        d->vorbis = len <= INT_MAX ? stb_vorbis_open_memory(data, (int)len, &error, NULL) : NULL;
        if (!d->vorbis) {
            set_err(err, err_len, "not a playable Ogg Vorbis (%d)", error);  // Opus also starts with OggS
            free(d);
            return NULL;
        }
        stb_vorbis_info info = stb_vorbis_get_info(d->vorbis);
        d->channels = info.channels;
        d->hz = info.sample_rate;
        d->frames = stb_vorbis_stream_length_in_samples(d->vorbis);
    } else {
        // MP3 has no fixed first bytes (an ID3 tag or a frame), so it is the rest.
        d->kind = KIND_MP3;
        // The index scan reads every frame header.
        int rc = mp3dec_ex_open_buf(&d->mp3, data, len, MP3D_SEEK_TO_SAMPLE);
        if (rc || d->mp3.info.channels < 1 || d->mp3.info.hz <= 0) {
            set_err(err, err_len, "not a playable MP3, Ogg Vorbis or WAV (%d)", rc);
            mp3dec_ex_close(&d->mp3);
            free(d);
            return NULL;
        }
        d->channels = d->mp3.info.channels;
        d->hz = (unsigned)d->mp3.info.hz;
        d->frames = d->mp3.samples / (uint64_t)d->channels;
    }
    if (d->channels < 1 || d->hz == 0 || d->frames == 0) {
        set_err(err, err_len, "no sound in it");
        decoder_close(d);
        return NULL;
    }
    return d;
}

void decoder_close(decoder *d) {
    if (!d) return;
    if (d->kind == KIND_MP3) mp3dec_ex_close(&d->mp3);
    if (d->vorbis) stb_vorbis_close(d->vorbis);
    free(d);
}

unsigned decoder_hz(const decoder *d) { return d->hz; }
uint64_t decoder_frames(const decoder *d) { return d->frames; }

size_t decoder_read(decoder *d, float *out, size_t frames) {
    size_t got = 0;
    switch (d->kind) {
    case KIND_MP3: {
        // minimp3 gives one or two channels.
        float tmp[1152 * 2];
        while (got < frames) {
            size_t want = frames - got;
            if (want > 1152) want = 1152;
            size_t n = mp3dec_ex_read(&d->mp3, tmp, want * (size_t)d->channels) / (size_t)d->channels;
            for (size_t f = 0; f < n; f++) {
                out[(got + f) * 2] = tmp[f * (size_t)d->channels];
                out[(got + f) * 2 + 1] = tmp[f * (size_t)d->channels + (d->channels > 1)];
            }
            got += n;
            if (n < want) break;
        }
        break;
    }
    case KIND_VORBIS:
        while (got < frames) {
            size_t want = frames - got;
            if (want > 4096) want = 4096;
            // Asked for two channels, mono fills the right one with zeros.
            int n = stb_vorbis_get_samples_float_interleaved(d->vorbis, 2, out + got * 2, (int)want * 2);
            if (n <= 0) break;
            if (d->channels == 1) {
                for (int f = 0; f < n; f++) out[(got + (size_t)f) * 2 + 1] = out[(got + (size_t)f) * 2];
            }
            got += (size_t)n;
        }
        break;
    case KIND_WAV: {
        size_t step = (size_t)d->wav.bytes * (d->channels > 1);
        for (; got < frames && d->wav.pos < d->frames; got++, d->wav.pos++) {
            const uint8_t *p = d->wav.data + d->wav.pos * d->wav.block;
            out[got * 2] = wav_sample(d, p);
            out[got * 2 + 1] = wav_sample(d, p + step);
        }
        break;
    }
    }
    return got;
}

void decoder_rewind(decoder *d) {
    switch (d->kind) {
    case KIND_MP3: mp3dec_ex_seek(&d->mp3, 0); break;
    case KIND_VORBIS: stb_vorbis_seek_start(d->vorbis); break;
    case KIND_WAV: d->wav.pos = 0; break;
    }
}
