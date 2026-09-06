"""Guard against silently unconstrained ports and missing/negative timing results."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "ppa/scripts"))
from generate_sdc import generate
from multi_corner import read_timing


class TimingToolsTest(unittest.TestCase):
    def setUp(self):
        self.config = json.loads((ROOT / "constraints/timing-estimate.json").read_text())
        self.netlist = "input clock;\ninput reset;\n" + "\n".join(
            [f"input pin_{i};" for i in range(40)] +
            [f"output out_{i};" for i in range(51)])

    def test_complete_io_budget(self):
        sdc = generate(self.config, self.netlist, 10)
        self.assertEqual(sdc.count("set_input_delay -max"), 41)
        self.assertEqual(sdc.count("set_input_delay -min"), 41)
        self.assertEqual(sdc.count("set_output_delay -max"), 51)
        self.assertEqual(sdc.count("set_output_delay -min"), 51)
        self.assertNotIn("set_false_path", sdc)

    def test_reject_missing_port(self):
        with self.assertRaises(ValueError):
            generate(self.config, self.netlist.replace("input pin_39;", ""), 10)

    def test_reject_invalid_budget(self):
        for key, value in (("input_delay_min_ns", 3), ("output_load_pf", -1),
                           ("clock_transition_ns", float("nan"))):
            with self.subTest(key=key), self.assertRaises(ValueError):
                generate({**self.config, key: value}, self.netlist, 10)

    def test_negative_hold_is_not_pass(self):
        with tempfile.TemporaryDirectory() as folder:
            report = Path(folder) / "timing.rpt"
            report.write_text("| out | tile_clock | max | 3r | 8 | 0 | 5.0 | 200 |\n"
                              "| ff:D | tile_clock | min | .07 | .1 | 0 | -.030 | NA |\n"
                              "| tile_clock | max | 0.000 |\n"
                              "| tile_clock | min | -1.200 |\n")
            result = read_timing(report)
            self.assertFalse(result["timing_met"])
            self.assertEqual(result["hold_wns_ns"], -.03)

    def test_missing_hold_report_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            report = Path(folder) / "timing.rpt"
            report.write_text("| out | tile_clock | max | 3r | 8 | 0 | 5.0 | 200 |\n")
            with self.assertRaises(ValueError):
                read_timing(report)


if __name__ == "__main__":
    unittest.main()
