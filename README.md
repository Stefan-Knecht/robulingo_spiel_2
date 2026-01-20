# Training Days CLI

Compute qualified training days per week from JSONL gameplay logs using the
gap-capped active time method.

## Usage

```bash
python compute_training_days.py /path/to/logs.jsonl
```

Common flags:

```bash
python compute_training_days.py /path/to/logs.jsonl --week-start sun
python compute_training_days.py /path/to/logs.jsonl --idle-cap 20 --threshold 120
python compute_training_days.py /path/to/logs.jsonl --format compact
python compute_training_days.py /path/to/logs.jsonl --week 2025-12-15 --user u123
```

Demo mode (reads JSONL from stdin):

```bash
cat /path/to/logs.jsonl | python compute_training_days.py --demo
```

## Output

Default output is JSONL with per-user, per-week data, including day-level
active seconds and qualification flags. Compact output prints a one-line
summary with a 7-digit bitmap.

## Notes

- The script ignores empty/invalid lines and reports counts to stderr.
- `--max-events-per-session` is a safeguard for huge sessions. The tool already
  stores only timestamps, so it keeps working even if a session exceeds the cap.

## Tests

```bash
python -m unittest tests/test_compute_training_days.py
```
