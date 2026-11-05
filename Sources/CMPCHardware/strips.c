// Which parts of a frame changed, strip by strip: what `cmpc_display_present_strips`
// sends. Pure, so the tests run it off the device.

#include "cmpc_display.h"

size_t cmpc_changed_strips(const uint32_t *old, const uint32_t *now, uint32_t width, uint32_t height,
                           uint32_t strip, int columns, cmpc_rect *out, size_t max) {
    size_t count = 0;
    uint32_t length = columns ? width : height;
    for (uint32_t s0 = 0; s0 < length && count < max; s0 += strip) {
        uint32_t s1 = s0 + strip < length ? s0 + strip : length;
        // The changed part of this strip, across it.
        uint32_t lo = UINT32_MAX, hi = 0;
        for (uint32_t y = columns ? 0 : s0; y < (columns ? height : s1); y++) {
            const uint32_t *a = old + (size_t)y * width, *b = now + (size_t)y * width;
            uint32_t x0 = columns ? s0 : 0, x1 = columns ? s1 : width;
            while (x0 < x1 && a[x0] == b[x0]) x0++;
            while (x1 > x0 && a[x1 - 1] == b[x1 - 1]) x1--;
            if (x0 == x1) continue;
            if (columns) {
                // Across a column strip is down the frame: the changed rows.
                if (lo == UINT32_MAX) lo = y;
                hi = y + 1;
            } else {
                if (x0 < lo) lo = x0;
                if (x1 > hi) hi = x1;
            }
        }
        if (lo == UINT32_MAX) continue;
        out[count++] = columns ? (cmpc_rect){ s0, lo, s1, hi } : (cmpc_rect){ lo, s0, hi, s1 };
    }
    return count;
}
