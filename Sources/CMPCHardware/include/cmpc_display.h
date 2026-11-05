#ifndef CMPC_DISPLAY_H
#define CMPC_DISPLAY_H

#include <stddef.h>
#include <stdint.h>

/// A KMS scanout on a DRM device, driven with two dumb buffers and page flips
/// (software rendering, no GPU) — the same path the stock MPC Sample app uses.
typedef struct cmpc_display cmpc_display;

/// Opens `path` (e.g. "/dev/dri/card0"), picks the first connected connector and
/// its preferred mode, and shows a black frame. On failure returns NULL and writes
/// a message into `err`.
cmpc_display *cmpc_display_open(const char *path, char *err, size_t err_len);

uint32_t cmpc_display_width(const cmpc_display *display);
uint32_t cmpc_display_height(const cmpc_display *display);

/// Copies a `width`×`height` XRGB8888 frame (row stride = width) into the back
/// buffer and flips it to the screen. Blocks until the flip completed, at most
/// ~100 ms. Returns 0 or a negative errno.
int cmpc_display_present(cmpc_display *display, const uint32_t *pixels);

/// Like `cmpc_display_present`, but sends only what changed, in strips `strip`
/// pixels wide (`columns`, left to right) or tall (rows, top to bottom), each as
/// its own update of the shown buffer. On an SPI panel a frame takes longer to send
/// than the panel takes to refresh, so it shows part old, part new frame; the line
/// between them runs across the strips' order. Rows suit things that move up and
/// down, columns things that move sideways. Falls back to `cmpc_display_present`
/// on drivers without damage clips. Returns 0 or a negative errno.
int cmpc_display_present_strips(cmpc_display *display, const uint32_t *pixels, uint32_t strip, int columns);

void cmpc_display_close(cmpc_display *display);

/// A rectangle of a frame, from (`x0`, `y0`) to before (`x1`, `y1`).
typedef struct {
    uint32_t x0, y0, x1, y1;
} cmpc_rect;

/// What `cmpc_display_present_strips` sends when `old` is on screen and `now` is
/// to be: per strip (as there) the smallest rectangle around what changed in it,
/// strips without changes left out, in sending order. Both frames are
/// `width`×`height` with row stride `width`. Writes at most `max` rectangles to
/// `out` and returns how many.
size_t cmpc_changed_strips(const uint32_t *old, const uint32_t *now, uint32_t width, uint32_t height,
                           uint32_t strip, int columns, cmpc_rect *out, size_t max);

#endif
