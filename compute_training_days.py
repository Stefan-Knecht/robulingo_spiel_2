#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from typing import Iterable, TextIO

START_BONUS = 5


@dataclass
class SessionData:
    timestamps: list[float] = field(default_factory=list)
    session_start_ts: float | None = None
    has_non_start: bool = False
    event_count: int = 0
    exceeded_max: bool = False


def parse_ts(ts_str: str) -> datetime | None:
    if not isinstance(ts_str, str) or not ts_str:
        return None
    if ts_str.endswith("Z"):
        ts_str = f"{ts_str[:-1]}+00:00"
    try:
        dt = datetime.fromisoformat(ts_str)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def compute_active_seconds(
    timestamps: list[float],
    idle_cap_seconds: int,
    has_non_start: bool,
) -> int:
    if not timestamps:
        return 0
    # Idle-cap prevents counting long gaps as active because we do not have session_end.
    timestamps.sort()
    active = 0.0
    for idx in range(len(timestamps) - 1):
        gap = timestamps[idx + 1] - timestamps[idx]
        active += min(max(gap, 0.0), idle_cap_seconds)
    if has_non_start:
        active += START_BONUS
    return int(active)


def day_key_from_ts(ts_seconds: float) -> str:
    # TODO: Apply per-user timezone offset here before taking .date().
    return datetime.fromtimestamp(ts_seconds, tz=timezone.utc).date().isoformat()


def week_start_for_date(target: date, week_start: str) -> date:
    if week_start == "mon":
        delta = target.weekday()
    else:
        delta = (target.weekday() + 1) % 7
    return target - timedelta(days=delta)


def read_sessions(
    file_obj: Iterable[str],
    user_filter: str | None,
    max_events_per_session: int | None,
) -> tuple[dict[tuple[str, str], SessionData], dict[str, int]]:
    sessions: dict[tuple[str, str], SessionData] = {}
    counters = {
        "empty": 0,
        "invalid_json": 0,
        "missing_fields": 0,
        "invalid_ts": 0,
        "max_exceeded": 0,
    }
    for line in file_obj:
        raw = line.strip()
        if not raw:
            counters["empty"] += 1
            continue
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            counters["invalid_json"] += 1
            continue
        if not isinstance(data, dict):
            counters["invalid_json"] += 1
            continue
        ts_str = data.get("ts")
        user = data.get("user")
        session = data.get("session")
        if not ts_str or not user or not session:
            counters["missing_fields"] += 1
            continue
        if user_filter and user != user_filter:
            continue
        dt = parse_ts(ts_str)
        if dt is None:
            counters["invalid_ts"] += 1
            continue

        key = (user, session)
        session_data = sessions.get(key)
        if session_data is None:
            session_data = SessionData()
            sessions[key] = session_data
        session_data.event_count += 1
        if (
            max_events_per_session is not None
            and session_data.event_count > max_events_per_session
        ):
            if not session_data.exceeded_max:
                session_data.exceeded_max = True
                counters["max_exceeded"] += 1
        session_data.timestamps.append(dt.timestamp())
        event_type = data.get("type")
        if event_type == "session_start":
            ts_seconds = dt.timestamp()
            if session_data.session_start_ts is None:
                session_data.session_start_ts = ts_seconds
            else:
                session_data.session_start_ts = min(
                    session_data.session_start_ts, ts_seconds
                )
        else:
            session_data.has_non_start = True
    return sessions, counters


def compute_user_day_active(
    sessions: dict[tuple[str, str], SessionData],
    idle_cap_seconds: int,
) -> dict[str, dict[str, int]]:
    user_day_active: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for (user, _session_id), session_data in sessions.items():
        if not session_data.timestamps:
            continue
        active_seconds = compute_active_seconds(
            session_data.timestamps, idle_cap_seconds, session_data.has_non_start
        )
        if session_data.session_start_ts is not None:
            day_key = day_key_from_ts(session_data.session_start_ts)
        else:
            day_key = day_key_from_ts(session_data.timestamps[0])
        user_day_active[user][day_key] += active_seconds
    return user_day_active


def build_week_records(
    user_day_active: dict[str, dict[str, int]],
    week_start: str,
    threshold_seconds: int,
    idle_cap_seconds: int,
    week_date: date | None,
) -> list[dict]:
    records: list[dict] = []
    for user in sorted(user_day_active.keys()):
        if week_date is not None:
            week_starts = [week_start_for_date(week_date, week_start)]
        else:
            week_starts = {
                week_start_for_date(date.fromisoformat(day), week_start)
                for day in user_day_active[user].keys()
            }
        for week_start_date in sorted(week_starts):
            days = []
            qualified_count = 0
            for offset in range(7):
                current_day = week_start_date + timedelta(days=offset)
                day_key = current_day.isoformat()
                active_seconds = user_day_active[user].get(day_key, 0)
                qualified = active_seconds >= threshold_seconds
                if qualified:
                    qualified_count += 1
                days.append(
                    {
                        "date": day_key,
                        "qualified": qualified,
                        "active_seconds": active_seconds,
                    }
                )
            record = {
                "user": user,
                "week_start": week_start_date.isoformat(),
                "week_end": (week_start_date + timedelta(days=6)).isoformat(),
                "days": days,
                "qualified_count": qualified_count,
                "threshold_seconds": threshold_seconds,
                "idle_cap_seconds": idle_cap_seconds,
            }
            records.append(record)
    records.sort(key=lambda r: (r["user"], r["week_start"]))
    return records


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compute qualified training days per week from JSONL gameplay logs."
        )
    )
    parser.add_argument("path", nargs="?", help="Path to JSONL log file")
    parser.add_argument(
        "--week-start",
        choices=["mon", "sun"],
        default="mon",
        help="Week start day (mon or sun)",
    )
    parser.add_argument(
        "--idle-cap",
        type=int,
        default=20,
        help="Cap gaps between events in seconds",
    )
    parser.add_argument(
        "--threshold",
        type=int,
        default=120,
        help="Qualified day threshold in seconds",
    )
    parser.add_argument(
        "--timezone",
        default="UTC",
        help="Timezone for day bucketing (UTC only for now)",
    )
    parser.add_argument("--user", help="Filter to a single user id")
    parser.add_argument(
        "--week",
        help="Any date within target week (YYYY-MM-DD)",
    )
    parser.add_argument(
        "--format",
        choices=["json", "compact"],
        default="json",
        help="Output format (json or compact)",
    )
    parser.add_argument(
        "--demo",
        action="store_true",
        help="Read JSONL from stdin and output JSON",
    )
    parser.add_argument(
        "--max-events-per-session",
        type=int,
        default=None,
        help="Safeguard for extremely large sessions (default: unlimited)",
    )
    return parser.parse_args(argv)


def load_input(path: str | None, demo: bool) -> TextIO:
    if demo or path == "-":
        return sys.stdin
    if not path:
        raise ValueError("path is required unless --demo is set")
    return open(path, "r", encoding="utf-8")


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.timezone != "UTC":
        print("Only --timezone=UTC is supported for now.", file=sys.stderr)
        return 2

    try:
        input_fp = load_input(args.path, args.demo)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    with input_fp:
        sessions, counters = read_sessions(
            input_fp, args.user, args.max_events_per_session
        )

    week_date = None
    if args.week:
        try:
            week_date = date.fromisoformat(args.week)
        except ValueError:
            print("Invalid --week date; expected YYYY-MM-DD.", file=sys.stderr)
            return 2

    user_day_active = compute_user_day_active(sessions, args.idle_cap)
    records = build_week_records(
        user_day_active,
        args.week_start,
        args.threshold,
        args.idle_cap,
        week_date,
    )

    for record in records:
        if args.format == "json":
            print(json.dumps(record, separators=(",", ":")))
        else:
            digits = "".join("1" if d["qualified"] else "0" for d in record["days"])
            qualified_count = record["qualified_count"]
            print(
                f"{record['user']} {record['week_start']} {digits} ({qualified_count}/7)"
            )

    if any(counters.values()):
        print(
            "Skipped lines:"
            f" empty={counters['empty']}"
            f" invalid_json={counters['invalid_json']}"
            f" missing_fields={counters['missing_fields']}"
            f" invalid_ts={counters['invalid_ts']}"
            f" max_events_exceeded={counters['max_exceeded']}",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
