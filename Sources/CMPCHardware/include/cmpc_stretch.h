#ifndef CMPC_STRETCH_H
#define CMPC_STRETCH_H

#include <stddef.h>
#include <stdint.h>

/// Slower playback at the same pitch (WSOLA). The song comes in at its own speed
/// from a source; the output is built from overlapping Hann-windowed segments of
/// it, one every hop of output, taken a hop times the speed of song apart. Each
/// segment may move by a few milliseconds to where it best continues the previous
/// one, so the waveform stays smooth. At speed 1 the output is the song, sample
/// for sample.
typedef struct cmpc_stretch cmpc_stretch;

/// Mixes the next `frames` song frames into `out` (stereo, zeroed by the caller).
typedef void (*cmpc_stretch_source)(void *context, float *out, size_t frames);

/// At song frame 0, reading from `source`.
cmpc_stretch *cmpc_stretch_new(cmpc_stretch_source source, void *context);
void cmpc_stretch_free(cmpc_stretch *stretch);
/// Back to song frame 0, before anything was read.
void cmpc_stretch_reset(cmpc_stretch *stretch);

/// The next `frames` output frames at `speed` (song frames per output frame,
/// 0.5–1) into `out` (stereo), and into `song`, if given, the song frame each one
/// stands for.
void cmpc_stretch_render(cmpc_stretch *stretch, double speed, float *out, double *song, size_t frames);
/// The song frame the next output frame stands for.
double cmpc_stretch_position(const cmpc_stretch *stretch);

#endif
