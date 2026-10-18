import importlib.util
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts/grok-generate-interframes.py"
SPEC = importlib.util.spec_from_file_location("grok_generate_interframes", SCRIPT)
assert SPEC and SPEC.loader
generator = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = generator
SPEC.loader.exec_module(generator)


class GrokInterframeTests(unittest.TestCase):
    def test_identical_color_attributes_are_not_reformatted(self):
        self.assertEqual(
            generator._interpolate_attribute("#00c972", "#00c972", 0.5),
            "#00c972",
        )

    def test_compatible_paths_get_vector_intermediate_geometry(self):
        left = "M 0 0 L 10 0 L 10 10 Z"
        right = "M 0 0 L 20 0 L 20 20 Z"
        result = generator._interpolate_path(left, right, 0.5)
        self.assertIsNotNone(result)
        assert result
        self.assertIn("L 15 0", result)
        self.assertIn("L 15 15", result)

    def test_topology_changes_fall_back_instead_of_morphing(self):
        left = "M 0 0 L 10 0 L 10 10 Z"
        right = "M 0 0 L 10 0 L 10 10 Z M 2 2 L 3 2 L 3 3 Z"
        self.assertIsNone(generator._interpolate_path(left, right, 0.5))

    def test_closed_contours_align_changed_start_and_winding(self):
        left = "M 0 0 L 10 0 L 10 10 L 0 10 Z"
        right = "M 10 10 L 10 0 L 0 0 L 0 10 Z"
        result = generator._interpolate_path(left, right, 0.5)
        self.assertIsNotNone(result)
        assert result
        points = generator.sample_subpath(generator.parse_path(result)[0], 64)
        area = abs(generator._signed_area(points))
        self.assertGreater(area, 90)

    def test_captured_grok_contours_do_not_collapse_at_known_reanchors(self):
        cases = (
            ("heart-red", 2, 3),
            ("hex-green", 41, 42),
            ("sparkle-magenta", 15, 16),
            ("star-yellow", 21, 22),
        )
        source = ROOT / "config/quickshell/ii/assets/grok-avatar-animations"
        for key, left_index, right_index in cases:
            with self.subTest(sequence=key):
                left_root = ET.parse(source / key / "neutral" / f"frame-{left_index:03d}.svg").getroot()
                right_root = ET.parse(source / key / "neutral" / f"frame-{right_index:03d}.svg").getroot()
                left_path = next(element.attrib["d"] for element in left_root.iter() if element.tag.rsplit("}", 1)[-1] == "path")
                right_path = next(element.attrib["d"] for element in right_root.iter() if element.tag.rsplit("}", 1)[-1] == "path")
                result = generator._interpolate_path(left_path, right_path, 0.25)
                self.assertIsNotNone(result)
                assert result
                points = generator.sample_subpath(generator.parse_path(result)[0], 256)
                self.assertGreater(abs(generator._signed_area(points)), 18_000)

    def test_generator_preserves_keyframes_and_expands_sequence(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "source"
            output = Path(temp) / "output"
            sequence = source / "blob-violet" / "neutral"
            sequence.mkdir(parents=True)
            for index in range(46):
                (sequence / f"frame-{index:03d}.svg").write_text(
                    f'<svg xmlns="http://www.w3.org/2000/svg"><path d="M 0 0 L {index} 0 L {index} {index} Z" fill="#a97efe"/></svg>',
                    encoding="utf-8",
                )

            generated = generator.generate(source, output, 4)
            self.assertEqual(generated, (1, 45, 0))
            dense = output / "blob-violet" / "neutral"
            self.assertEqual(len(list(dense.glob("frame-*.svg"))), 181)
            self.assertEqual(
                (dense / "frame-000.svg").read_bytes(),
                (sequence / "frame-000.svg").read_bytes(),
            )
            self.assertEqual(
                (dense / "frame-180.svg").read_bytes(),
                (sequence / "frame-045.svg").read_bytes(),
            )
            self.assertNotEqual(
                (dense / "frame-001.svg").read_bytes(),
                (sequence / "frame-000.svg").read_bytes(),
            )


if __name__ == "__main__":
    unittest.main()
