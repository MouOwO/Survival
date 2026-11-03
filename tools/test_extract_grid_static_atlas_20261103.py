import unittest
import extract_grid_static_atlas_20261103 as m


class PublicAtlasExtractionTests(unittest.TestCase):
    def log(self, left="3|64|-1|2|2|2|384|99", right=None):
        right = left if right is None else right
        return (('event_name: "ui_grid_placement_static_area"\ndata: "private_scope_account_' + value + '"\n') * 1
                for value in (left, right))

    def payload(self, left="3|64|-1|2|2|2|384|99", right=None):
        return ("".join(self.log(left, right)) + "ShutdownSource2Logging\n").encode("ascii")

    def test_only_public_numeric_bitmap_survives(self):
        value = m.parse_areas(self.payload())
        self.assertEqual(value, "3|64|-1|2|2|2|384|99")
        self.assertNotIn("private", value)

    def test_different_regions_or_maps_are_not_silently_combined(self):
        with self.assertRaisesRegex(ValueError, "two_identical"):
            m.parse_areas(self.payload(right="3|64|-2|2|2|2|384|99"))

    def test_unknown_states_dimensions_or_open_log_fail_closed(self):
        for area in ("3|64|-1|2|2|2|384|ff", "3|64|-1|2|2|2|384|9"):
            with self.assertRaises(ValueError):
                m.parse_areas(self.payload(area))
        with self.assertRaisesRegex(ValueError, "closed_native"):
            m.parse_areas(self.payload().replace(b"ShutdownSource2Logging", b"open"))


if __name__ == "__main__":
    unittest.main()
