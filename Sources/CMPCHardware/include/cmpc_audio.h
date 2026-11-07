#ifndef CMPC_AUDIO_H
#define CMPC_AUDIO_H

#include <stddef.h>
#include <stdint.h>

/// Song playback on an ALSA PCM device without alsa-lib: a real-time thread mixes
/// stems (MP3, Ogg Vorbis or WAV, decoded on the fly from memory, resampled to the
/// device rate) and one-shot sound effects, and keeps a clock of what is heard.
typedef struct cmpc_audio cmpc_audio;

/// Opens the playback device (`/dev/snd/by-path/platform-sound`, else card 0) and
/// starts the mixer thread, which plays silence until stems are started.
cmpc_audio *cmpc_audio_open(char *err, size_t err_len);
void cmpc_audio_close(cmpc_audio *audio);

/// An engine without a device or thread, for tests: `cmpc_audio_render` mixes on
/// demand, and what is rendered counts as heard at once.
cmpc_audio *cmpc_audio_open_offline(unsigned rate);
/// Mixes `frames` stereo frames into `out` (offline engines only).
void cmpc_audio_render(cmpc_audio *audio, float *out, size_t frames);

/// Device setup as "4ch S32_LE 44100 Hz, period 512 x 4", for logs.
const char *cmpc_audio_describe(const cmpc_audio *audio);

/// Adds a stem (an MP3, Ogg Vorbis or WAV file's bytes, copied) to the current
/// song; the song must be stopped. Returns the stem's index, or -1 with a message
/// in `err`.
int cmpc_audio_add_stem(cmpc_audio *audio, const uint8_t *data, size_t len, char *err, size_t err_len);
/// Stops playback and removes all stems; the position goes back to 0.
void cmpc_audio_clear_stems(cmpc_audio *audio);
void cmpc_audio_set_stem_gain(cmpc_audio *audio, int stem, float gain);

/// Stops playback and puts every stem back to its start; the stems stay loaded.
void cmpc_audio_rewind(cmpc_audio *audio);
void cmpc_audio_play(cmpc_audio *audio);
void cmpc_audio_pause(cmpc_audio *audio);
/// Seconds of the song that have been heard (the device's buffer delay taken out).
double cmpc_audio_position(cmpc_audio *audio);
/// Length of the longest stem in seconds.
double cmpc_audio_duration(cmpc_audio *audio);
/// 1 once every stem has played to its end.
int cmpc_audio_finished(cmpc_audio *audio);
/// Song speed, 0.5-1 (clamped), at the same pitch; applies within a few
/// milliseconds. The position counts song seconds, so it runs slower too.
void cmpc_audio_set_speed(cmpc_audio *audio, double speed);
double cmpc_audio_speed(cmpc_audio *audio);
/// Since the last call: device underruns (heard as clicks), the average and
/// longest time mixing one period took, and how long what was mixed waited in the
/// device on average (what a new sound waits too), in seconds. Resets them.
void cmpc_audio_take_stats(cmpc_audio *audio, unsigned *underruns, double *mix_average, double *mix_longest, double *delay_average);

/// One-shot effects (miss sound, metronome click, pad sounds) live in a few slots.
#define CMPC_AUDIO_EFFECT_SLOTS 8

/// Decodes an MP3, Ogg Vorbis or WAV file into an effect slot (replacing what
/// was there). 0 or -1.
int cmpc_audio_load_effect(cmpc_audio *audio, int slot, const uint8_t *data, size_t len);
/// Puts mono samples at `rate` Hz into an effect slot. 0 or -1.
int cmpc_audio_load_effect_samples(cmpc_audio *audio, int slot, const float *samples, size_t count, unsigned rate);
void cmpc_audio_set_effect_gain(cmpc_audio *audio, int slot, float gain);
/// Plays an effect from its start, now.
void cmpc_audio_trigger_effect(cmpc_audio *audio, int slot);
/// Plays an effect when the song reaches `song_sec`, to the sample. Pending ones
/// wait while paused and are dropped with the song (`clear_stems`).
void cmpc_audio_schedule_effect(cmpc_audio *audio, int slot, double song_sec);

/// Overall gain, 0–1.
void cmpc_audio_set_master(cmpc_audio *audio, float gain);

#endif
