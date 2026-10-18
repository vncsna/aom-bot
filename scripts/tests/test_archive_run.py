#!/usr/bin/env python3
"""Regression tests for scripts/archive_run.py.

The archive has to survive an agent reading it later, so these pin the header
(which names the map and both players) and the filtering to the bot's own lines.
"""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ARCHIVE = Path(__file__).resolve().parent.parent / "archive_run.py"

MYTHLOG = (
    "PreGame  1416:  ************* Memory Report ***************\r\n"
    "12719    00:00:12:  MAP CODE: '0/mirage.xs/16295/2/1/5/1/2/8/2/0/1/0/2/0/3/1/0/1'\r\n"
)

CONSTANTS = """\
const int cMyID = {player};
const int cMyCulture = {culture};
const int cMyCiv = {civ};
const string cFilename = "{script}";
const int cPersonalityCurrent = {personality};
const int cPersonalityBalanced = 0;
const int cCultureEgyptian = 1;
const int cCultureNorse = 2;
const int cCivIsis = 5;
const int cCivOdin = 8;
"""

BOT_LOG = "\n".join([
    "00:00:00  (0): Main is starting",  # engine chatter, dropped
    "00:00:00  (0): === [CustomBot] preInit() - installing Conqueror strategy ===",
    "00:00:30  (30052): [CBOT] t=30 age=1 vills=8 pop=9/15 army=0 food=100 wood=100 gold=100 enemyAge=1 state=hold",
    "00:00:59  (59052): --- Running Rule defendManager. ---",  # engine chatter, dropped
    "00:21:00  (1260327): [CustomBot] Raiding enemy economy at 12.",
])

NO_BOT_LOG = "00:00:00  (0): Villager Priority startup.\n00:00:00  (0): Deleting Fish plans.\n"


def write_run(logs, bot_log):
    (logs / "MythLog.txt").write_text(MYTHLOG)
    (logs / "MythAIConstantsPlayer1.txt").write_text(
        CONSTANTS.format(player=1, culture=1, civ=5, script="custom_bot", personality=14))
    (logs / "MythAIConstantsPlayer2.txt").write_text(
        CONSTANTS.format(player=2, culture=2, civ=8, script="chairon", personality=0))
    (logs / "MythRetoldAIOutputPlayer1.txt").write_bytes(bot_log.encode("utf-16"))


class ArchiveRunTest(unittest.TestCase):
    def archive(self, bot_log, *args):
        """Run the archiver over a throwaway log dir; return its result and archives."""
        with tempfile.TemporaryDirectory() as tmp:
            logs, runs = Path(tmp) / "logs", Path(tmp) / "runs"
            logs.mkdir()
            write_run(logs, bot_log)
            env = dict(os.environ, AOM_LOGS=str(logs), AOM_RUNS=str(runs))
            result = subprocess.run(
                [sys.executable, str(ARCHIVE), *args], env=env, capture_output=True, text=True)
            archived = [(path.name, path.read_text()) for path in sorted(runs.glob("*"))]
        return result, archived

    def test_archives_bot_lines_under_a_metadata_header(self):
        result, archived = self.archive(BOT_LOG, "beat", "Balanced", "on", "Easy")
        self.assertEqual(result.returncode, 0, result.stderr)

        self.assertEqual(len(archived), 1)
        name, text = archived[0]
        self.assertTrue(name.endswith("-mirage.log"), name)

        self.assertIn("# map: mirage", text)
        self.assertIn("# player 1: custom_bot, personality 14, Isis (Egyptian)", text)
        self.assertIn("# player 2: chairon, Balanced, Odin (Norse)", text)
        self.assertIn("# notes: beat Balanced on Easy", text)
        self.assertIn("[CBOT] t=30 age=1", text)
        self.assertIn("[CustomBot] preInit()", text)
        self.assertNotIn("defendManager", text)

    def test_refuses_a_log_with_no_bot_output(self):
        result, archived = self.archive(NO_BOT_LOG)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no bot output", result.stderr)
        self.assertEqual(archived, [])


if __name__ == "__main__":
    unittest.main()
