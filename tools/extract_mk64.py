#!/usr/bin/env python3
"""Read what the Mario Kart demo needs out of your own copy of Mario Kart 64.

The demo in ``addons/gta/mk/scenes/demo.tscn`` runs without this script.
Its kart physics are ported from the public
`mk64 decompilation <https://github.com/n64decomp/mk64>`_, which publishes the
numbers as source, and its course and karts are the addon's own work. Two
things are genuinely the game's own data and this script reads them: the item
probability curves, and the kart sprites, the 64x64 frames the game billboards
for each character (written to ``addons/gta/mk/assets/karts/<character>/``
with a ``manifest.json`` each and a ``roster.json`` seating the demo's drivers;
the comment above ``KART_SEGMENT_ROM_OFFSET`` says where they are and how the
game picks one). First, the curves.

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
KARTS_DIR = OUT_DIR / "karts"

# ---------------------------------------------------------------------------
# The kart sprites.
#
# Every kart on screen is a billboard: a 64x64 CI8 frame (8 bit indices into a
# 256 colour RGBA16 palette), chosen by the angle between the camera and the
# kart, and drawn mirrored for one half of the circle. The frames live in the
# ``kart_textures`` segment, ``mk64.ld`` line 486, ROM 0x145470 to 0x63E278,
# one character after another in the order of the ``.o`` files listed there:
# ``data/karts/luigi_kart.s``, mario, yoshi, peach, wario, toad, donkeykong,
# bowser. Each of those ``.s`` files is the same shape, 321 ``.incbin`` MIO0
# frames ``gKart<Name>000`` to ``320`` (4 byte aligned), then 289 x 4 wheel
# palettes ``gKart<Name>NNNWheel0..3`` of 0x80 bytes, then the character's
# palette ``gKart<Name>Palette`` of 0x180 bytes; the segment's ``SUBALIGN(0x10)``
# pads each character to 16 bytes. So the whole segment can be walked block by
# block without a table of offsets, and the walk is checked against the
# addresses the decomp's ``assets/karts/<name>_kart.json`` publishes.
#
# How a frame becomes pixels. ``render_kart`` (``src/render_player.c`` 1426)
# loads the decoded frame as two 64x32 CI8 tiles, the upper from byte 0 and the
# lower from byte 0x7C0 (row 31), with ``gDPLoadTLUT_pal256`` on a palette the
# game stitches at run time: ``struct_D_802F1F80`` in ``src/buffers.h`` is 0xC0
# kart colours followed by 0x40 wheel colours, the first DMA'd from
# ``gKartPalettes[characterId]`` (``load_kart_palette``, ``src/kart_dma.c`` 318),
# the second from the frame's own wheel palette (``update_wheel_palette``,
# ``src/render_player.c`` 1789: frame ``k`` of a group reads ``kart_k_wheel_n``
# where ``n`` is ``tyreSpeed >> 8``, so wheel_0 is the tyre at rest and 1..3
# its rolling phases). The decomp's own extractor writes the same stitched
# palette (``tools/new_extract_assets.py`` ``export_stitched_palette``), with
# wheel_0, and this script matches it pixel for pixel.
#
# How a frame is chosen. ``func_8002934C`` (``src/player_controller.c`` 729):
#
#   a = atan2s(kart.x - cam.x, kart.z - cam.z) + rotation[1] + unk_0C0   (u16)
#
# is the camera to kart bearing minus the kart's heading (the kart drives along
# ``sins(-rotation[1]), coss(-rotation[1])``, line 1308, so the sum is zero with
# the camera straight behind). Line 771: a frame index of ``a / 128`` at or
# above 0x101 sets ``UNK_002_UNKNOWN_0x4``, the mirror flag, and ``render_player``
# (line 1726) then draws the quad with the flipped vertex set (``gPlayerOneVtx``
# 8..15 in ``src/data/some_data.c``, same corners, u reversed). Line 802: ``a``
# at or above 0x7FF9 is negated, folding the circle onto 0..180 degrees. Then,
# driving normally, ``a / 0x208`` (2.856 degrees a frame) while ``a / 128 < 0x51``
# (under 56.95 degrees), else ``15 + a / DEGREES(9)``, clamped to 34; so indices
# 0..19 are the fine rear quarter, 21..34 the coarse 9 degree steps out to the
# head on view at 180, and 20 is never reached. In a spin out (banana, shell
# contact spin, lightning) the whole half circle is ``a / DEGREES(9)``, 0..19,
# from a second table of 20 frame rings (``gKartTextureTable1``), and a crash
# that tumbles the kart (green shell, explosion, star, terrain) plays the 32
# ``gKart<Name>289..320`` frames by its animation counter, ``unk_0A8 >> 8``,
# whatever the camera angle (``load_kart_texture``, ``src/kart_dma.c`` 213).
#
# The poses are pitch. ``func_80029200`` (``src/player_controller.c`` 694) picks
# ``animGroupSelector`` 0..8 from ``slopeAccel``, which line 962 sets to
# ``atan1s((rear tyre height - front tyre height) / kart length)``: positive
# when the rear sits higher, nose down. The bands are below -10, -10..-7,
# -7..-3, -3..-2, -2..2, 2..3, 3..7, 7..10 and 10 and over, degrees.
# ``gKartTextureTable0`` (``src/kart_dma.c`` 157) maps selector s to
# ``Group(8 - s)``, and ``DECLARE_KART_GROUP`` (line 17) gives Group g the 21
# fine frames ``g * 21 ..`` plus 14 frames (6..19) of one of five 20 frame rings
# at 189, 209, 229, 249 and 269; the second table maps selector s to the rings
# ``Group(17 - s)``, which are the same five rings whole.
# ---------------------------------------------------------------------------

KART_SEGMENT_ROM_OFFSET = 0x145470   # mk64.ld 486: BEGIN_SEG(kart_textures) 145470-63E278
KART_SEGMENT_ROM_END = 0x63E278
# The characters in the order their .o files are linked, mk64.ld 488-495, each
# with the ROM offset of its frame 000 from assets/karts/<name>_kart.json.
KART_ROM_ORDER = [
    ("luigi", 0x145470), ("mario", 0x1E01F0), ("yoshi", 0x272A20), ("peach", 0x309F50),
    ("wario", 0x39E0C0), ("toad", 0x43B3E0), ("donkeykong", 0x4CBE50), ("bowser", 0x57DE70),
]
# characterId, the index into gKartTextureTable0/1 and gKartPalettes (src/kart_dma.c 180).
KART_CHARACTER_IDS = {"mario": 0, "luigi": 1, "yoshi": 2, "toad": 3,
                      "donkeykong": 4, "wario": 5, "peach": 6, "bowser": 7}
KART_FRAME_COUNT = 321           # gKart<Name>000 .. 320
KART_WHEEL_FRAMES = 289          # gKart<Name>000Wheel0 .. 288Wheel3
KART_WHEEL_PHASES = 4
KART_WHEEL_PALETTE_BYTES = 0x80  # 0x40 RGBA16 colours, struct_D_802F1F80.wheel_palette
KART_PALETTE_BYTES = 0x180       # 0xC0 RGBA16 colours, struct_D_802F1F80.kart_palette
KART_PALETTE_COLOURS = 0xC0
KART_FRAME_SIZE = 64             # 64x64 CI8, two 64x32 tiles in render_kart
KART_FRAME_BYTES = KART_FRAME_SIZE * KART_FRAME_SIZE
KART_TUMBLE_FIRST = 289          # DECLARE_KART_TUMBLE_TABLE: 289 .. 320
KART_TUMBLE_COUNT = 32
KART_RING_BASES = [189, 209, 229, 249, 269]   # the five 20 frame half circles
KART_RING_LENGTH = 20
KART_FINE_LENGTH = 21
KART_POSE_FRAMES = 35            # a group: 21 fine + 14 coarse
# Group g borrows frames 6..19 of this ring for indices 21..34 (DECLARE_KART_GROUP).
KART_GROUP_RING = {0: 189, 1: 189, 2: 209, 3: 229, 4: 229, 5: 229, 6: 249, 7: 269, 8: 269}
# gKartTextureTable1: selector s -> Group(17 - s) -> ring base, src/kart_dma.c 143.
KART_SPIN_RING = {0: 269, 1: 269, 2: 249, 3: 229, 4: 229, 5: 229, 6: 209, 7: 189, 8: 189}
# animGroupSelector s, from func_80029200's slopeAccel bands, as a pose name and
# its pitch band in degrees (positive = nose down).
KART_POSES = [
    ("nose_up_10", -90, -10), ("nose_up_7", -10, -7), ("nose_up_3", -7, -3), ("nose_up_2", -3, -2),
    ("level", -2, 2),
    ("nose_down_2", 2, 3), ("nose_down_3", 3, 7), ("nose_down_7", 7, 10), ("nose_down_10", 10, 90),
]
KART_RING_POSES = {269: "nose_up_7", 249: "nose_up_3", 229: "level", 209: "nose_down_3", 189: "nose_down_7"}
# The angle rule's constants, in the game's 65536 units per turn.
KART_FINE_STEP_UNITS = 0x208                     # a / 0x208 for the fine frames
KART_COARSE_STEP_UNITS = int(9 * 65536 / 360)    # DEGREES(9) = 1638
KART_FINE_LIMIT_UNITS = 0x51 * 128               # a / 128 < 0x51: fine frames
KART_COARSE_OFFSET = 0xF
KART_MIRROR_UNITS = 0x101 * 128                  # a / 128 >= 0x101: drawn mirrored
KART_FOLD_UNITS = 0x7FF9                         # a >= 0x7FF9: a = -a
# How big the game draws it: an 18 unit square (gPlayerOneVtx, x -9..9, y 0..18)
# times gCharacterSize 0.75 (MARIO_SIZE etc., include/defines.h 132), in units
# of MkConst.UNIT (1/9 m). Only rows 0..59 reach the screen: the upper tile's
# v runs to 1984 (31 texels at the 0.5 texture scale) and the lower, which
# starts at row 31, to 1792 (28 texels).
KART_QUAD_UNITS = 18.0
KART_CHARACTER_SIZE = 0.75
KART_ROWS_DRAWN = 59
UNIT_METRES = 1.0 / 9.0
KART_TARGET_HEIGHT_M = 1.4

# The demo's roster onto the game's characters, by stat class first (MkRoster:
# light = pip, fennec, sprig; standard = rook, vesper; heavy = dozer, brack,
# tusk; the game: light = Toad, Peach, Yoshi; standard = Mario, Luigi; heavy =
# DK, Wario, Bowser) and by colour within a class where one fits: Sprig is
# green, so Yoshi; Fennec is orange, nearest Peach's pink; Pip takes Toad.
# Rook is blue and Vesper purple, neither Mario's red nor Luigi's green, so
# Rook gets the game's first character. Dozer is brown, so DK; Tusk is
# off-white, nearest Wario's yellow; Brack, grey, takes Bowser. Edit
# roster.json to reseat anyone.
KART_ROSTER = {
    "pip": "toad", "fennec": "peach", "sprig": "yoshi",
    "rook": "mario", "vesper": "luigi",
    "dozer": "donkeykong", "brack": "bowser", "tusk": "wario",
}


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


def mio0_decode(buf: bytes, off: int) -> tuple[bytes, int] | None:
    """Decompress the MIO0 block at *off*: the data and the offset just past
    the block, or None if it is not one.

    MIO0 is the compression the game uses for most of its bulk data. A block is
    a header, a run of layout bits, a section of literal bytes and a section of
    back references; a set bit takes the next literal, a clear bit takes a two
    byte back reference of a length and a distance. The end offset is where the
    last section stops, which is what lets a run of blocks packed back to back
    (the kart frames) be walked without a table of their sizes.
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
    return bytes(out), max(layout, comp, raw)


def mio0_decompress(buf: bytes, off: int) -> bytes | None:
    """Decompress the MIO0 block at *off*, or None if it is not one."""
    decoded = mio0_decode(buf, off)
    return decoded[0] if decoded else None


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


def align(value: int, to: int) -> int:
    return (value + to - 1) // to * to


def walk_kart_segment(rom: bytes) -> dict[str, dict] | None:
    """Walk the kart_textures segment block by block.

    Returns, per character name, its 321 decoded frames, the 289 x 4 wheel
    palettes and the kart palette, with the ROM offsets found, or None when the
    segment is not laid out as ``data/karts/<name>_kart.s`` describes it: every
    frame has to be a MIO0 block of exactly 64 x 64 bytes and every character's
    first frame has to sit where the decomp's asset json says it does.
    """
    pos = KART_SEGMENT_ROM_OFFSET
    characters: dict[str, dict] = {}
    for name, expected in KART_ROM_ORDER:
        if pos != expected:
            print(f"  {name}: frames start at 0x{pos:X}, decomp says 0x{expected:X}; stopping")
            return None
        frames: list[bytes] = []
        offsets: list[int] = []
        for index in range(KART_FRAME_COUNT):
            decoded = mio0_decode(rom, pos)
            if not decoded or len(decoded[0]) != KART_FRAME_BYTES:
                print(f"  {name}: frame {index} at 0x{pos:X} is not a 64x64 MIO0 block; stopping")
                return None
            frames.append(decoded[0])
            offsets.append(pos)
            pos = align(decoded[1], 4)
        wheel_span = KART_WHEEL_FRAMES * KART_WHEEL_PHASES * KART_WHEEL_PALETTE_BYTES
        wheels = rom[pos:pos + wheel_span]
        wheels_at = pos
        pos += wheel_span
        palette = rom[pos:pos + KART_PALETTE_BYTES]
        palette_at = pos
        pos = align(pos + KART_PALETTE_BYTES, 16)
        if pos > KART_SEGMENT_ROM_END:
            print(f"  {name}: runs past the end of the segment at 0x{pos:X}; stopping")
            return None
        characters[name] = {
            "frames": frames, "offsets": offsets, "wheels": wheels, "wheels_at": wheels_at,
            "palette": palette, "palette_at": palette_at,
        }
    return characters


def rgba16_to_rgba8(colours: bytes) -> list[tuple[int, int, int, int]]:
    """RGBA5551 big endian to 8 bit tuples, scaled the way n64graphics does
    (``SCALE_5_8``: ``v * 0xFF / 0x1F``), alpha 0 or 255."""
    out = []
    for i in range(0, len(colours) - 1, 2):
        v = (colours[i] << 8) | colours[i + 1]
        out.append(((v >> 11) * 0xFF // 0x1F, ((v >> 6) & 0x1F) * 0xFF // 0x1F,
                    ((v >> 1) & 0x1F) * 0xFF // 0x1F, 0xFF if v & 1 else 0))
    return out


def kart_frame_image(character: dict, index: int, phase: int = 0):
    """Frame *index* of a character as a Pillow RGBA image, through the stitched
    palette the game builds: the kart's 0xC0 colours then the frame's 0x40
    wheel colours at tyre *phase*. The tumble frames (289..320) have no wheel
    palette of their own and take frame 000's, as the decomp's json does."""
    from PIL import Image
    wheel_frame = index if index < KART_WHEEL_FRAMES else 0
    start = (wheel_frame * KART_WHEEL_PHASES + phase) * KART_WHEEL_PALETTE_BYTES
    wheel = character["wheels"][start:start + KART_WHEEL_PALETTE_BYTES]
    palette = rgba16_to_rgba8(character["palette"] + wheel)
    pixels = character["frames"][index]
    image = Image.new("RGBA", (KART_FRAME_SIZE, KART_FRAME_SIZE))
    image.putdata([palette[p] for p in pixels])
    return image


def kart_frame_angle_index(angle_units: int, spinning: bool = False) -> tuple[int, bool]:
    """The game's own rule, func_8002934C: the frame index for a camera
    bearing minus kart heading of *angle_units* (65536 a turn) and whether it
    is drawn mirrored. Here for the manifest's angle table and for a test."""
    a = angle_units & 0xFFFF
    mirrored = (a // 128) >= 0x101
    if a >= KART_FOLD_UNITS:
        a = (-a) & 0xFFFF
    if spinning:
        index = a // KART_COARSE_STEP_UNITS
        if index >= KART_RING_LENGTH:
            index = 0
        return index, mirrored
    if a < KART_FINE_LIMIT_UNITS:
        index = a // KART_FINE_STEP_UNITS
    else:
        index = a // KART_COARSE_STEP_UNITS + KART_COARSE_OFFSET
    return min(index, KART_POSE_FRAMES - 1), mirrored


def kart_pose_frames(group: int) -> list[int]:
    """The 35 ROM frame numbers of Group *group*, DECLARE_KART_GROUP."""
    fine = list(range(group * KART_FINE_LENGTH, (group + 1) * KART_FINE_LENGTH))
    ring = KART_GROUP_RING[group]
    return fine + list(range(ring + 6, ring + KART_RING_LENGTH))


def units_to_degrees(units: int) -> float:
    return round(units * 360.0 / 65536.0, 3)


def kart_angle_table() -> list[dict]:
    """For each of the 35 pose indices, the angle band (degrees, 0 = camera
    straight behind the kart) that selects it under the game's rule."""
    bands: dict[int, list[int]] = {}
    for a in range(0, 0x8000):
        index, _ = kart_frame_angle_index(a)
        if index not in bands:
            bands[index] = [a, a]
        bands[index][1] = a
    table = []
    for i in range(KART_POSE_FRAMES):
        if i in bands:
            lo, hi = bands[i]
            table.append({"index": i, "from_deg": units_to_degrees(lo), "to_deg": units_to_degrees(hi + 1)})
        else:
            table.append({"index": i, "from_deg": None, "to_deg": None, "note": "never selected"})
    return table


def content_rows(image) -> tuple[int, int]:
    """First and last row with any opaque pixel, inclusive."""
    alpha = image.getchannel("A")
    box = alpha.getbbox()
    return (box[1], box[3] - 1) if box else (0, -1)


def write_kart_sprites(characters: dict[str, dict], source_sha1: str, out_dir: Path) -> None:
    """Every frame of every character as PNGs, named by pose and index, with a
    manifest.json per character and roster.json mapping the demo's drivers."""
    import json

    angle_table = kart_angle_table()
    ring_table = [{"index": k, "from_deg": units_to_degrees(k * KART_COARSE_STEP_UNITS),
                   "to_deg": units_to_degrees((k + 1) * KART_COARSE_STEP_UNITS)}
                  for k in range(KART_RING_LENGTH)]
    drawn_height_m = KART_QUAD_UNITS * KART_CHARACTER_SIZE * UNIT_METRES
    for name, character in characters.items():
        folder = out_dir / name
        folder.mkdir(parents=True, exist_ok=True)
        images = {index: kart_frame_image(character, index) for index in range(KART_FRAME_COUNT)}
        poses: dict[str, dict] = {}
        written = 0

        def save_pose(pose: str, rom_frames: list[int]) -> dict:
            """Write a pose's frames as <pose>_<index>.png; its files and the
            rows its pixels span."""
            nonlocal written
            files = []
            top, bottom = KART_FRAME_SIZE, -1
            for i, frame in enumerate(rom_frames):
                file_name = f"{pose}_{i:02d}.png"
                images[frame].save(folder / file_name, optimize=True)
                first, last = content_rows(images[frame])
                top, bottom = min(top, first), max(bottom, last)
                files.append(file_name)
                written += 1
            return {"rom_frames": rom_frames, "files": files, "content_rows": [top, bottom]}

        for selector, (pose, pitch_lo, pitch_hi) in enumerate(KART_POSES):
            group = 8 - selector
            poses[pose] = {
                "kind": "drive", "anim_group_selector": selector, "group": group,
                "pitch_deg": [pitch_lo, pitch_hi], "coverage": "0-180", "angles": angle_table,
                **save_pose(pose, kart_pose_frames(group)),
            }
        for base in KART_RING_BASES:
            pose = f"ring_{KART_RING_POSES[base]}"
            selectors = [s for s, b in KART_SPIN_RING.items() if b == base]
            poses[pose] = {
                "kind": "ring", "anim_group_selectors": selectors,
                "pitch_deg": [KART_POSES[min(selectors)][1], KART_POSES[max(selectors)][2]],
                "coverage": "0-180", "step_deg": units_to_degrees(KART_COARSE_STEP_UNITS),
                "angles": ring_table,
                **save_pose(pose, list(range(base, base + KART_RING_LENGTH))),
            }
        poses["tumble"] = {
            "kind": "animation", "coverage": "animation",
            "note": "played by the crash animation counter (unk_0A8 >> 8), not by camera angle",
            **save_pose("tumble", list(range(KART_TUMBLE_FIRST, KART_TUMBLE_FIRST + KART_TUMBLE_COUNT))),
        }
        drive_rows = [p["content_rows"] for p in poses.values() if p["kind"] != "animation"]
        content_top = min(rows[0] for rows in drive_rows)
        content_bottom = max(rows[1] for rows in drive_rows)
        content_height = content_bottom - content_top + 1
        manifest = {
            "character": name,
            "character_id": KART_CHARACTER_IDS[name],
            "source": {
                "rom_sha1": source_sha1,
                "frames_rom_offset": f"0x{character['offsets'][0]:X}",
                "wheel_palettes_rom_offset": f"0x{character['wheels_at']:X}",
                "palette_rom_offset": f"0x{character['palette_at']:X}",
                "format": "64x64 CI8 in MIO0, RGBA16 palette of 0xC0 kart + 0x40 wheel colours",
            },
            "frame_size": [KART_FRAME_SIZE, KART_FRAME_SIZE],
            "rows_drawn_by_game": KART_ROWS_DRAWN,
            "content_rows": [content_top, content_bottom],
            "content_height_px": content_height,
            "content_note": "content_rows span the drive and ring poses; each pose lists its own, "
                            "and the tumble frames can fill the whole square",
            "angle": {
                "zero": "camera straight behind the kart; 180 is head on",
                "measure": "bearing from camera to kart minus the kart's heading, "
                           "positive with the camera on the kart's left side (nose points to the "
                           "right of the frame)",
                "coverage": "frames cover 0-180; for 180-360 use the frame for 360 - angle mirrored "
                            "horizontally (UNK_002_UNKNOWN_0x4, func_8002934C line 771)",
                "mirror_above_deg": units_to_degrees(KART_MIRROR_UNITS),
                "fine_step_deg": units_to_degrees(KART_FINE_STEP_UNITS),
                "fine_until_deg": units_to_degrees(KART_FINE_LIMIT_UNITS),
                "coarse_step_deg": units_to_degrees(KART_COARSE_STEP_UNITS),
                "rule": "a in 65536ths of a turn, folded to 0..0x7FF9 by a = -a when a >= 0x7FF9; "
                        "drive: a // 0x208 while a // 128 < 0x51, else 15 + a // 1638, max 34; "
                        "ring (spin out): a // 1638, 20 and over wraps to 0",
            },
            "size": {
                "unit_metres": UNIT_METRES,
                "drawn_height_m": round(drawn_height_m, 4),
                "drawn_width_m": round(drawn_height_m, 4),
                "pixel_size_for_1_4_m_frame": round(KART_TARGET_HEIGHT_M / KART_FRAME_SIZE, 6),
                "pixel_size_for_1_4_m_content": round(KART_TARGET_HEIGHT_M / content_height, 6),
                "pixel_size_as_game": round(drawn_height_m / KART_ROWS_DRAWN, 6),
            },
            "poses": poses,
        }
        (folder / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
        print(f"  {name}: {written} frames, content rows {content_top}..{content_bottom}"
              f" ({content_height} px), frames at 0x{character['offsets'][0]:X},"
              f" palette at 0x{character['palette_at']:X}")
    (out_dir / "roster.json").write_text(json.dumps(KART_ROSTER, indent=1) + "\n", encoding="utf-8")
    print(f"  wrote {out_dir / 'roster.json'}: {KART_ROSTER}")


SPRITE_KART_SCRIPT = Path("addons/gta/mk/scripts/mk_sprite_kart.gd")
# The drive poses an MkSpriteKart takes, by the manifest's name, and the spin
# ring it uses: the level one, the ring the game draws for a level kart.
SPRITE_KART_POSES = ("nose_up_10", "nose_up_7", "nose_up_3", "nose_up_2", "level",
                     "nose_down_2", "nose_down_3", "nose_down_7", "nose_down_10")
SPRITE_KART_RING = "ring_level"


def res_path(path: Path, root: Path) -> str:
    """``path`` as Godot sees it from the project at ``root``."""
    try:
        return "res://" + path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return "res://" + path.as_posix()


def kart_scene_text(manifest: dict, frames_res_dir: str, script_res: str, script_uid: str) -> str:
    """A drop-in kart scene for ``MkAssets.kart_model``: one MkSpriteKart with
    the character's frames in its pose arrays, by path, at the pixel size that
    draws the 64 pixel frame 1.4 m tall."""
    ext: list[str] = []
    ids: dict[str, str] = {}

    def texture_id(file_name: str) -> str:
        if file_name not in ids:
            ids[file_name] = f"{len(ids) + 2}_{Path(file_name).stem}"
            ext.append(f'[ext_resource type="Texture2D" path="{frames_res_dir}/{file_name}" id="{ids[file_name]}"]')
        return ids[file_name]

    properties: list[str] = []
    poses = manifest["poses"]
    for pose in SPRITE_KART_POSES:
        refs = ", ".join(f'ExtResource("{texture_id(f)}")' for f in poses[pose]["files"])
        properties.append(f"{pose} = Array[Texture2D]([{refs}])")
    refs = ", ".join(f'ExtResource("{texture_id(f)}")' for f in poses[SPRITE_KART_RING]["files"])
    properties.append(f"spin_ring = Array[Texture2D]([{refs}])")

    uid = f' uid="{script_uid}"' if script_uid else ""
    lines = [f"[gd_scene load_steps={len(ext) + 2} format=3]", "",
             f'[ext_resource type="Script"{uid} path="{script_res}" id="1_script"]',
             *ext, "",
             '[node name="MkSpriteKart" type="Sprite3D"]',
             f"pixel_size = {manifest['size']['pixel_size_for_1_4_m_frame']}",
             'script = ExtResource("1_script")',
             *properties, ""]
    return "\n".join(lines)


def write_kart_scenes(out_dir: Path, root: Path = Path(".")) -> list[Path]:
    """One ``<driver>.tscn`` per roster.json entry, beside the character
    folders, so the demo picks the game's own kart up for that driver
    (``MkAssets.kart_model`` looks for ``karts/<driver>.tscn``)."""
    import json

    roster = json.loads((out_dir / "roster.json").read_text(encoding="utf-8"))
    script = root / SPRITE_KART_SCRIPT
    uid_file = script.with_suffix(".gd.uid")
    script_uid = uid_file.read_text(encoding="utf-8").strip() if uid_file.is_file() else ""
    written: list[Path] = []
    for driver, character in roster.items():
        manifest_file = out_dir / character / "manifest.json"
        if not manifest_file.is_file():
            print(f"  {driver}: no {manifest_file}; no scene written")
            continue
        manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
        scene = out_dir / f"{driver}.tscn"
        scene.write_text(kart_scene_text(manifest, res_path(out_dir / character, root),
                                         res_path(script, root), script_uid),
                         encoding="utf-8", newline="\n")
        written.append(scene)
    print(f"  wrote {len(written)} kart scene(s) in {out_dir}: {', '.join(p.name for p in written)}")
    return written


def extract_karts(rom: bytes, source_sha1: str, out_dir: Path) -> bool:
    print("reading the kart sprites out of the kart_textures segment")
    try:
        import PIL  # noqa: F401
    except ImportError:
        print("  Pillow is not installed (python -m pip install pillow); skipping the sprites")
        return False
    characters = walk_kart_segment(rom)
    if not characters:
        print("  the segment is not laid out as the decompilation describes; nothing written")
        return False
    write_kart_sprites(characters, source_sha1, out_dir)
    write_kart_scenes(out_dir)
    return True


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
    parser.add_argument("--karts-out", type=Path, default=KARTS_DIR,
                        help=f"where to write the kart sprites, one folder a character (default {KARTS_DIR})")
    parser.add_argument("--no-karts", action="store_true", help="skip the kart sprites")
    parser.add_argument("--no-curves", action="store_true", help="skip the item curves")
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
    status = 0
    if not args.no_curves:
        status = extract_curves(rom, digest, args.out)
    if not args.no_karts and not extract_karts(rom, digest, args.karts_out):
        status = 1
    return status


def extract_curves(rom: bytes, digest: str, out: Path) -> int:
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
            target = out if mode == MAIN_MODE else out.with_name(f"{out.stem}_{mode}{out.suffix}")
            write_resource(chunk, mode, positions, digest, where, target)
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
    write_resource(curves, MAIN_MODE, RACERS, digest, where, out)
    print("done. The demo will use the real odds from now on.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
