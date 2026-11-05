// Which song frame is being heard: see cmpc_heard_clock.h.

#include "cmpc_heard_clock.h"

#include <stdlib.h>

#define POINTS 64

struct cmpc_heard_clock {
    struct { uint64_t device; double song; } points[POINTS];
    int head, count;
    double heard_song;    // last measured song frame being heard
    double heard_at;      // monotonic time of that measurement
};

cmpc_heard_clock *cmpc_heard_clock_new(void) {
    return calloc(1, sizeof(cmpc_heard_clock));
}

void cmpc_heard_clock_free(cmpc_heard_clock *c) {
    free(c);
}

void cmpc_heard_clock_reset(cmpc_heard_clock *c) {
    c->head = c->count = 0;
    c->heard_song = 0;
    c->heard_at = 0;
}

void cmpc_heard_clock_note(cmpc_heard_clock *c, uint64_t device, double song) {
    int i = (c->head + c->count) % POINTS;
    if (c->count < POINTS) {
        c->count++;
    } else {
        c->head = (c->head + 1) % POINTS;
    }
    c->points[i].device = device;
    c->points[i].song = song;
}

void cmpc_heard_clock_hear(cmpc_heard_clock *c, uint64_t heard, double at) {
    if (c->count == 0) return;
    double song = c->points[c->head].song;
    for (int k = c->count - 1; k >= 0; k--) {
        int i = (c->head + k) % POINTS;
        if (c->points[i].device > heard) continue;
        song = c->points[i].song;
        if (k + 1 < c->count) {
            int j = (c->head + k + 1) % POINTS;
            uint64_t span = c->points[j].device - c->points[i].device;
            if (span > 0) song += (c->points[j].song - c->points[i].song) * (double)(heard - c->points[i].device) / span;
        }
        break;
    }
    c->heard_song = song;
    c->heard_at = at;
}

double cmpc_heard_clock_song_frame(const cmpc_heard_clock *c, double now, double speed, double mixed) {
    double song = c->heard_song;
    if (speed > 0 && c->heard_at > 0) {
        song += (now - c->heard_at) * speed;
        if (song > mixed) song = mixed;
    }
    return song;
}
