#ifndef CMPC_HEARD_CLOCK_H
#define CMPC_HEARD_CLOCK_H

#include <stdint.h>

/// Which song frame is being heard. The mixer notes which song frame goes out at
/// which device frame; the device says how far it has played; between two
/// notes the song frame is interpolated, and between two device reports it runs
/// on with the wall clock.
typedef struct cmpc_heard_clock cmpc_heard_clock;

cmpc_heard_clock *cmpc_heard_clock_new(void);
void cmpc_heard_clock_free(cmpc_heard_clock *clock);
/// Nothing heard yet: song frame 0.
void cmpc_heard_clock_reset(cmpc_heard_clock *clock);

/// Song frame `song` goes out at device frame `device` (in rising order; the
/// last 64 are kept).
void cmpc_heard_clock_note(cmpc_heard_clock *clock, uint64_t device, double song);
/// Device frame `device` is being heard at monotonic time `at`.
void cmpc_heard_clock_hear(cmpc_heard_clock *clock, uint64_t device, double at);
/// The song frame heard at monotonic time `now`: the last heard one, run on at
/// `speed` song frames per second while playing (`speed` 0: not), never past
/// `mixed`.
double cmpc_heard_clock_song_frame(const cmpc_heard_clock *clock, double now, double speed, double mixed);

#endif
