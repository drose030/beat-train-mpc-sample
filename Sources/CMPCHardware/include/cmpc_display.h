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

/// Like `cmpc_display_present`, but sends only what changed, in vertical strips
/// `strip` pixels wide, left to right, each as its own update of the shown buffer.
/// On an SPI panel a frame takes longer to send than the panel takes to refresh, so
/// it shows part old, part new frame: sent row by row, the line between them is
/// horizontal and cuts sideways-moving things in two; sent in strips it is
/// (nearly) vertical. Falls back to `cmpc_display_present` on drivers without
/// damage clips. Returns 0 or a negative errno.
int cmpc_display_present_columns(cmpc_display *display, const uint32_t *pixels, uint32_t strip);

void cmpc_display_close(cmpc_display *display);

#endif
