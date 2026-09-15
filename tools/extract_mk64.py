#!/usr/bin/env python3
"""Read what the Mario Kart demo needs out of your own copy of Mario Kart 64.

The demo in ``addons/gta/mk/scenes/demo.tscn`` runs without this script.
Its kart physics are ported from the public
`mk64 decompilation <https://github.com/n64decomp/mk64>`_, which publishes the
numbers as source, and its course and karts are the addon's own work. One thing
is genuinely missing, and this script is for that one thing: the item
probability curves.

Mario Kart 64 does not roll weighted dice for items. It keeps a flat hundred
entry table per finishing position and reads whatever is sitting at the index
its rolling counter lands on, so the odds for a position *are* that table. The
decomp names the symbol, ``common_grand_prix_human_item_curve``, but never
defines it: the data is reached through a segment pointer and lives in the ROM
rather than in the source. So it cannot be shipped, and without it
``MkItems`` falls back to an even spread that the HUD labels as not the real
odds.

Run this against a ROM you own::

    python tools/extract_mk64.py "Mario Kart 64 (U) [!].z64"

What it writes goes to ``addons/gta/mk/assets/``, which is git-ignored,
exactly as ``tools/extract_tm2.py`` treats the files it pulls off a Twisted
Metal 2 disc: the converted result is yours, built from your own copy, and is
not redistributed by this repository.

A note on what this currently finds, so nobody repeats the search by hand. On
the US ROM neither the item curves nor the course vertex arrays are stored in
the clear. Scanning the whole 12 MB for a run of at least four hundred bytes
that are all valid item ids finds nothing, and matching the decomp's own
published Luigi Raceway vertices against the ROM as packed big endian shorts
finds nothing either. Both therefore sit behind the game's segment and
compression scheme rather than being addressable directly, and resolving that
is a larger job than this script. Decompressing every MIO0 block in the ROM and
searching those is implemented below and does run, so if the tables are in one
this will find them; on the US ROM it reports that they are not. It says so and
writes nothing rather than inventing a table, which is the same rule the
constants in ``MkConst`` follow.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys
from pathlib import Path

# The three builds the decompilation supports, by the SHA1 of the ROM itself.
KNOWN_ROMS = {
    "579c48e211ae952530ffc8738709f078d5dd215e": "Mario Kart 64 (USA)",
    "a729039453210b84f17019dda3f248d5888f7690": "Mario Kart 64 (Europe) v1.0",
    "f6b5f519dd57ea59e9f013cc64816e9d273b2329": "Mario Kart 64 (Europe) v1.1",
}

ITEM_COUNT = 16      # ITEM_NONE through ITEM_SUPER_MUSHROOM
CURVE_LENGTH = 100   # entries per finishing position, from gen_random_item
RACERS = 8           # NUM_PLAYERS

# What separates a real roulette table from smooth data that happens to be in
# range. See looks_like_curves for why each of these is here.
MIN_MEAN_STEP = 2.0       # average jump between neighbouring entries
MIN_ITEMS_PER_ROW = 4     # different items available at one finishing position
MAX_CONSTANT_RUN = 20     # longest stretch of one repeated item within a row

OUT_DIR = Path("addons/gta/mk/assets")
OUT_FILE = OUT_DIR / "item_curves.tres"


def sha1_of(path: Path) -> str:
    digest = hashlib.sha1()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def byteswap_if_needed(data: bytes) -> bytes:
    """Return the ROM in big endian z64 order, whatever order it arrived in."""
    if data[:4] == b"\x80\x37\x12\x40":
        return data
    if data[:4] == b"\x37\x80\x40\x12":  # v64, byte swapped pairs
        out = bytearray(len(data))
        out[0::2] = data[1::2]
        out[1::2] = data[0::2]
        return bytes(out)
    if data[:4] == b"\x40\x12\x37\x80":  # n64, word swapped
        out = bytearray(len(data))
        for i in range(0, len(data) - 3, 4):
            out[i:i + 4] = data[i:i + 4][::-1]
        return bytes(out)
    return data


def mio0_decompress(buf: bytes, off: int) -> bytes | None:
    """Decompress the MIO0 block at *off*, or None if it is not one.

    MIO0 is the compression the game uses for most of its bulk data. A block is
    a header, a run of layout bits, a section of literal bytes and a section of
    back references; a set bit takes the next literal, a clear bit takes a two
    byte back reference of a length and a distance.
    """
    if buf[off:off + 4] != b"MIO0":
        return None
    try:
        size, comp_off, raw_off = struct.unpack_from(">III", buf, off + 4)
    except struct.error:
        return None
    if size == 0 or size > 8 * 1024 * 1024:
        return None
    out = bytearray()
    layout, comp, raw = off + 16, off + comp_off, off + raw_off
    bits = 0
    current = 0
    try:
        while len(out) < size:
            if bits == 0:
                current = buf[layout]
                layout += 1
                bits = 8
            bits -= 1
            if current & (1 << bits):
                out.append(buf[raw])
                raw += 1
            else:
                first, second = buf[comp], buf[comp + 1]
                comp += 2
                length = (first >> 4) + 3
                distance = (((first & 0xF) << 8) | second) + 1
                if distance > len(out):
                    return None
                for _ in range(length):
                    out.append(out[-distance])
    except IndexError:
        return None
    return bytes(out)


def looks_like_curves(chunk: bytes) -> bool:
    """Whether *chunk* could be a run of per position item tables.

    Every byte has to be a valid item id, and almost all of them have to be
    something rather than nothing, since a table of mostly ITEM_NONE would be a
    box that usually gives you nothing.

    The rest of the test is there to reject smooth data, and it is not
    theoretical: the ROM contains long stretches of gently rising bytes, and a
    looser version of this function matched one of them and cheerfully wrote it
    out as the item odds. A ramp like 0,0,0,1,1,1,2,2 satisfies every test about
    ranges and distributions while being obviously not a roulette. What
    separates them is that consecutive entries in a real table jump about, since
    the game's rolling index lands anywhere in the hundred, whereas a ramp barely
    moves. So each row has to carry several different items, must not be one long
    constant run, and the average step between neighbours has to be a real jump.
    """
    if len(chunk) < CURVE_LENGTH * RACERS:
        return False
    if any(b >= ITEM_COUNT for b in chunk):
        return False
    body = chunk[:CURVE_LENGTH * RACERS]
    if sum(1 for b in body if b != 0) < len(body) * 0.8:
        return False

    steps = [abs(body[i + 1] - body[i]) for i in range(len(body) - 1)]
    if sum(steps) / len(steps) < MIN_MEAN_STEP:
        return False

    rows = [body[r * CURVE_LENGTH:(r + 1) * CURVE_LENGTH] for r in range(RACERS)]
    for row in rows:
        if len(set(row)) < MIN_ITEMS_PER_ROW:
            return False
        longest = best = 1
        for i in range(1, len(row)):
            longest = longest + 1 if row[i] == row[i - 1] else 1
            best = max(best, longest)
        if best > MAX_CONSTANT_RUN:
            return False
    # and the leader's chances must not be the back marker's
    return set(rows[0]) != set(rows[-1])


def find_curves(rom: bytes) -> tuple[int, bytes] | None:
    """Look for the item tables, in the clear and inside every MIO0 block."""
    span = CURVE_LENGTH * RACERS

    def scan(buf: bytes, label: str) -> tuple[str, bytes] | None:
        start = None
        for i, byte in enumerate(buf):
            if byte < ITEM_COUNT:
                if start is None:
                    start = i
                continue
            if start is not None and i - start >= span:
                for base in range(start, i - span + 1):
                    if looks_like_curves(buf[base:base + span]):
                        return (f"{label}+0x{base:X}", buf[base:base + span])
            start = None
        if start is not None and len(buf) - start >= span:
            for base in range(start, len(buf) - span + 1):
                if looks_like_curves(buf[base:base + span]):
                    return (f"{label}+0x{base:X}", buf[base:base + span])
        return None

    hit = scan(rom, "rom")
    if hit:
        return hit

    blocks = []
    index = 0
    while True:
        index = rom.find(b"MIO0", index)
        if index < 0:
            break
        blocks.append(index)
        index += 4
    print(f"  not in the clear; searching {len(blocks)} MIO0 blocks")
    for offset in blocks:
        decoded = mio0_decompress(rom, offset)
        if not decoded:
            continue
        hit = scan(decoded, f"mio0@0x{offset:X}")
        if hit:
            return hit
    return None


def write_resource(curves: bytes, source_sha1: str, where: str, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    values = ", ".join(str(b) for b in curves)
    out.write_text(
        '[gd_resource type="Resource" script_class="MkItemCurves" load_steps=2 format=3]\n'
        '\n'
        '[ext_resource type="Script"'
        ' path="res://addons/gta/mk/scripts/mk_item_curves.gd" id="1_curves"]\n'
        '\n'
        '[resource]\n'
        'script = ExtResource("1_curves")\n'
        f'curves = PackedInt32Array({values})\n'
        'mode = &"grand_prix_human"\n'
        f'positions = {RACERS}\n'
        f'source_sha1 = "{source_sha1}"\n',
        encoding="utf-8",
    )
    print(f"  wrote {out} from {where}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("rom", type=Path, help="your own Mario Kart 64 ROM (.z64, .v64 or .n64)")
    parser.add_argument("--out", type=Path, default=OUT_FILE,
                        help=f"where to write the curves (default {OUT_FILE})")
    args = parser.parse_args()

    if not args.rom.is_file():
        print(f"no such ROM: {args.rom}", file=sys.stderr)
        return 2

    digest = sha1_of(args.rom)
    name = KNOWN_ROMS.get(digest)
    print(f"ROM {args.rom.name}")
    print(f"  sha1 {digest}")
    if name:
        print(f"  recognised as {name}")
    else:
        print("  not one of the three builds the decompilation knows, carrying on anyway")

    rom = byteswap_if_needed(args.rom.read_bytes())
    print("searching for the item probability curves")
    found = find_curves(rom)
    if not found:
        print()
        print("The item curves were not found in this ROM.")
        print("They are reached through a segment pointer rather than stored in the clear,")
        print("and they are not inside any MIO0 block either, so locating them needs the")
        print("game's segment tables resolved. Nothing has been written: the demo keeps its")
        print("placeholder spread, which the HUD labels as not the real odds, rather than")
        print("being given a made up table.")
        return 1

    where, curves = found
    write_resource(curves, digest, where, args.out)
    print("done. The demo will use the real odds from now on.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
