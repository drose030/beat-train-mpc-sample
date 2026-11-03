// struct and ioctl from the stable ALSA uapi <sound/asound.h> (kernel >= 5.14 has
// the `mode` field), declared here so the build does not need kernel headers.

#include "cmpc_rawmidi.h"

#include <errno.h>
#include <stddef.h>
#include <sys/ioctl.h>

struct snd_rawmidi_params {
    int stream;
    size_t buffer_size;
    size_t avail_min;
    unsigned int no_active_sensing : 1;
    unsigned int mode;
    unsigned char reserved[12];
};

#define SNDRV_RAWMIDI_STREAM_INPUT  1
#define SNDRV_RAWMIDI_IOCTL_PARAMS  _IOWR('W', 0x10, struct snd_rawmidi_params)

int cmpc_rawmidi_set_byte_mode(int fd) {
    struct snd_rawmidi_params params = {
        .stream = SNDRV_RAWMIDI_STREAM_INPUT,
        .buffer_size = 4096,
        .avail_min = 1,
        .mode = 0,  // no framing, no timestamps
    };
    return ioctl(fd, SNDRV_RAWMIDI_IOCTL_PARAMS, &params) ? -errno : 0;
}
