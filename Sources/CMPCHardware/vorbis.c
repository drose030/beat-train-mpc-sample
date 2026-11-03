// stb_vorbis on its own: its internals (get_bits…) clash with minimp3's.

#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_PUSHDATA_API
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#include "stb_vorbis/stb_vorbis.h"
#pragma clang diagnostic pop
