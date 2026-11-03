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

void cmpc_display_close(cmpc_display *display);

#endif
