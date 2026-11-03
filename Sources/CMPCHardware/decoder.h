#ifndef CMPC_DECODER_H
#define CMPC_DECODER_H

#include <stddef.h>
#include <stdint.h>

/// One compressed or PCM sound in memory, read as stereo float frames: MP3
/// (minimp3), Ogg Vorbis (stb_vorbis) or WAV, told apart by the first bytes.
typedef struct decoder decoder;

/// Opens `data`, which must stay alive until `decoder_close`. NULL with a message
/// in `err` when it is none of the three or has no sound.
decoder *decoder_open(const uint8_t *data, size_t len, char *err, size_t err_len);
void decoder_close(decoder *d);

unsigned decoder_hz(const decoder *d);
/// Frames in the whole sound.
uint64_t decoder_frames(const decoder *d);

/// Reads up to `frames` stereo frames into `out`: mono is copied to both sides,
/// channels past the second are left out. Returns the frames read, 0 at the end.
size_t decoder_read(decoder *d, float *out, size_t frames);
/// Goes back to the first frame.
void decoder_rewind(decoder *d);

#endif
