#!/usr/bin/env python3
"""Tests for tools/mk64_course.py: the decompilation tables are read, the fit maps both ways, the
fence quads collapse to one segment each, and the scene text is Godot's.

Run with:  python -m unittest tools/test_mk64_course.py
"""

from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mk64_course as mk  # noqa: E402

SNIPPET = """
TrackPathPoint d_course_mario_raceway_track_path[] = {
    { 0, 0, -232, 1 },      { 0, 0, -252, 1 },      { 10, 2, -272, 1 },
    { -32768, 0, 0, 0 },
};

struct ActorSpawnData d_course_mario_raceway_item_box_spawns[] = {
    { { 503, 0, -951 }, { 0 } },  { { 531, 2, -986 }, { 0 } },
    { { -32768, 0, 0 }, { 0 } },
};

struct ActorSpawnData d_course_mario_raceway_piranha_plant_spawns[] = {
    { { 2248, 3, -442 }, { 7 } }, { { -32768, 0, 0 }, { 0 } },
};

struct ActorSpawnData d_course_mario_raceway_tree_spawns[] = {
    { { 228, 0, -1069 }, { 7 } }, { { 372, 2, -1046 }, { 7 } }, { { -32768, 0, 0 }, { 0 } },
};
"""


class Tables(unittest.TestCase):
    def test_the_tables_are_read_without_their_terminators(self) -> None:
        tables = mk.course_tables(SNIPPET)
        self.assertEqual(tables["path"], [(0, 0, -232, 1), (0, 0, -252, 1), (10, 2, -272, 1)])
        self.assertEqual(tables["boxes"], [(503, 0, -951, 0), (531, 2, -986, 0)])
        self.assertEqual(tables["plants"], [(2248, 3, -442, 7)])
        self.assertEqual(len(tables["trees"]), 2)

    def test_a_missing_table_is_an_error_rather_than_an_empty_course(self) -> None:
        with self.assertRaises(ValueError):
            mk.parse_path(SNIPPET, "d_course_mario_raceway_unknown_path")

    def test_the_lap_closes_back_to_the_first_point(self) -> None:
        self.assertAlmostEqual(mk.lap_length([(0, 0, 0, 0), (0, 0, 30, 0), (40, 0, 30, 0)]), 30 + 40 + 50)


class FitMaps(unittest.TestCase):
    def test_to_rip_and_back(self) -> None:
        for a in mk.Fit.MAPS:
            fit = mk.Fit(a, 971.0, (0.06, 0.0058))
            rx, rz = fit.to_rip(503, -951)
            gx, gz = fit.to_game(rx, rz)
            self.assertAlmostEqual(gx, 503, places=6)
            self.assertAlmostEqual(gz, -951, places=6)

    def test_metres_are_game_units_over_nine(self) -> None:
        fit = mk.Fit(((-1, 0), (0, -1)), 900.0, (0.0, 0.0))
        x, y, z = fit.rip_to_metres((-1.0, 0.1, 0.5))  # game (900, 90, -450)
        self.assertAlmostEqual(x, 100.0)
        self.assertAlmostEqual(y, 10.0)
        self.assertAlmostEqual(z, -50.0)


class FakeRip:
    def __init__(self, verts, faces):
        self.verts = verts
        self.groups = {"120": faces}


class Fences(unittest.TestCase):
    def test_a_quad_of_two_triangles_is_one_segment_on_the_ground(self) -> None:
        verts = [(0, 0, 0), (1, 0, 0), (1, 0.05, 0), (0, 0.05, 0)]
        faces = [([0, 1, 2], [], "m"), ([0, 2, 3], [], "m")]
        fit = mk.Fit(((1, 0), (0, 1)), 9.0, (0.0, 0.0))  # one rip unit is one metre
        segments = mk.fence_segments(FakeRip(verts, faces), fit)
        self.assertEqual(len(segments), 1)
        (a, b), = segments
        self.assertAlmostEqual(math.dist(a, b), 1.0)
        self.assertAlmostEqual(a[1], 0.0, msg="the segment is on the fence's foot")

    def test_a_flat_face_is_not_a_fence(self) -> None:
        verts = [(0, 0, 0), (1, 0, 0), (1, 0, 1)]
        self.assertEqual(mk.fence_segments(FakeRip(verts, [([0, 1, 2], [], "m")]), mk.Fit(((1, 0), (0, 1)), 9.0, (0, 0))), [])


class SceneText(unittest.TestCase):
    def test_transform_rows_face_plus_z_along_the_heading(self) -> None:
        # a heading along -Z is a half turn: Godot writes the basis by rows
        self.assertEqual(mk.transform((1, 2, 3), (0, 0, -1)), "Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 1, 2, 3)")
        self.assertEqual(mk.transform((0, 0, 0), (1, 0, 0)), "Transform3D(0, 0, 1, 0, 1, 0, -1, 0, 0, 0, 0, 0)")

    def test_the_grid_is_two_staggered_columns_behind_the_line(self) -> None:
        slots = mk.grid_slots([(0, 0, -232, 1), (0, 0, -252, 1)])
        self.assertEqual(len(slots), 8)
        start_z = -232 * mk.UNIT_METRES
        for origin, facing in slots:
            self.assertGreater(origin[2], start_z, "behind the line, which the karts drive -Z across")
            self.assertEqual(facing, (0.0, 0.0, -1.0))
        self.assertAlmostEqual(slots[0][0][0], 2.2)
        self.assertAlmostEqual(slots[1][0][0], -2.2)
        self.assertGreater(slots[1][0][2], slots[0][0][2], "the second column sits further back")

    def test_curve_text_is_closed_with_zero_handles(self) -> None:
        text = mk.curve3d([(1, 0, 2), (3, 0, 4)])
        self.assertIn("closed = true", text)
        self.assertIn("point_count = 2", text)
        self.assertIn("PackedVector3Array(0, 0, 0, 0, 0, 0, 1, 0, 2, 0, 0, 0, 0, 0, 0, 3, 0, 4)", text)


if __name__ == "__main__":
    unittest.main()
