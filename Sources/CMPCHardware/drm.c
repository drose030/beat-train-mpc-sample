// Minimal DRM/KMS client. The uapi structs and ioctl numbers below are the
// stable kernel ABI from <drm/drm.h> and <drm/drm_mode.h>, declared here so the
// build does not depend on kernel headers in the SDK.

#include "cmpc_display.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

struct drm_mode_card_res {
    uint64_t fb_id_ptr, crtc_id_ptr, connector_id_ptr, encoder_id_ptr;
    uint32_t count_fbs, count_crtcs, count_connectors, count_encoders;
    uint32_t min_width, max_width, min_height, max_height;
};

struct drm_mode_modeinfo {
    uint32_t clock;
    uint16_t hdisplay, hsync_start, hsync_end, htotal, hskew;
    uint16_t vdisplay, vsync_start, vsync_end, vtotal, vscan;
    uint32_t vrefresh, flags, type;
    char name[32];
};

struct drm_mode_get_connector {
    uint64_t encoders_ptr, modes_ptr, props_ptr, prop_values_ptr;
    uint32_t count_modes, count_props, count_encoders;
    uint32_t encoder_id, connector_id, connector_type, connector_type_id;
    uint32_t connection, mm_width, mm_height, subpixel, pad;
};

struct drm_mode_get_encoder {
    uint32_t encoder_id, encoder_type, crtc_id, possible_crtcs, possible_clones;
};

struct drm_mode_crtc {
    uint64_t set_connectors_ptr;
    uint32_t count_connectors, crtc_id, fb_id, x, y, gamma_size, mode_valid;
    struct drm_mode_modeinfo mode;
};

struct drm_mode_fb_cmd {
    uint32_t fb_id, width, height, pitch, bpp, depth, handle;
};

struct drm_mode_create_dumb {
    uint32_t height, width, bpp, flags, handle, pitch;
    uint64_t size;
};

struct drm_mode_map_dumb {
    uint32_t handle, pad;
    uint64_t offset;
};

struct drm_mode_destroy_dumb {
    uint32_t handle;
};

struct drm_mode_crtc_page_flip {
    uint32_t crtc_id, fb_id, flags, reserved;
    uint64_t user_data;
};

struct drm_mode_fb_dirty_cmd {
    uint32_t fb_id, flags, color, num_clips;
    uint64_t clips_ptr;
};

struct drm_event {
    uint32_t type, length;
};

#define DRM_IOCTL_SET_MASTER         _IO('d', 0x1e)
#define DRM_IOCTL_MODE_GETRESOURCES  _IOWR('d', 0xA0, struct drm_mode_card_res)
#define DRM_IOCTL_MODE_SETCRTC       _IOWR('d', 0xA2, struct drm_mode_crtc)
#define DRM_IOCTL_MODE_GETENCODER    _IOWR('d', 0xA6, struct drm_mode_get_encoder)
#define DRM_IOCTL_MODE_GETCONNECTOR  _IOWR('d', 0xA7, struct drm_mode_get_connector)
#define DRM_IOCTL_MODE_ADDFB         _IOWR('d', 0xAE, struct drm_mode_fb_cmd)
#define DRM_IOCTL_MODE_RMFB          _IOWR('d', 0xAF, unsigned int)
#define DRM_IOCTL_MODE_PAGE_FLIP     _IOWR('d', 0xB0, struct drm_mode_crtc_page_flip)
#define DRM_IOCTL_MODE_DIRTYFB       _IOWR('d', 0xB1, struct drm_mode_fb_dirty_cmd)
#define DRM_IOCTL_MODE_CREATE_DUMB   _IOWR('d', 0xB2, struct drm_mode_create_dumb)
#define DRM_IOCTL_MODE_MAP_DUMB      _IOWR('d', 0xB3, struct drm_mode_map_dumb)
#define DRM_IOCTL_MODE_DESTROY_DUMB  _IOWR('d', 0xB4, struct drm_mode_destroy_dumb)

#define DRM_MODE_CONNECTED        1
#define DRM_MODE_TYPE_PREFERRED   (1 << 3)
#define DRM_MODE_PAGE_FLIP_EVENT  0x01
#define DRM_EVENT_FLIP_COMPLETE   0x02

struct buffer {
    uint32_t handle, fb_id, pitch;
    uint64_t size;
    uint8_t *map;
};

struct cmpc_display {
    int fd;
    uint32_t width, height, crtc_id;
    struct buffer buffers[2];
    int front;           // index of the buffer on screen
    int use_page_flip;   // falls back to DIRTYFB on drivers without flips
};

static int xioctl(int fd, unsigned long request, void *arg) {
    int rc;
    do {
        rc = ioctl(fd, request, arg);
    } while (rc == -1 && (errno == EINTR || errno == EAGAIN));
    return rc;
}

static void set_err(char *err, size_t len, const char *fmt, ...) {
    if (!err || len == 0) return;
    va_list args;
    va_start(args, fmt);
    vsnprintf(err, len, fmt, args);
    va_end(args);
}

static int create_buffer(int fd, uint32_t w, uint32_t h, struct buffer *buf) {
    struct drm_mode_create_dumb create = { .height = h, .width = w, .bpp = 32 };
    if (xioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create)) return -errno;
    buf->handle = create.handle;
    buf->pitch = create.pitch;
    buf->size = create.size;

    struct drm_mode_fb_cmd fb = {
        .width = w, .height = h, .pitch = create.pitch, .bpp = 32, .depth = 24,
        .handle = create.handle,
    };
    if (xioctl(fd, DRM_IOCTL_MODE_ADDFB, &fb)) return -errno;
    buf->fb_id = fb.fb_id;

    struct drm_mode_map_dumb map = { .handle = create.handle };
    if (xioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &map)) return -errno;
    void *ptr = mmap(NULL, create.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)map.offset);
    if (ptr == MAP_FAILED) return -errno;
    buf->map = ptr;
    memset(buf->map, 0, buf->size);
    return 0;
}

static void destroy_buffer(int fd, struct buffer *buf) {
    if (buf->map) munmap(buf->map, buf->size);
    if (buf->fb_id) xioctl(fd, DRM_IOCTL_MODE_RMFB, &buf->fb_id);
    if (buf->handle) {
        struct drm_mode_destroy_dumb destroy = { .handle = buf->handle };
        xioctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy);
    }
    memset(buf, 0, sizeof(*buf));
}

// Finds a connected connector, its preferred mode and a CRTC that can drive it.
static int pick_output(int fd, uint32_t *conn_id, struct drm_mode_modeinfo *mode,
                       uint32_t *crtc_id, char *err, size_t err_len) {
    struct drm_mode_card_res res = {0};
    if (xioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res)) {
        set_err(err, err_len, "GETRESOURCES failed: %s", strerror(errno));
        return -1;
    }
    uint32_t *crtcs = calloc(res.count_crtcs + 1, sizeof(uint32_t));
    uint32_t *conns = calloc(res.count_connectors + 1, sizeof(uint32_t));
    uint32_t *encs = calloc(res.count_encoders + 1, sizeof(uint32_t));
    res.count_fbs = 0;
    res.fb_id_ptr = 0;
    res.crtc_id_ptr = (uint64_t)(uintptr_t)crtcs;
    res.connector_id_ptr = (uint64_t)(uintptr_t)conns;
    res.encoder_id_ptr = (uint64_t)(uintptr_t)encs;
    int found = -1;
    if (xioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res)) {
        set_err(err, err_len, "GETRESOURCES failed: %s", strerror(errno));
        goto out;
    }

    for (uint32_t i = 0; i < res.count_connectors && found != 0; i++) {
        struct drm_mode_get_connector conn = { .connector_id = conns[i] };
        if (xioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn)) continue;
        if (conn.connection != DRM_MODE_CONNECTED || conn.count_modes == 0) continue;

        struct drm_mode_modeinfo *modes = calloc(conn.count_modes, sizeof(*modes));
        uint32_t *conn_encs = calloc(conn.count_encoders + 1, sizeof(uint32_t));
        conn.modes_ptr = (uint64_t)(uintptr_t)modes;
        conn.encoders_ptr = (uint64_t)(uintptr_t)conn_encs;
        conn.count_props = 0;
        conn.props_ptr = 0;
        conn.prop_values_ptr = 0;
        if (xioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &conn) == 0 && conn.count_modes > 0) {
            *mode = modes[0];
            for (uint32_t m = 0; m < conn.count_modes; m++) {
                if (modes[m].type & DRM_MODE_TYPE_PREFERRED) { *mode = modes[m]; break; }
            }
            uint32_t crtc = 0;
            if (conn.encoder_id) {
                struct drm_mode_get_encoder enc = { .encoder_id = conn.encoder_id };
                if (xioctl(fd, DRM_IOCTL_MODE_GETENCODER, &enc) == 0) crtc = enc.crtc_id;
            }
            for (uint32_t e = 0; e < conn.count_encoders && crtc == 0; e++) {
                struct drm_mode_get_encoder enc = { .encoder_id = conn_encs[e] };
                if (xioctl(fd, DRM_IOCTL_MODE_GETENCODER, &enc)) continue;
                for (uint32_t c = 0; c < res.count_crtcs; c++) {
                    if (enc.possible_crtcs & (1u << c)) { crtc = crtcs[c]; break; }
                }
            }
            if (crtc) {
                *conn_id = conn.connector_id;
                *crtc_id = crtc;
                found = 0;
            }
        }
        free(modes);
        free(conn_encs);
    }
    if (found) set_err(err, err_len, "no connected display with a usable CRTC");
out:
    free(crtcs);
    free(conns);
    free(encs);
    return found;
}

cmpc_display *cmpc_display_open(const char *path, char *err, size_t err_len) {
    int fd = open(path, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        set_err(err, err_len, "open %s: %s", path, strerror(errno));
        return NULL;
    }
    // Only fails when another master holds the device; SETCRTC then reports it.
    xioctl(fd, DRM_IOCTL_SET_MASTER, NULL);

    uint32_t conn_id = 0, crtc_id = 0;
    struct drm_mode_modeinfo mode;
    if (pick_output(fd, &conn_id, &mode, &crtc_id, err, err_len)) {
        close(fd);
        return NULL;
    }

    cmpc_display *d = calloc(1, sizeof(*d));
    d->fd = fd;
    d->width = mode.hdisplay;
    d->height = mode.vdisplay;
    d->crtc_id = crtc_id;
    d->use_page_flip = 1;
    for (int i = 0; i < 2; i++) {
        int rc = create_buffer(fd, d->width, d->height, &d->buffers[i]);
        if (rc) {
            set_err(err, err_len, "dumb buffer %dx%d: %s", d->width, d->height, strerror(-rc));
            cmpc_display_close(d);
            return NULL;
        }
    }

    struct drm_mode_crtc crtc = {
        .set_connectors_ptr = (uint64_t)(uintptr_t)&conn_id,
        .count_connectors = 1,
        .crtc_id = crtc_id,
        .fb_id = d->buffers[0].fb_id,
        .mode_valid = 1,
        .mode = mode,
    };
    if (xioctl(fd, DRM_IOCTL_MODE_SETCRTC, &crtc)) {
        set_err(err, err_len, "SETCRTC failed: %s (is another app on the display?)", strerror(errno));
        cmpc_display_close(d);
        return NULL;
    }
    d->front = 0;
    return d;
}

uint32_t cmpc_display_width(const cmpc_display *d) { return d->width; }
uint32_t cmpc_display_height(const cmpc_display *d) { return d->height; }

static void copy_frame(const cmpc_display *d, struct buffer *buf, const uint32_t *pixels) {
    size_t row = (size_t)d->width * 4;
    for (uint32_t y = 0; y < d->height; y++) {
        memcpy(buf->map + (size_t)y * buf->pitch, pixels + (size_t)y * d->width, row);
    }
}

static int wait_for_flip(int fd) {
    struct pollfd pfd = { .fd = fd, .events = POLLIN };
    for (;;) {
        int rc = poll(&pfd, 1, 100);
        if (rc == 0) return -ETIMEDOUT;
        if (rc < 0) {
            if (errno == EINTR) continue;
            return -errno;
        }
        char events[1024];
        ssize_t len = read(fd, events, sizeof(events));
        if (len < 0) return -errno;
        for (ssize_t off = 0; off + (ssize_t)sizeof(struct drm_event) <= len;) {
            struct drm_event *ev = (struct drm_event *)(events + off);
            if (ev->type == DRM_EVENT_FLIP_COMPLETE) return 0;
            if (ev->length == 0) break;
            off += ev->length;
        }
    }
}

int cmpc_display_present(cmpc_display *d, const uint32_t *pixels) {
    if (d->use_page_flip) {
        int back = 1 - d->front;
        copy_frame(d, &d->buffers[back], pixels);
        struct drm_mode_crtc_page_flip flip = {
            .crtc_id = d->crtc_id,
            .fb_id = d->buffers[back].fb_id,
            .flags = DRM_MODE_PAGE_FLIP_EVENT,
        };
        if (xioctl(d->fd, DRM_IOCTL_MODE_PAGE_FLIP, &flip) == 0) {
            d->front = back;
            return wait_for_flip(d->fd);
        }
        if (errno == EBUSY) return -EBUSY;
        d->use_page_flip = 0;
    }
    // Single buffer: write into the scanout buffer and mark it dirty, so that
    // drivers for SPI panels push the new pixels out.
    struct buffer *front = &d->buffers[d->front];
    copy_frame(d, front, pixels);
    struct drm_mode_fb_dirty_cmd dirty = { .fb_id = front->fb_id };
    if (xioctl(d->fd, DRM_IOCTL_MODE_DIRTYFB, &dirty) && errno != ENOSYS && errno != EINVAL) {
        return -errno;
    }
    return 0;
}

void cmpc_display_close(cmpc_display *d) {
    if (!d) return;
    for (int i = 0; i < 2; i++) destroy_buffer(d->fd, &d->buffers[i]);
    close(d->fd);
    free(d);
}
