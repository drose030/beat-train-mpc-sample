#!/usr/bin/env python3
"""Extracts the partitions from an inMusic AZ0x firmware update image
(e.g. Update.img inside "MPC Sample 1.3.0 Updater.app") into the layout the
virtual-mpc-sample lab expects:

    OUT/extracted/part1   boot partition   (PART "boot")
    OUT/extracted/part2   rootfs           (PART "rootfs")
    OUT/extracted/parr    recovery         (PARR "recovery")
    OUT/Firmware/MPCSAMPLE-<version>-update.img   copy of the image

Usage: extract-az0x.py UPDATE_IMG OUT_DIR [VERSION]   (VERSION default 1.3.0.12)

Format (reverse-engineered from 1.3.0.12): "AZ0x" header, string table at 0x38,
entry table at 0x90 with 0x40-byte entries:
    4s tag, u32 compressed (1 = xz), u64 offset, u64 size, u64 name (string
    table offset), 32 bytes SHA-256 of the stored (compressed) blob.
Each blob's SHA-256 is checked before it is unpacked.
"""
import hashlib
import lzma
import os
import shutil
import struct
import sys

STRING_TABLE = 0x38
ENTRY_TABLE = 0x90
ENTRY_SIZE = 0x40
TARGETS = {("PART", "boot"): "part1", ("PART", "rootfs"): "part2", ("PARR", "recovery"): "parr"}


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    img_path, out_dir = sys.argv[1], sys.argv[2]
    version = sys.argv[3] if len(sys.argv) == 4 else "1.3.0.12"

    with open(img_path, "rb") as f:
        img = f.read()
    if img[:4] != b"AZ0x":
        sys.exit("not an AZ0x image")

    def string(offset):
        start = STRING_TABLE + offset
        return img[start:img.index(b"\0", start)].decode()

    os.makedirs(os.path.join(out_dir, "extracted"), exist_ok=True)
    found = set()
    pos = ENTRY_TABLE
    while img[pos:pos + 4] in (b"BOOT", b"PART", b"PARR"):
        tag, compressed, offset, size, name = struct.unpack_from("<4sIQQQ", img, pos)
        digest = img[pos + 0x20:pos + 0x40]
        pos += ENTRY_SIZE
        tag, label = tag.decode(), string(name)
        blob = img[offset:offset + size]
        if hashlib.sha256(blob).digest() != digest:
            sys.exit(f"{tag} {label}: SHA-256 mismatch, image damaged")
        target = TARGETS.get((tag, label))
        if target is None:
            print(f"skip {tag} {label!r} ({size} bytes)")
            continue
        data = lzma.decompress(blob) if compressed == 1 else blob
        out = os.path.join(out_dir, "extracted", target)
        with open(out, "wb") as f:
            f.write(data)
        found.add(target)
        print(f"{tag} {label!r} -> {out} ({len(data)} bytes)")

    missing = set(TARGETS.values()) - found
    if missing:
        sys.exit(f"missing partitions: {sorted(missing)}")

    fw = os.path.join(out_dir, "Firmware")
    os.makedirs(fw, exist_ok=True)
    shutil.copyfile(img_path, os.path.join(fw, f"MPCSAMPLE-{version}-update.img"))


if __name__ == "__main__":
    main()
