// Slower playback at the same pitch (WSOLA): see cmpc_stretch.h.

#include "cmpc_stretch.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

// The song is read from the source at its own speed into `in`; the output is built
// from overlapping Hann-windowed segments of it, one every STRETCH_HOP output
// frames, taken STRETCH_HOP * speed song frames apart. Each segment may move by up
// to STRETCH_SEEK frames to where it best continues the previous one. At speed 1
// the segments follow each other and the output is the input, sample for sample.
#define STRETCH_LEN 1024
#define STRETCH_HOP (STRETCH_LEN / 2)
#define STRETCH_SEEK 192
#define STRETCH_IN 4096   // song frames kept for the search

struct cmpc_stretch {
    cmpc_stretch_source source;
    void *context;
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
};

typedef cmpc_stretch stretch_t;

static float hann[STRETCH_LEN];

void cmpc_stretch_reset(stretch_t *t) {
    cmpc_stretch_source source = t->source;
    void *context = t->context;
    memset(t, 0, sizeof(*t));
    t->source = source;
    t->context = context;
    t->out_pos = STRETCH_HOP;
    t->fresh = 1;
    if (hann[1] == 0) {
        // Periodic, so that two halves overlapping by STRETCH_HOP add up to 1.
        for (int i = 0; i < STRETCH_LEN; i++) hann[i] = (float)(0.5 - 0.5 * cos(2 * M_PI * i / STRETCH_LEN));
    }
}

// Reads the song on until song frame `end` is in the input, first dropping the
// frames before `keep`.
static void stretch_fill(stretch_t *t, uint64_t keep, uint64_t end) {
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
        t->source(t->context, dst, n);
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
static void stretch_hop(stretch_t *t, double speed) {
    uint64_t start;
    if (speed >= 1.0 || t->fresh) {
        // Segments one after the other: the input as it is, and the nominal
        // position back on it.
        start = t->cont;
        t->next = (double)start;
        // Keep what a slower next segment may search back to.
        stretch_fill(t, start > STRETCH_SEEK ? start - STRETCH_SEEK : 0, start + STRETCH_LEN);
    } else {
        uint64_t target = (uint64_t)(t->next + 0.5);
        uint64_t lo = target > STRETCH_SEEK ? target - STRETCH_SEEK : 0;
        uint64_t hi = target + STRETCH_SEEK;
        // Never before what is still in the input (nothing is mixed twice).
        if (lo < t->in_start) lo = t->in_start;
        if (hi < lo) hi = lo;
        stretch_fill(t, lo < t->cont ? lo : t->cont, hi + STRETCH_LEN);
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
    for (size_t i = 0; i < STRETCH_HOP; i++) t->out_song[i] = t->next + i * speed;
    t->next += STRETCH_HOP * speed;
    t->cont = start + STRETCH_HOP;
    t->out_pos = 0;
}

cmpc_stretch *cmpc_stretch_new(cmpc_stretch_source source, void *context) {
    stretch_t *t = calloc(1, sizeof(*t));
    if (!t) return NULL;
    t->source = source;
    t->context = context;
    cmpc_stretch_reset(t);
    return t;
}

void cmpc_stretch_free(cmpc_stretch *t) {
    free(t);
}

void cmpc_stretch_render(stretch_t *t, double speed, float *out, double *song, size_t frames) {
    for (size_t f = 0; f < frames; f++) {
        if (t->out_pos == STRETCH_HOP) stretch_hop(t, speed);
        out[f * 2] = t->out[t->out_pos * 2];
        out[f * 2 + 1] = t->out[t->out_pos * 2 + 1];
        if (song) song[f] = t->out_song[t->out_pos];
        t->out_pos++;
    }
}

double cmpc_stretch_position(const stretch_t *t) {
    return t->out_pos < STRETCH_HOP ? t->out_song[t->out_pos] : t->next;
}
