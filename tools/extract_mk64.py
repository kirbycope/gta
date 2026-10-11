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
decomp names the symbols, ``common_grand_prix_human_item_curve`` and so on, but
its source never defines them: the data is reached through a segment pointer
and lives in the ROM rather than in the source. So it cannot be shipped, and
without it ``MkItems`` falls back to an even spread that the HUD labels as not
the real odds.

Run this against a ROM you own::

    python tools/extract_mk64.py "Mario Kart 64 (U) [!].z64"

What it writes goes to ``addons/gta/mk/assets/``, which is git-ignored,
exactly as ``tools/extract_tm2.py`` treats the files it pulls off a Twisted
Metal 2 disc: the converted result is yours, built from your own copy, and is
not redistributed by this repository.

Where the tables are. The decomp's asset description for the US build,
``yamls/us/common_data.yml``, declares segment ``0x0D`` as the MIO0 block at
ROM offset ``0x132B50`` (the same offset is segment 13 of the list in its
``config.yml``), and lists every curve as a ``mk64:item_curve`` entry with its
offset inside the decompressed segment: the eight grand prix human tables from
``0x8150``, a hundred bytes apart, then the eight CPU ones, the versus tables
for two, three and four players, and the single battle table at ``0x8B14``.
``gen_random_item`` in ``src/update_objects.c`` reads
``curve[rank * 100 + sRandomItemIndex]`` from the first of a mode's symbols, so
a mode's tables are one contiguous run of hundreds, which is how
``MkItemCurves`` stores them.

So the extraction is: decompress that one MIO0 block, slice the tables out at
the decomp's offsets, and check they are what they claim to be. Each table has
to be a hundred valid item ids, and the grand prix human tables have to show
the shape the game is known for, a leader who never sees a star, a thunderbolt
or a blue shell and a back marker who sees all three.

A note on why an earlier version of this script missed them, so nobody repeats
the search. It scanned the ROM and every MIO0 block for something that looked
like a shuffled roulette: several items per row, no long constant run, big
jumps between neighbours. The real tables are the opposite. Each hundred is
sorted, thirty bananas in a row followed by five bunches and so on, because the
rolling index does the shuffling at run time, so a filter that rejects long
constant runs rejects the genuine article. That scan is still here as the last
resort for a ROM whose segment layout is not the one the decomp describes, and
it still writes nothing rather than inventing a table, which is the same rule
the constants in ``MkConst`` follow.
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

# include/defines.h's ITEM_ enum, by id, for the histogram this prints.
ITEM_NAMES = [
    "ITEM_NONE", "ITEM_BANANA", "ITEM_BANANA_BUNCH", "ITEM_GREEN_SHELL",
    "ITEM_TRIPLE_GREEN_SHELL", "ITEM_RED_SHELL", "ITEM_TRIPLE_RED_SHELL",
    "ITEM_BLUE_SPINY_SHELL", "ITEM_THUNDERBOLT", "ITEM_FAKE_ITEM_BOX", "ITEM_STAR",
    "ITEM_BOO", "ITEM_MUSHROOM", "ITEM_DOUBLE_MUSHROOM", "ITEM_TRIPLE_MUSHROOM",
    "ITEM_SUPER_MUSHROOM",
]
ITEM_BANANA = 1
ITEM_BLUE_SPINY_SHELL = 7
ITEM_THUNDERBOLT = 8
ITEM_STAR = 10

# Segment 0x0D, the common data, on the US build: ``yamls/us/common_data.yml``
# ``segments: [0x0D, 0x132B50]`` and ``config.yml``'s segment list.
COMMON_DATA_ROM_OFFSET = 0x132B50

# Each mode's tables inside the decompressed segment, from the ``mk64:item_curve``
# entries in ``yamls/us/common_data.yml``: the offset of the first position's
# hundred and how many positions follow it back to back.
CURVE_TABLES = {
    "grand_prix_human": (0x8150, 8),
    "grand_prix_cpu": (0x8470, 8),
    "versus_2_player": (0x8790, 2),
    "versus_3_player": (0x8858, 3),
    "versus_4_player": (0x8984, 4),
    "battle": (0x8B14, 1),
}
# The one MkItems loads; the rest go beside it named by mode.
MAIN_MODE = "grand_prix_human"

# What separates a real roulette table from smooth data that happens to be in
# range, for the last resort scan. See looks_like_curves for why each is here.
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


def mio0_offsets(rom: bytes) -> list[int]:
    blocks = []
    index = 0
    while True:
        index = rom.find(b"MIO0", index)
        if index < 0:
            return blocks
        blocks.append(index)
        index += 4


def is_item_table(row: bytes) -> bool:
    """A hundred valid item ids that are not all nothing."""
    return (len(row) == CURVE_LENGTH
            and all(b < ITEM_COUNT for b in row)
            and any(b != 0 for b in row))


def read_curve_tables(segment: bytes) -> dict[str, bytes] | None:
    """Slice every mode's tables out of a decompressed common data segment.

    Returns None unless every table is a valid item table and the grand prix
    human tables have the shape the game is known for: a leader who is never
    handed a star, a thunderbolt or a blue shell, and a back marker who is handed
    all three and never a single banana. That is the check that this really is
    the common data segment rather than some other block that happens to hold
    small numbers at these offsets.
    """
    tables: dict[str, bytes] = {}
    for mode, (offset, positions) in CURVE_TABLES.items():
        span = CURVE_LENGTH * positions
        if offset + span > len(segment):
            return None
        chunk = segment[offset:offset + span]
        rows = [chunk[r * CURVE_LENGTH:(r + 1) * CURVE_LENGTH] for r in range(positions)]
        if not all(is_item_table(row) for row in rows):
            return None
        tables[mode] = chunk

    human = tables[MAIN_MODE]
    leader = human[:CURVE_LENGTH]
    last = human[(RACERS - 1) * CURVE_LENGTH:RACERS * CURVE_LENGTH]
    heavy = {ITEM_STAR, ITEM_THUNDERBOLT, ITEM_BLUE_SPINY_SHELL}
    if heavy & set(leader):
        return None
    if not heavy <= set(last) or ITEM_BANANA in last:
        return None
    return tables


def find_curve_tables(rom: bytes) -> tuple[str, dict[str, bytes]] | None:
    """The tables at the decomp's offsets, from the segment it names first.

    The US build's common data is the MIO0 block at COMMON_DATA_ROM_OFFSET. A
    build that keeps it elsewhere is covered by trying every MIO0 block in the
    ROM against the same in-segment layout, since the segment's contents do not
    move between builds the way its ROM address might.
    """
    candidates = [COMMON_DATA_ROM_OFFSET]
    candidates += [off for off in mio0_offsets(rom) if off != COMMON_DATA_ROM_OFFSET]
    for offset in candidates:
        segment = mio0_decompress(rom, offset)
        if not segment:
            continue
        tables = read_curve_tables(segment)
        if tables:
            where = f"mio0@0x{offset:X}"
            if offset == COMMON_DATA_ROM_OFFSET:
                where += " (segment 0x0D, common data)"
            return where, tables
    return None


def looks_like_curves(chunk: bytes) -> bool:
    """Whether *chunk* could be a run of per position item tables, for the
    last resort scan.

    Every byte has to be a valid item id, and almost all of them have to be
    something rather than nothing, since a table of mostly ITEM_NONE would be a
    box that usually gives you nothing.

    The rest of the test is there to reject smooth data, and it is not
    theoretical: the ROM contains long stretches of gently rising bytes, and a
    looser version of this function matched one of them and cheerfully wrote it
    out as the item odds. A ramp like 0,0,0,1,1,1,2,2 satisfies every test about
    ranges and distributions while being obviously not a roulette. Note that the
    real tables are sorted runs and fail this test too, which is why the segment
    path above exists; this scan only matters for a build laid out differently.
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


def find_curves(rom: bytes) -> tuple[str, bytes] | None:
    """Last resort: look for a shuffled table in the clear and inside every
    MIO0 block."""
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

    blocks = mio0_offsets(rom)
    print(f"  not in the clear; searching {len(blocks)} MIO0 blocks")
    for offset in blocks:
        decoded = mio0_decompress(rom, offset)
        if not decoded:
            continue
        hit = scan(decoded, f"mio0@0x{offset:X}")
        if hit:
            return hit
    return None


def histogram(row: bytes) -> str:
    counts: dict[int, int] = {}
    for item in row:
        counts[item] = counts.get(item, 0) + 1
    return ", ".join(f"{ITEM_NAMES[item]} {count}" for item, count in sorted(counts.items()))


def write_resource(curves: bytes, mode: str, positions: int, source_sha1: str,
                   where: str, out: Path) -> None:
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
        f'mode = &"{mode}"\n'
        f'positions = {positions}\n'
        f'source_sha1 = "{source_sha1}"\n',
        encoding="utf-8",
    )
    print(f"  wrote {out} from {where}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("rom", type=Path, help="your own Mario Kart 64 ROM (.z64, .v64 or .n64)")
    parser.add_argument("--out", type=Path, default=OUT_FILE,
                        help=f"where to write the grand prix curves (default {OUT_FILE});"
                             " the other modes go beside it, named by mode")
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
    print("reading the item probability curves out of the common data segment")
    found = find_curve_tables(rom)
    if found:
        where, tables = found
        print(f"  found at {where}")
        for mode, chunk in tables.items():
            positions = CURVE_TABLES[mode][1]
            print(f"  {mode}, {positions} position(s):")
            for rank in range(positions):
                row = chunk[rank * CURVE_LENGTH:(rank + 1) * CURVE_LENGTH]
                print(f"    {rank + 1}: {histogram(row)}")
            out = args.out if mode == MAIN_MODE else args.out.with_name(
                f"{args.out.stem}_{mode}{args.out.suffix}")
            write_resource(chunk, mode, positions, digest, where, out)
        print("done. The demo will use the real odds from now on.")
        return 0

    print("  not at the decomp's offsets in any MIO0 block; scanning for a shuffled table")
    scanned = find_curves(rom)
    if not scanned:
        print()
        print("The item curves were not found in this ROM.")
        print("They are not where the decompilation's yaml places them in the common data")
        print("segment, and no MIO0 block or stretch of the ROM looks like a table either.")
        print("Nothing has been written: the demo keeps its placeholder spread, which the")
        print("HUD labels as not the real odds, rather than being given a made up table.")
        return 1

    where, curves = scanned
    write_resource(curves, MAIN_MODE, RACERS, digest, where, args.out)
    print("done. The demo will use the real odds from now on.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
