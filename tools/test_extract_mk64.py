#!/usr/bin/env python3
"""Tests for the parts of extract_mk64.py that do not need a ROM: the MIO0
decoder and its end offset, the game's camera angle to frame rule, the group
layout of the kart frames and the RGBA16 conversion.

Run with:  python -m unittest tools/test_extract_mk64.py
"""

from __future__ import annotations

import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import extract_mk64 as mk  # noqa: E402


def mio0_literal_block(payload: bytes) -> bytes:
    """A MIO0 block of nothing but literals: one set layout bit a byte."""
    layout = bytes([0xFF] * ((len(payload) + 7) // 8))
    layout += b"\0" * (-len(layout) % 4)
    comp_off = 16 + len(layout)
    raw_off = comp_off  # no back references, so the raw section follows at once
    return b"MIO0" + struct.pack(">III", len(payload), comp_off, raw_off) + layout + payload


class Mio0Test(unittest.TestCase):
    def test_literal_block_decodes_and_reports_its_end(self) -> None:
        payload = bytes(range(37))
        block = mio0_literal_block(payload)
        rom = b"junk" + block + b"MIO0tail"
        decoded = mk.mio0_decode(rom, 4)
        self.assertIsNotNone(decoded)
        data, end = decoded
        self.assertEqual(data, payload)
        self.assertEqual(end, 4 + len(block))
        self.assertEqual(mk.mio0_decompress(rom, 4), payload)

    def test_back_reference(self) -> None:
        # "ab" literal, then copy 3 bytes from 2 back: "ababa"
        layout = bytes([0b11000000, 0, 0, 0])
        comp = bytes([(3 - 3) << 4 | 0, 2 - 1])
        raw = b"ab"
        block = b"MIO0" + struct.pack(">III", 5, 20, 22) + layout + comp + raw
        self.assertEqual(mk.mio0_decompress(block, 0), b"ababa")

    def test_not_a_block(self) -> None:
        self.assertIsNone(mk.mio0_decode(b"MIO1" + b"\0" * 32, 0))


class AngleRuleTest(unittest.TestCase):
    """func_8002934C, src/player_controller.c 729-834."""

    def test_rear_view_is_frame_zero(self) -> None:
        self.assertEqual(mk.kart_frame_angle_index(0), (0, False))

    def test_fine_steps_then_coarse(self) -> None:
        self.assertEqual(mk.kart_frame_angle_index(0x208 - 1)[0], 0)
        self.assertEqual(mk.kart_frame_angle_index(0x208)[0], 1)
        self.assertEqual(mk.kart_frame_angle_index(0x51 * 128 - 1)[0], 19)
        # the first coarse frame is 21; 20 is never reached
        self.assertEqual(mk.kart_frame_angle_index(0x51 * 128)[0], 21)
        self.assertNotIn(20, {mk.kart_frame_angle_index(a)[0] for a in range(0, 0x10000, 7)})

    def test_head_on_clamps_to_34(self) -> None:
        self.assertEqual(mk.kart_frame_angle_index(0x7FF8), (34, False))
        self.assertEqual(mk.kart_frame_angle_index(0x8000), (34, False))

    def test_other_half_is_mirrored(self) -> None:
        index, mirrored = mk.kart_frame_angle_index(0x10000 - 0x208 * 3 - 1)
        self.assertTrue(mirrored)
        self.assertEqual(index, 3)
        self.assertEqual(mk.kart_frame_angle_index(0x101 * 128 - 1)[1], False)
        self.assertEqual(mk.kart_frame_angle_index(0x101 * 128)[1], True)

    def test_spin_ring_wraps(self) -> None:
        self.assertEqual(mk.kart_frame_angle_index(1638 * 19, spinning=True)[0], 19)
        self.assertEqual(mk.kart_frame_angle_index(1638 * 20 - 1, spinning=True)[0], 19)
        # 1638 * 20 is 0x7FF8, the last folded angle, so a head on spin shows the rear frame
        self.assertEqual(mk.kart_frame_angle_index(0x7FF8, spinning=True)[0], 0)

    def test_angle_table_covers_the_half_circle(self) -> None:
        table = mk.kart_angle_table()
        self.assertEqual(len(table), 35)
        self.assertEqual(table[0]["from_deg"], 0.0)
        self.assertEqual(table[34]["to_deg"], 180.0)
        self.assertIsNone(table[20]["from_deg"])


class LayoutTest(unittest.TestCase):
    """DECLARE_KART_GROUP, src/kart_dma.c 17-141."""

    def test_level_group_borrows_the_level_ring(self) -> None:
        self.assertEqual(mk.kart_pose_frames(4), list(range(84, 105)) + list(range(235, 249)))

    def test_group_zero(self) -> None:
        self.assertEqual(mk.kart_pose_frames(0), list(range(0, 21)) + list(range(195, 209)))

    def test_every_group_is_35_frames(self) -> None:
        for group in range(9):
            self.assertEqual(len(mk.kart_pose_frames(group)), mk.KART_POSE_FRAMES)

    def test_roster_covers_every_driver_and_character(self) -> None:
        self.assertEqual(set(mk.KART_ROSTER), {"pip", "fennec", "sprig", "rook", "vesper", "dozer", "brack", "tusk"})
        self.assertEqual(set(mk.KART_ROSTER.values()), set(mk.KART_CHARACTER_IDS))


class SceneTest(unittest.TestCase):
    def _manifest(self) -> dict:
        poses = {pose: {"files": [f"{pose}_{i:02d}.png" for i in range(35)]} for pose in mk.SPRITE_KART_POSES}
        poses["ring_level"] = {"files": [f"ring_level_{i:02d}.png" for i in range(20)]}
        return {"size": {"pixel_size_for_1_4_m_frame": 0.021875}, "poses": poses}

    def test_scene_lists_every_frame_once_at_the_1_4_m_pixel_size(self) -> None:
        text = mk.kart_scene_text(self._manifest(), "res://k/toad", "res://s/mk_sprite_kart.gd", "uid://abc")
        self.assertIn("[gd_scene load_steps=337 format=3]", text)
        self.assertEqual(text.count('type="Texture2D"'), 9 * 35 + 20)
        self.assertIn('uid="uid://abc" path="res://s/mk_sprite_kart.gd"', text)
        self.assertIn('[node name="MkSpriteKart" type="Sprite3D"]', text)
        self.assertIn("pixel_size = 0.021875", text)
        self.assertIn('path="res://k/toad/level_34.png"', text)
        self.assertIn("spin_ring = Array[Texture2D]([ExtResource(", text)
        for pose in mk.SPRITE_KART_POSES:
            self.assertIn(f"\n{pose} = Array[Texture2D]([", text)

    def test_write_kart_scenes_names_scenes_by_driver(self) -> None:
        import json
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            karts = root / "addons" / "gta" / "mk" / "assets" / "karts"
            (karts / "toad").mkdir(parents=True)
            (karts / "toad" / "manifest.json").write_text(json.dumps(self._manifest()), encoding="utf-8")
            (karts / "roster.json").write_text(json.dumps({"pip": "toad", "rook": "mario"}), encoding="utf-8")
            written = mk.write_kart_scenes(karts, root)
            self.assertEqual([p.name for p in written], ["pip.tscn"], "A character with no frames gets no scene")
            self.assertIn('path="res://addons/gta/mk/assets/karts/toad/level_00.png"',
                          (karts / "pip.tscn").read_text(encoding="utf-8"))


class ColourTest(unittest.TestCase):
    def test_rgba16(self) -> None:
        # red 31, green 0, blue 15, alpha 1 -> 0xF81F
        self.assertEqual(mk.rgba16_to_rgba8(bytes([0xF8, 0x1F])), [(255, 0, 123, 255)])
        self.assertEqual(mk.rgba16_to_rgba8(bytes([0x00, 0x00])), [(0, 0, 0, 0)])


if __name__ == "__main__":
    unittest.main()
