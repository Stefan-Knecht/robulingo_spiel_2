import io
import json
import unittest
from datetime import date, datetime, timedelta, timezone

import compute_training_days as ctd


def iso_z(dt: datetime) -> str:
    return dt.isoformat().replace("+00:00", "Z")


class ComputeTrainingDaysTests(unittest.TestCase):
    def test_active_seconds_idle_cap_and_bonus(self) -> None:
        timestamps = [0.0, 5.0, 45.0]
        active = ctd.compute_active_seconds(
            timestamps, idle_cap_seconds=20, has_non_start=True
        )
        self.assertEqual(active, 30)

    def test_multiple_sessions_same_day_accumulate(self) -> None:
        base = datetime(2025, 1, 1, 0, 0, 0, tzinfo=timezone.utc)
        lines = [
            json.dumps(
                {
                    "ts": iso_z(base),
                    "type": "session_start",
                    "session": "s1",
                    "user": "u1",
                }
            ),
            json.dumps(
                {
                    "ts": iso_z(base + timedelta(seconds=5)),
                    "type": "event",
                    "session": "s1",
                    "user": "u1",
                }
            ),
            json.dumps(
                {
                    "ts": iso_z(base + timedelta(seconds=45)),
                    "type": "event",
                    "session": "s1",
                    "user": "u1",
                }
            ),
            json.dumps(
                {
                    "ts": iso_z(base + timedelta(hours=1)),
                    "type": "session_start",
                    "session": "s2",
                    "user": "u1",
                }
            ),
            json.dumps(
                {
                    "ts": iso_z(base + timedelta(hours=1, seconds=10)),
                    "type": "event",
                    "session": "s2",
                    "user": "u1",
                }
            ),
        ]
        sessions, _counters = ctd.read_sessions(
            io.StringIO("\n".join(lines)), user_filter=None, max_events_per_session=None
        )
        user_day_active = ctd.compute_user_day_active(sessions, idle_cap_seconds=20)
        self.assertEqual(user_day_active["u1"]["2025-01-01"], 45)

    def test_week_alignment(self) -> None:
        target = date(2025, 12, 21)  # Sunday
        self.assertEqual(ctd.week_start_for_date(target, "mon"), date(2025, 12, 15))
        self.assertEqual(ctd.week_start_for_date(target, "sun"), date(2025, 12, 21))

    def test_prompt_sample_snippet_qualifies(self) -> None:
        start = datetime(2025, 12, 21, 17, 47, 33, 908634, tzinfo=timezone.utc)
        lines = []
        for idx in range(7):
            ts = start + timedelta(seconds=20 * idx)
            lines.append(
                json.dumps(
                    {
                        "ts": iso_z(ts),
                        "type": "session_start" if idx == 0 else "event",
                        "session": "sample-session",
                        "user": "u123",
                    }
                )
            )
        sessions, _counters = ctd.read_sessions(
            io.StringIO("\n".join(lines)), user_filter=None, max_events_per_session=None
        )
        user_day_active = ctd.compute_user_day_active(sessions, idle_cap_seconds=20)
        active_seconds = user_day_active["u123"]["2025-12-21"]
        if active_seconds < 120:
            print(f"Computed active_seconds={active_seconds}")
        self.assertEqual(active_seconds, 125)
        records = ctd.build_week_records(
            user_day_active,
            week_start="mon",
            threshold_seconds=120,
            idle_cap_seconds=20,
            week_date=date(2025, 12, 21),
        )
        day_entry = next(
            day
            for day in records[0]["days"]
            if day["date"] == "2025-12-21"
        )
        self.assertTrue(day_entry["qualified"])


if __name__ == "__main__":
    unittest.main()
