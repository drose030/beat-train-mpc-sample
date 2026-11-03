#ifndef CMPC_RAWMIDI_H
#define CMPC_RAWMIDI_H

/// Puts the input side of an open rawmidi device into plain byte mode. The stock
/// app switches the panel to timestamped framing (32-byte frames per byte), and
/// that setting outlives its process. Returns 0 or a negative errno.
int cmpc_rawmidi_set_byte_mode(int fd);

#endif
