// ALSA PCM playback with raw ioctls (the uapi structs from <sound/asound.h> are
// declared here, as in rawmidi.c) plus a stem mixer over decoder.c.

#include "cmpc_audio.h"
#include "decoder.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

// ---------------------------------------------------------------- ALSA uapi

typedef unsigned long snd_pcm_uframes_t;
typedef long snd_pcm_sframes_t;

struct snd_interval {
    unsigned int min, max;
    unsigned int openmin : 1, openmax : 1, integer : 1, empty : 1;
};

struct snd_mask {
    uint32_t bits[8];
};

struct snd_pcm_hw_params {
    unsigned int flags;
    struct snd_mask masks[3];        // ACCESS, FORMAT, SUBFORMAT
    struct snd_mask mres[5];
    struct snd_interval intervals[12];  // SAMPLE_BITS .. TICK_TIME
    struct snd_interval ires[9];
    unsigned int rmask, cmask, info, msbits, rate_num, rate_den;
    snd_pcm_uframes_t fifo_size;
    unsigned char reserved[64];
};

struct snd_xferi {
    snd_pcm_sframes_t result;
    void *buf;
    snd_pcm_uframes_t frames;
};

enum {
    PARAM_ACCESS = 0, PARAM_FORMAT = 1, PARAM_SUBFORMAT = 2,
    PARAM_FIRST_INTERVAL = 8,
    PARAM_SAMPLE_BITS = 8, PARAM_FRAME_BITS = 9, PARAM_CHANNELS = 10, PARAM_RATE = 11,
    PARAM_PERIOD_TIME = 12, PARAM_PERIOD_SIZE = 13, PARAM_PERIOD_BYTES = 14, PARAM_PERIODS = 15,
    PARAM_BUFFER_TIME = 16, PARAM_BUFFER_SIZE = 17, PARAM_BUFFER_BYTES = 18, PARAM_TICK_TIME = 19,
};

#define ACCESS_RW_INTERLEAVED 3
#define FORMAT_S16_LE 2
#define FORMAT_S32_LE 10

#define SNDRV_PCM_IOCTL_HW_PARAMS     _IOWR('A', 0x11, struct snd_pcm_hw_params)
#define SNDRV_PCM_IOCTL_DELAY         _IOR('A', 0x21, snd_pcm_sframes_t)
#define SNDRV_PCM_IOCTL_PREPARE       _IO('A', 0x40)
#define SNDRV_PCM_IOCTL_DROP          _IO('A', 0x43)
#define SNDRV_PCM_IOCTL_WRITEI_FRAMES _IOW('A', 0x50, struct snd_xferi)

static void hw_any(struct snd_pcm_hw_params *p) {
    memset(p, 0, sizeof(*p));
    for (int m = 0; m < 3; m++) memset(p->masks[m].bits, 0xff, sizeof(p->masks[m].bits));
    for (int i = 0; i < 12; i++) p->intervals[i].max = UINT_MAX;
    p->rmask = ~0u;
    p->info = ~0u;
}

static void hw_mask(struct snd_pcm_hw_params *p, int param, unsigned value) {
    struct snd_mask *m = &p->masks[param];
    memset(m->bits, 0, sizeof(m->bits));
    m->bits[value >> 5] |= 1u << (value & 31);
}

static void hw_set(struct snd_pcm_hw_params *p, int param, unsigned value) {
    struct snd_interval *i = &p->intervals[param - PARAM_FIRST_INTERVAL];
    i->min = i->max = value;
    i->integer = 1;
}

static unsigned hw_get(const struct snd_pcm_hw_params *p, int param) {
    return p->intervals[param - PARAM_FIRST_INTERVAL].min;
}

// ---------------------------------------------------------------- resampler

// Windowed-sinc (Kaiser, beta 9) with SINC_TAPS taps and SINC_PHASES precomputed
// fractional positions, linearly interpolated between. The cutoff follows the
// lower of the two rates, so downsampling does not alias. At the same rate the
// samples pass through.
#define SINC_TAPS 32
#define SINC_HALF (SINC_TAPS / 2)
#define SINC_PHASES 256
#define SINC_CUTOFF 0.42  // of the lower rate; the transition band ends near Nyquist
#define SINC_BETA 9.0

typedef struct {
    int identity;
    float coef[SINC_PHASES + 1][SINC_TAPS];  // tap k weighs source frame i - SINC_HALF + 1 + k
} sinc_t;

static double bessel_i0(double x) {
    double sum = 1, term = 1;
    for (int k = 1; k < 32; k++) {
        term *= (x / (2 * k)) * (x / (2 * k));
        sum += term;
    }
    return sum;
}

// `step` is source frames per output frame.
static void sinc_init(sinc_t *k, double step) {
    k->identity = step == 1.0;
    if (k->identity) return;
    double fc = SINC_CUTOFF * (step > 1 ? 1 / step : 1);  // cycles per source frame
    for (int p = 0; p <= SINC_PHASES; p++) {
        double t = (double)p / SINC_PHASES, sum = 0, h[SINC_TAPS];
        for (int j = 0; j < SINC_TAPS; j++) {
            double x = j - (SINC_HALF - 1) - t;
            double r = x / SINC_HALF;
            double w = r * r < 1 ? bessel_i0(SINC_BETA * sqrt(1 - r * r)) / bessel_i0(SINC_BETA) : 0;
            double y = 2 * fc * x;
            h[j] = 2 * fc * (y == 0 ? 1 : sin(M_PI * y) / (M_PI * y)) * w;
            sum += h[j];
        }
        for (int j = 0; j < SINC_TAPS; j++) k->coef[p][j] = (float)(h[j] / sum);  // unity gain at DC
    }
}

// The stereo sample at source position `pos`, from `src`: `len` frames of
// `channels` interleaved channels, `src` frame 0 being source frame `base`.
// Frames outside it count as silence.
static void sinc_sample(const sinc_t *k, const float *src, int64_t base, size_t len, int channels, double pos, float out[2]) {
    int64_t i = (int64_t)floor(pos);
    if (k->identity) {
        int64_t at = i - base;
        int inside = at >= 0 && at < (int64_t)len;
        out[0] = inside ? src[at * channels] : 0;
        out[1] = inside ? src[at * channels + (channels > 1)] : 0;
        return;
    }
    double phase = (pos - (double)i) * SINC_PHASES;
    int p = (int)phase;
    if (p >= SINC_PHASES) p = SINC_PHASES - 1;
    float frac = (float)(phase - p);
    const float *c0 = k->coef[p], *c1 = k->coef[p + 1];
    float l0 = 0, r0 = 0, l1 = 0, r1 = 0;
    int64_t first = i - (SINC_HALF - 1) - base;
    int j0 = first < 0 ? (int)-first : 0;
    int j1 = first + SINC_TAPS > (int64_t)len ? (int)((int64_t)len - first) : SINC_TAPS;
    for (int j = j0; j < j1; j++) {
        const float *f = src + (first + j) * channels;
        float l = f[0], r = f[channels > 1];
        l0 += c0[j] * l; r0 += c0[j] * r;
        l1 += c1[j] * l; r1 += c1[j] * r;
    }
    out[0] = l0 + (l1 - l0) * frac;
    out[1] = r0 + (r1 - r0) * frac;
}

// ---------------------------------------------------------------- mixer state

#define MAX_STEMS 8
#define WINDOW 2048  // decoded source frames kept per stem

typedef struct {
    uint8_t *data;
    decoder *dec;
    double step;          // source frames per output frame
    double pos;           // source frame position
    float window[WINDOW * 2];  // stereo frames [window_start, window_start + window_len)
    uint64_t window_start;
    size_t window_len;
    int decoded;          // the decoder has nothing more
    int eof;
    float gain;
    uint64_t frames;      // source frames in the stem
    unsigned hz;
    sinc_t sinc;
} stem_t;

#define MAX_SCHEDULED 32

typedef struct {
    float *samples;       // stereo at the device rate
    size_t frames, pos;
    size_t delay;         // frames into the next block before it starts
    int on;
    float gain;
} effect_t;

// Slower playback at the same pitch (WSOLA). The stems are mixed at their own
// speed into `in`; the output is built from overlapping Hann-windowed segments of
// it, one every STRETCH_HOP output frames, taken STRETCH_HOP * speed song frames
// apart. Each segment may move by up to STRETCH_SEEK frames to where it best
// continues the previous one, so the waveform stays smooth. At speed 1 the
// segments follow each other and the output is the input, sample for sample.
#define STRETCH_LEN 1024
#define STRETCH_HOP (STRETCH_LEN / 2)
#define STRETCH_SEEK 192
#define STRETCH_IN 4096   // song frames kept for the search

typedef struct {
    float in[STRETCH_IN * 2];  // mixed song frames [in_start, in_start + in_len)
    uint64_t in_start;
    size_t in_len;
    double next;          // nominal song frame of the next segment
    uint64_t cont;        // the song frame that continues the previous segment
    float acc[STRETCH_LEN * 2];  // overlap-add of the segments
    float out[STRETCH_HOP * 2];  // the hop being played
    double out_song[STRETCH_HOP];  // the nominal song frame of each of its frames
    size_t out_pos;       // STRETCH_HOP: the next hop is to be made
    int fresh;            // no segment yet
} stretch_t;

static float hann[STRETCH_LEN];

#define CLOCK_POINTS 64

struct cmpc_audio {
    int fd;
    unsigned rate, channels, format, period, periods;
    char description[96];

    pthread_t thread;
    pthread_mutex_t lock;
    int running;

    stem_t *stems[MAX_STEMS];
    int stem_count;
    int playing;
    float master;

    effect_t effects[CMPC_AUDIO_EFFECT_SLOTS];
    struct { int slot; uint64_t song_frame; } scheduled[MAX_SCHEDULED];
    int scheduled_count;

    double speed;         // song frames per output frame, 0.5-1
    stretch_t stretch;

    // Clock: frames written to the device, the song frame after the last frame
    // mixed, and which song frame went out at which device frame.
    uint64_t written;
    double song_out;
    struct { uint64_t device; double song; } points[CLOCK_POINTS];
    int point_head, point_count;
    double heard_song;    // last measured song frame being heard
    double heard_at;      // monotonic time of that measurement

    // Since the last `cmpc_audio_take_stats`: device underruns, and how long
    // mixing a period took.
    unsigned underruns;
    unsigned mixes;
    double mix_total, mix_longest;
};

static double now_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void set_err(char *err, size_t len, const char *fmt, ...) {
    if (!err || !len) return;
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(err, len, fmt, ap);
    va_end(ap);
}

// Decodes the next block of a stem into its window, keeping the last SINC_TAPS
// frames for the filter. Returns 0 at the end of the stem.
static int stem_refill(stem_t *s) {
    if (s->window_len > SINC_TAPS) {
        size_t drop = s->window_len - SINC_TAPS;
        memmove(s->window, s->window + drop * 2, SINC_TAPS * 2 * sizeof(float));
        s->window_start += drop;
        s->window_len = SINC_TAPS;
    }
    size_t want_frames = WINDOW - s->window_len;
    if (want_frames > 1152 * 2) want_frames = 1152 * 2;
    size_t got = decoder_read(s->dec, s->window + s->window_len * 2, want_frames);
    s->window_len += got;
    return got > 0;
}

// Adds `frames` output frames of the stem into `out` (stereo).
static void stem_mix(stem_t *s, float *out, size_t frames) {
    for (size_t f = 0; f < frames && !s->eof; f++) {
        // The filter reads up to SINC_HALF frames past the position.
        uint64_t need = (uint64_t)s->pos + SINC_HALF;
        while (!s->decoded && need >= s->window_start + s->window_len) {
            if (!stem_refill(s)) s->decoded = 1;
        }
        float v[2];
        sinc_sample(&s->sinc, s->window, (int64_t)s->window_start, s->window_len, 2, s->pos, v);
        out[f * 2] += s->gain * v[0];
        out[f * 2 + 1] += s->gain * v[1];
        s->pos += s->step;
        if (s->pos >= (double)s->frames) s->eof = 1;
    }
}

// ---------------------------------------------------------------- time stretch

static void stretch_reset(stretch_t *t) {
    memset(t, 0, sizeof(*t));
    t->out_pos = STRETCH_HOP;
    t->fresh = 1;
    if (hann[1] == 0) {
        // Periodic, so that two halves overlapping by STRETCH_HOP add up to 1.
        for (int i = 0; i < STRETCH_LEN; i++) hann[i] = (float)(0.5 - 0.5 * cos(2 * M_PI * i / STRETCH_LEN));
    }
}

// Mixes the stems on until song frame `end` is in the input, first dropping the
// frames before `keep`.
static void stretch_fill(cmpc_audio *a, uint64_t keep, uint64_t end) {
    stretch_t *t = &a->stretch;
    if (keep > t->in_start) {
        size_t drop = (size_t)(keep - t->in_start);
        if (drop > t->in_len) drop = t->in_len;
        memmove(t->in, t->in + drop * 2, (t->in_len - drop) * 2 * sizeof(float));
        t->in_start += drop;
        t->in_len -= drop;
    }
    while (t->in_start + t->in_len < end && t->in_len < STRETCH_IN) {
        size_t n = (size_t)(end - (t->in_start + t->in_len));
        if (n > STRETCH_IN - t->in_len) n = STRETCH_IN - t->in_len;
        float *dst = t->in + t->in_len * 2;
        memset(dst, 0, n * 2 * sizeof(float));
        for (int s = 0; s < a->stem_count; s++) stem_mix(a->stems[s], dst, n);
        t->in_len += n;
    }
}

// How well a segment starting at song frame `s` continues `ref` (the mono sum of
// the natural continuation, every second frame), reading every `every`-th value:
// normalised cross-correlation.
static double stretch_match(const stretch_t *t, uint64_t s, const float *ref, double ref_energy, size_t every) {
    const float *x = t->in + (s - t->in_start) * 2;
    float dot = 0, energy = 0;
    for (size_t i = 0; i < STRETCH_HOP / 2; i += every) {
        float v = x[i * 4] + x[i * 4 + 1];
        dot += v * ref[i];
        energy += v * v;
    }
    return energy > 1e-12f ? dot / sqrt((double)energy * ref_energy) : 0;
}

// The segment start in [lo, hi] whose first half best matches the natural
// continuation of the previous segment: first every fourth start on a quarter of
// the frames, then the starts around the best on all of them. The middle (the
// nominal start) in silence.
static uint64_t stretch_seek(const stretch_t *t, uint64_t lo, uint64_t hi) {
    float ref[STRETCH_HOP / 2];
    const float *c = t->in + (t->cont - t->in_start) * 2;
    double ref_energy = 0;
    for (size_t i = 0; i < STRETCH_HOP / 2; i++) {
        ref[i] = c[i * 4] + c[i * 4 + 1];
        ref_energy += (double)ref[i] * ref[i];
    }
    uint64_t best = (lo + hi) / 2;
    if (ref_energy < 1e-9) return best;
    double best_score = -2;
    for (uint64_t s = lo; s <= hi; s += 4) {
        double score = stretch_match(t, s, ref, ref_energy, 2);
        if (score > best_score) {
            best_score = score;
            best = s;
        }
    }
    uint64_t coarse = best;
    best_score = -2;
    for (uint64_t s = coarse > lo + 3 ? coarse - 3 : lo; s <= coarse + 3 && s <= hi; s++) {
        double score = stretch_match(t, s, ref, ref_energy, 1);
        if (score > best_score) {
            best_score = score;
            best = s;
        }
    }
    return best;
}

// Makes the next STRETCH_HOP output frames.
static void stretch_hop(cmpc_audio *a) {
    stretch_t *t = &a->stretch;
    uint64_t start;
    if (a->speed >= 1.0 || t->fresh) {
        // Segments one after the other: the input as it is, and the nominal
        // position back on it.
        start = t->cont;
        t->next = (double)start;
        // Keep what a slower next segment may search back to.
        stretch_fill(a, start > STRETCH_SEEK ? start - STRETCH_SEEK : 0, start + STRETCH_LEN);
    } else {
        uint64_t target = (uint64_t)(t->next + 0.5);
        uint64_t lo = target > STRETCH_SEEK ? target - STRETCH_SEEK : 0;
        uint64_t hi = target + STRETCH_SEEK;
        // Never before what is still in the input (nothing is mixed twice).
        if (lo < t->in_start) lo = t->in_start;
        if (hi < lo) hi = lo;
        stretch_fill(a, lo < t->cont ? lo : t->cont, hi + STRETCH_LEN);
        start = stretch_seek(t, lo, hi);
    }
    const float *x = t->in + (start - t->in_start) * 2;
    if (t->fresh) {
        // The second half of a segment before the first: the song starts at full level.
        for (size_t i = 0; i < STRETCH_HOP; i++) {
            t->acc[i * 2] = x[i * 2] * hann[STRETCH_HOP + i];
            t->acc[i * 2 + 1] = x[i * 2 + 1] * hann[STRETCH_HOP + i];
        }
        t->fresh = 0;
    }
    for (size_t i = 0; i < STRETCH_LEN; i++) {
        t->acc[i * 2] += x[i * 2] * hann[i];
        t->acc[i * 2 + 1] += x[i * 2 + 1] * hann[i];
    }
    memcpy(t->out, t->acc, STRETCH_HOP * 2 * sizeof(float));
    memmove(t->acc, t->acc + STRETCH_HOP * 2, STRETCH_HOP * 2 * sizeof(float));
    memset(t->acc + STRETCH_HOP * 2, 0, STRETCH_HOP * 2 * sizeof(float));
    for (size_t i = 0; i < STRETCH_HOP; i++) t->out_song[i] = t->next + i * a->speed;
    t->next += STRETCH_HOP * a->speed;
    t->cont = start + STRETCH_HOP;
    t->out_pos = 0;
}

static void stem_free(stem_t *s) {
    if (!s) return;
    decoder_close(s->dec);
    free(s->data);
    free(s);
}

// ---------------------------------------------------------------- device

static int pcm_setup(cmpc_audio *a, unsigned format, unsigned channels, unsigned period) {
    struct snd_pcm_hw_params p;
    hw_any(&p);
    hw_mask(&p, PARAM_ACCESS, ACCESS_RW_INTERLEAVED);
    hw_mask(&p, PARAM_FORMAT, format);
    hw_mask(&p, PARAM_SUBFORMAT, 0);
    hw_set(&p, PARAM_CHANNELS, channels);
    hw_set(&p, PARAM_RATE, 44100);
    hw_set(&p, PARAM_PERIOD_SIZE, period);
    hw_set(&p, PARAM_PERIODS, 4);
    if (ioctl(a->fd, SNDRV_PCM_IOCTL_HW_PARAMS, &p)) return -errno;
    a->format = format;
    a->channels = hw_get(&p, PARAM_CHANNELS);
    a->rate = hw_get(&p, PARAM_RATE);
    a->period = hw_get(&p, PARAM_PERIOD_SIZE);
    a->periods = hw_get(&p, PARAM_PERIODS);
    if (ioctl(a->fd, SNDRV_PCM_IOCTL_PREPARE)) return -errno;
    return 0;
}

static int find_card(void) {
    char link[256];
    ssize_t n = readlink("/dev/snd/by-path/platform-sound", link, sizeof(link) - 1);
    if (n > 0) {
        link[n] = 0;
        const char *c = strstr(link, "controlC");
        if (c) return atoi(c + 8);
    }
    return 0;
}

static void write_period(cmpc_audio *a, const float *mix, void *dev) {
    size_t frames = a->period;
    for (size_t f = 0; f < frames; f++) {
        for (unsigned ch = 0; ch < a->channels; ch++) {
            // Channels 3-4 (the second output pair) get the same mix as 1-2.
            float v = mix[f * 2 + (ch & 1)];
            if (v > 1.0f) v = 1.0f;
            if (v < -1.0f) v = -1.0f;
            if (a->format == FORMAT_S32_LE)
                ((int32_t *)dev)[f * a->channels + ch] = (int32_t)(v * 2147483520.0f);
            else
                ((int16_t *)dev)[f * a->channels + ch] = (int16_t)(v * 32767.0f);
        }
    }
    size_t done = 0;
    while (done < frames) {
        size_t bytes = a->format == FORMAT_S32_LE ? 4 : 2;
        struct snd_xferi x = {
            .buf = (char *)dev + done * a->channels * bytes,
            .frames = frames - done,
        };
        if (ioctl(a->fd, SNDRV_PCM_IOCTL_WRITEI_FRAMES, &x)) {
            if (errno == EINTR) continue;
#ifndef ESTRPIPE
#define ESTRPIPE EPIPE  // Linux only
#endif
            if (errno == EPIPE || errno == ESTRPIPE) {  // underrun: restart the stream
                pthread_mutex_lock(&a->lock);
                a->underruns++;
                pthread_mutex_unlock(&a->lock);
                ioctl(a->fd, SNDRV_PCM_IOCTL_PREPARE);
                continue;
            }
            usleep(10000);
            return;
        }
        done += x.result;
    }
}

// Notes that song frame `song` goes out at device frame `device`.
static void clock_point(cmpc_audio *a, uint64_t device, double song) {
    int i = (a->point_head + a->point_count) % CLOCK_POINTS;
    if (a->point_count < CLOCK_POINTS) {
        a->point_count++;
    } else {
        a->point_head = (a->point_head + 1) % CLOCK_POINTS;
    }
    a->points[i].device = device;
    a->points[i].song = song;
}

static void clock_reset(cmpc_audio *a) {
    a->song_out = 0;
    a->point_head = a->point_count = 0;
    a->heard_song = 0;
    a->heard_at = 0;
}

// Mixes one block of song stems and the effects into `mix` (stereo, zeroed here),
// in pieces of at most one stretch hop. Called with the lock held.
static void mix_locked(cmpc_audio *a, float *mix, size_t frames) {
    memset(mix, 0, frames * 2 * sizeof(float));
    double song[STRETCH_HOP];
    for (size_t done = 0; done < frames;) {
        size_t n = frames - done;
        if (n > STRETCH_HOP) n = STRETCH_HOP;
        float *m = mix + done * 2;
        clock_point(a, a->written + done, a->song_out);
        if (a->playing) {
            stretch_t *t = &a->stretch;
            for (size_t f = 0; f < n; f++) {
                if (t->out_pos == STRETCH_HOP) stretch_hop(a);
                m[f * 2] = t->out[t->out_pos * 2];
                m[f * 2 + 1] = t->out[t->out_pos * 2 + 1];
                song[f] = t->out_song[t->out_pos];
                t->out_pos++;
            }
            a->song_out = t->out_pos < STRETCH_HOP ? t->out_song[t->out_pos] : t->next;
            // Start the scheduled effects that fall into this piece, at their frame.
            for (int i = 0; i < a->scheduled_count;) {
                double at = (double)a->scheduled[i].song_frame;
                if (at < a->song_out) {
                    size_t f = 0;
                    while (f + 1 < n && song[f] < at) f++;
                    effect_t *e = &a->effects[a->scheduled[i].slot];
                    e->delay = f;
                    e->pos = 0;
                    e->on = 1;
                    a->scheduled[i] = a->scheduled[--a->scheduled_count];
                } else {
                    i++;
                }
            }
        }
        for (int slot = 0; slot < CMPC_AUDIO_EFFECT_SLOTS; slot++) {
            effect_t *e = &a->effects[slot];
            if (!e->on || !e->samples) continue;
            for (size_t f = e->delay; f < n && e->pos < e->frames; f++, e->pos++) {
                m[f * 2] += e->gain * e->samples[e->pos * 2];
                m[f * 2 + 1] += e->gain * e->samples[e->pos * 2 + 1];
            }
            e->delay = 0;
            if (e->pos >= e->frames) e->on = 0;
        }
        done += n;
    }
    clock_point(a, a->written + frames, a->song_out);
    for (size_t i = 0; i < frames * 2; i++) mix[i] *= a->master;
}

// After `frames` more device frames were written, with `delay` frames still queued
// in the device: which song frame is being heard now, between the points noted
// while mixing. Called with the lock held.
static void advance_clock_locked(cmpc_audio *a, size_t frames, uint64_t delay) {
    a->written += frames;
    if (a->point_count == 0) return;
    uint64_t heard = a->written > delay ? a->written - delay : 0;
    double song = a->points[a->point_head].song;
    for (int k = a->point_count - 1; k >= 0; k--) {
        int i = (a->point_head + k) % CLOCK_POINTS;
        if (a->points[i].device > heard) continue;
        song = a->points[i].song;
        if (k + 1 < a->point_count) {
            int j = (a->point_head + k + 1) % CLOCK_POINTS;
            uint64_t span = a->points[j].device - a->points[i].device;
            if (span > 0) song += (a->points[j].song - a->points[i].song) * (double)(heard - a->points[i].device) / span;
        }
        break;
    }
    a->heard_song = song;
    a->heard_at = now_sec();
}

static void *mixer_thread(void *arg) {
    cmpc_audio *a = arg;
    float *mix = malloc(a->period * 2 * sizeof(float));
    void *dev = malloc(a->period * a->channels * 4);

    struct sched_param sp = { .sched_priority = 70 };
    pthread_setschedparam(pthread_self(), SCHED_FIFO, &sp);  // best effort

    while (1) {
        pthread_mutex_lock(&a->lock);
        if (!a->running) {
            pthread_mutex_unlock(&a->lock);
            break;
        }
        double began = now_sec();
        mix_locked(a, mix, a->period);
        double took = now_sec() - began;
        a->mixes++;
        a->mix_total += took;
        if (took > a->mix_longest) a->mix_longest = took;
        pthread_mutex_unlock(&a->lock);

        write_period(a, mix, dev);

        snd_pcm_sframes_t delay = 0;
        if (ioctl(a->fd, SNDRV_PCM_IOCTL_DELAY, &delay) || delay < 0) delay = 0;
        pthread_mutex_lock(&a->lock);
        advance_clock_locked(a, a->period, (uint64_t)delay);
        pthread_mutex_unlock(&a->lock);
    }
    free(mix);
    free(dev);
    return NULL;
}

// ---------------------------------------------------------------- API

cmpc_audio *cmpc_audio_open(char *err, size_t err_len) {
    char path[64];
    snprintf(path, sizeof(path), "/dev/snd/pcmC%dD0p", find_card());
    int fd = open(path, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        set_err(err, err_len, "open %s: %s", path, strerror(errno));
        return NULL;
    }
    cmpc_audio *a = calloc(1, sizeof(*a));
    a->fd = fd;
    // The stock app's setup first, then simpler ones.
    static const unsigned tries[][3] = {
        { FORMAT_S32_LE, 4, 512 }, { FORMAT_S32_LE, 4, 1024 }, { FORMAT_S32_LE, 2, 512 },
        { FORMAT_S16_LE, 2, 512 }, { FORMAT_S16_LE, 2, 1024 },
    };
    int rc = -EINVAL;
    for (size_t i = 0; i < sizeof(tries) / sizeof(tries[0]); i++) {
        rc = pcm_setup(a, tries[i][0], tries[i][1], tries[i][2]);
        if (rc == 0) break;
    }
    if (rc) {
        set_err(err, err_len, "%s: no usable format (%s)", path, strerror(-rc));
        close(fd);
        free(a);
        return NULL;
    }
    snprintf(a->description, sizeof(a->description), "%s %uch %s %u Hz, period %u x %u", path, a->channels,
             a->format == FORMAT_S32_LE ? "S32_LE" : "S16_LE", a->rate, a->period, a->periods);
    a->master = 1.0f;
    for (int slot = 0; slot < CMPC_AUDIO_EFFECT_SLOTS; slot++) a->effects[slot].gain = 1.0f;
    a->speed = 1.0;
    stretch_reset(&a->stretch);
    pthread_mutex_init(&a->lock, NULL);
    a->running = 1;
    if (pthread_create(&a->thread, NULL, mixer_thread, a)) {
        set_err(err, err_len, "mixer thread: %s", strerror(errno));
        close(fd);
        free(a);
        return NULL;
    }
    return a;
}

cmpc_audio *cmpc_audio_open_offline(unsigned rate) {
    cmpc_audio *a = calloc(1, sizeof(*a));
    a->fd = -1;
    a->rate = rate;
    a->channels = 2;
    snprintf(a->description, sizeof(a->description), "offline %u Hz", rate);
    a->master = 1.0f;
    for (int slot = 0; slot < CMPC_AUDIO_EFFECT_SLOTS; slot++) a->effects[slot].gain = 1.0f;
    a->speed = 1.0;
    stretch_reset(&a->stretch);
    pthread_mutex_init(&a->lock, NULL);
    return a;
}

void cmpc_audio_render(cmpc_audio *a, float *out, size_t frames) {
    pthread_mutex_lock(&a->lock);
    mix_locked(a, out, frames);
    advance_clock_locked(a, frames, 0);
    pthread_mutex_unlock(&a->lock);
}

void cmpc_audio_close(cmpc_audio *a) {
    if (!a) return;
    if (a->fd >= 0) {
        pthread_mutex_lock(&a->lock);
        a->running = 0;
        pthread_mutex_unlock(&a->lock);
        pthread_join(a->thread, NULL);
        ioctl(a->fd, SNDRV_PCM_IOCTL_DROP);
        close(a->fd);
    }
    for (int s = 0; s < a->stem_count; s++) stem_free(a->stems[s]);
    for (int slot = 0; slot < CMPC_AUDIO_EFFECT_SLOTS; slot++) free(a->effects[slot].samples);
    pthread_mutex_destroy(&a->lock);
    free(a);
}

const char *cmpc_audio_describe(const cmpc_audio *a) { return a->description; }

int cmpc_audio_add_stem(cmpc_audio *a, const uint8_t *data, size_t len, char *err, size_t err_len) {
    stem_t *s = calloc(1, sizeof(*s));
    s->data = malloc(len ? len : 1);
    memcpy(s->data, data, len);
    // Opening scans the whole file (MP3 frames, the Ogg end); done outside the lock.
    s->dec = decoder_open(s->data, len, err, err_len);
    if (!s->dec) {
        stem_free(s);
        return -1;
    }
    s->hz = decoder_hz(s->dec);
    s->frames = decoder_frames(s->dec);
    s->step = (double)s->hz / a->rate;
    sinc_init(&s->sinc, s->step);
    s->gain = 1.0f;

    pthread_mutex_lock(&a->lock);
    int index = -1;
    if (a->stem_count < MAX_STEMS) {
        index = a->stem_count;
        a->stems[a->stem_count++] = s;
    }
    pthread_mutex_unlock(&a->lock);
    if (index < 0) {
        set_err(err, err_len, "more than %d stems", MAX_STEMS);
        stem_free(s);
    }
    return index;
}

void cmpc_audio_clear_stems(cmpc_audio *a) {
    stem_t *old[MAX_STEMS];
    pthread_mutex_lock(&a->lock);
    int count = a->stem_count;
    memcpy(old, a->stems, sizeof(old));
    a->stem_count = 0;
    a->scheduled_count = 0;
    a->playing = 0;
    stretch_reset(&a->stretch);
    clock_reset(a);
    pthread_mutex_unlock(&a->lock);
    for (int s = 0; s < count; s++) stem_free(old[s]);
}

void cmpc_audio_rewind(cmpc_audio *a) {
    pthread_mutex_lock(&a->lock);
    for (int s = 0; s < a->stem_count; s++) {
        stem_t *stem = a->stems[s];
        decoder_rewind(stem->dec);
        stem->pos = 0;
        stem->window_start = 0;
        stem->window_len = 0;
        stem->decoded = 0;
        stem->eof = 0;
    }
    a->playing = 0;
    a->scheduled_count = 0;
    stretch_reset(&a->stretch);
    clock_reset(a);
    pthread_mutex_unlock(&a->lock);
}

void cmpc_audio_set_stem_gain(cmpc_audio *a, int stem, float gain) {
    pthread_mutex_lock(&a->lock);
    if (stem >= 0 && stem < a->stem_count) a->stems[stem]->gain = gain;
    pthread_mutex_unlock(&a->lock);
}

void cmpc_audio_play(cmpc_audio *a) {
    pthread_mutex_lock(&a->lock);
    a->playing = 1;
    pthread_mutex_unlock(&a->lock);
}

void cmpc_audio_pause(cmpc_audio *a) {
    pthread_mutex_lock(&a->lock);
    a->playing = 0;
    pthread_mutex_unlock(&a->lock);
}

double cmpc_audio_position(cmpc_audio *a) {
    pthread_mutex_lock(&a->lock);
    double pos = a->heard_song / a->rate;
    // Between device writes, run on with the wall clock while playing, but never
    // past what has been mixed.
    if (a->playing && a->heard_at > 0) {
        pos += (now_sec() - a->heard_at) * a->speed;
        double mixed = a->song_out / a->rate;
        if (pos > mixed) pos = mixed;
    }
    pthread_mutex_unlock(&a->lock);
    return pos;
}

double cmpc_audio_duration(cmpc_audio *a) {
    double longest = 0;
    pthread_mutex_lock(&a->lock);
    for (int s = 0; s < a->stem_count; s++) {
        double d = (double)a->stems[s]->frames / a->stems[s]->hz;
        if (d > longest) longest = d;
    }
    pthread_mutex_unlock(&a->lock);
    return longest;
}

int cmpc_audio_finished(cmpc_audio *a) {
    pthread_mutex_lock(&a->lock);
    int done = a->stem_count > 0;
    for (int s = 0; s < a->stem_count; s++) done = done && a->stems[s]->eof;
    pthread_mutex_unlock(&a->lock);
    return done;
}

// Resamples mono or interleaved stereo `src` (at `hz`) to stereo at the device rate.
static float *to_device_stereo(const cmpc_audio *a, const float *src, size_t src_frames, int channels, unsigned hz, size_t *out_frames) {
    size_t frames = (size_t)((double)src_frames * a->rate / hz);
    float *out = malloc((frames ? frames : 1) * 2 * sizeof(float));
    sinc_t *k = malloc(sizeof(*k));
    sinc_init(k, (double)hz / a->rate);
    for (size_t f = 0; f < frames; f++) {
        sinc_sample(k, src, 0, src_frames, channels, (double)f * hz / a->rate, out + f * 2);
    }
    free(k);
    *out_frames = frames;
    return out;
}

static void set_effect(cmpc_audio *a, int slot, float *samples, size_t frames) {
    pthread_mutex_lock(&a->lock);
    effect_t *e = &a->effects[slot];
    float *old = e->samples;
    e->samples = samples;
    e->frames = frames;
    e->on = 0;
    pthread_mutex_unlock(&a->lock);
    free(old);
}

static int valid_slot(int slot) {
    return slot >= 0 && slot < CMPC_AUDIO_EFFECT_SLOTS;
}

int cmpc_audio_load_effect(cmpc_audio *a, int slot, const uint8_t *data, size_t len) {
    if (!valid_slot(slot)) return -1;
    decoder *dec = decoder_open(data, len, NULL, 0);
    if (!dec) return -1;
    unsigned hz = decoder_hz(dec);
    size_t total = (size_t)decoder_frames(dec);
    float *pcm = malloc(total * 2 * sizeof(float));
    size_t frames = pcm ? decoder_read(dec, pcm, total) : 0;
    decoder_close(dec);
    if (frames == 0) {
        free(pcm);
        return -1;
    }
    size_t out_frames;
    float *out = to_device_stereo(a, pcm, frames, 2, hz, &out_frames);
    free(pcm);
    set_effect(a, slot, out, out_frames);
    return 0;
}

int cmpc_audio_load_effect_samples(cmpc_audio *a, int slot, const float *samples, size_t count, unsigned rate) {
    if (!valid_slot(slot) || !samples || count == 0 || rate == 0) return -1;
    size_t frames;
    float *out = to_device_stereo(a, samples, count, 1, rate, &frames);
    set_effect(a, slot, out, frames);
    return 0;
}

void cmpc_audio_set_effect_gain(cmpc_audio *a, int slot, float gain) {
    if (!valid_slot(slot)) return;
    pthread_mutex_lock(&a->lock);
    a->effects[slot].gain = gain;
    pthread_mutex_unlock(&a->lock);
}

void cmpc_audio_trigger_effect(cmpc_audio *a, int slot) {
    if (!valid_slot(slot)) return;
    pthread_mutex_lock(&a->lock);
    a->effects[slot].pos = 0;
    a->effects[slot].delay = 0;
    a->effects[slot].on = 1;
    pthread_mutex_unlock(&a->lock);
}

void cmpc_audio_schedule_effect(cmpc_audio *a, int slot, double song_sec) {
    if (!valid_slot(slot) || song_sec < 0) return;
    pthread_mutex_lock(&a->lock);
    if (a->scheduled_count < MAX_SCHEDULED) {
        a->scheduled[a->scheduled_count].slot = slot;
        a->scheduled[a->scheduled_count].song_frame = (uint64_t)(song_sec * a->rate + 0.5);
        a->scheduled_count++;
    }
    pthread_mutex_unlock(&a->lock);
}

void cmpc_audio_set_speed(cmpc_audio *a, double speed) {
    pthread_mutex_lock(&a->lock);
    a->speed = speed < 0.5 ? 0.5 : (speed > 1 ? 1 : speed);
    pthread_mutex_unlock(&a->lock);
}

double cmpc_audio_speed(cmpc_audio *a) {
    pthread_mutex_lock(&a->lock);
    double speed = a->speed;
    pthread_mutex_unlock(&a->lock);
    return speed;
}

void cmpc_audio_take_stats(cmpc_audio *a, unsigned *underruns, double *mix_average, double *mix_longest) {
    pthread_mutex_lock(&a->lock);
    *underruns = a->underruns;
    *mix_average = a->mixes ? a->mix_total / a->mixes : 0;
    *mix_longest = a->mix_longest;
    a->underruns = a->mixes = 0;
    a->mix_total = a->mix_longest = 0;
    pthread_mutex_unlock(&a->lock);
}

void cmpc_audio_set_master(cmpc_audio *a, float gain) {
    pthread_mutex_lock(&a->lock);
    a->master = gain < 0 ? 0 : (gain > 1 ? 1 : gain);
    pthread_mutex_unlock(&a->lock);
}
