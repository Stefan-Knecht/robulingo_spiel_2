#!/usr/bin/env python3
"""Monte-Carlo simulator for the SK Codex hex duel logic.

Mirrors the logic in lib/logic/hexagon_controller.dart:
- Rival mood (slacking/steady/hot) as a Markov chain with stay probability.
- pCorrect depends on player history, progress gap (catchup), mood offset, idle boost.
- Movement uses the same hex-grid neighbor selection rules.

This script is intentionally parameter-light so win chances stay controllable.
"""
from __future__ import annotations

import argparse
import math
import random
from dataclasses import dataclass
from typing import List, Optional, Sequence, Tuple

HEX_COLS = 10
HEX_ROWS = 3
START_PHASE_LEN = 10

UNIT_HEX = [
    (0.0, -1.0),
    (0.8660254, -0.5),
    (0.8660254, 0.5),
    (0.0, 1.0),
    (-0.8660254, 0.5),
    (-0.8660254, -0.5),
]


@dataclass
class Runner:
    index: int
    progress: int = 0
    last_delta: Optional[Tuple[float, float]] = None
    last_dir: int = 0


@dataclass
class DuelState:
    you: Runner
    rival: Runner
    wins_you: int = 0
    wins_rival: int = 0


@dataclass
class Grid:
    nodes: List[Tuple[float, float]]
    adjacency: List[List[int]]
    finish_nodes: set[int]
    start_you: int
    start_rival: int


@dataclass
class Params:
    sigma: float
    coupled_prob: float
    max_prob_base: float
    max_prob_slope: float
    min_prob_ratio: float
    mood_offsets: Tuple[float, float, float]
    mood_stay_prob: float
    mood_min_moves: int
    idle_grace_days: int
    idle_boost_per_day: float
    idle_boost_max: float


@dataclass
class RunResult:
    wins_you: int
    wins_rival: int
    winner: Optional[str]
    steps_to_win: Optional[int]


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def build_hex_grid(side: float = 1.0) -> Grid:
    nodes: List[Tuple[float, float]] = []
    node_index_by_key: dict[str, int] = {}
    node_index_by_cell_vertex: dict[str, int] = {}
    cells: List[Tuple[int, int, List[Tuple[float, float]]]] = []

    def add_node(p: Tuple[float, float]) -> int:
        key = f"{p[0]:.6f}:{p[1]:.6f}"
        if key in node_index_by_key:
            return node_index_by_key[key]
        idx = len(nodes)
        node_index_by_key[key] = idx
        nodes.append(p)
        return idx

    for row in range(HEX_ROWS):
        for col in range(HEX_COLS):
            x_offset = col * (1.7320508 * side) + (0.8660254 * side if row % 2 == 1 else 0.0)
            y_offset = row * (1.5 * side)
            points = [
                (p[0] * side + x_offset, p[1] * side + y_offset)
                for p in UNIT_HEX
            ]
            cells.append((row, col, points))
            for v, point in enumerate(points):
                idx = add_node(point)
                node_index_by_cell_vertex[f"{row}:{col}:{v}"] = idx

    adjacency: List[List[int]] = [[] for _ in range(len(nodes))]

    def connect(a: int, b: int) -> None:
        if b not in adjacency[a]:
            adjacency[a].append(b)
        if a not in adjacency[b]:
            adjacency[b].append(a)

    for row, col, _points in cells:
        verts = [node_index_by_cell_vertex[f"{row}:{col}:{i}"] for i in range(6)]
        for i in range(6):
            connect(verts[i], verts[(i + 1) % 6])

    max_x = max(p[0] for p in nodes)
    finish_nodes: set[int] = set()
    last_col = HEX_COLS - 1
    for row, col, points in cells:
        if col != last_col or row != 1:
            continue
        for v, point in enumerate(points):
            if abs(point[0] - max_x) < 1e-6:
                finish_nodes.add(node_index_by_cell_vertex[f"{row}:{col}:{v}"])

    start_you = node_index_by_cell_vertex["2:0:5"]
    start_rival = node_index_by_cell_vertex["0:0:4"]

    return Grid(
        nodes=nodes,
        adjacency=adjacency,
        finish_nodes=finish_nodes,
        start_you=start_you,
        start_rival=start_rival,
    )


def _vec_sub(a: Tuple[float, float], b: Tuple[float, float]) -> Tuple[float, float]:
    return (a[0] - b[0], a[1] - b[1])


def _vec_len(v: Tuple[float, float]) -> float:
    return math.hypot(v[0], v[1])


def _is_inverse(last: Optional[Tuple[float, float]], candidate: Tuple[float, float]) -> bool:
    if last is None:
        return False
    last_len = _vec_len(last)
    cand_len = _vec_len(candidate)
    if last_len < 1e-9 or cand_len < 1e-9:
        return False
    dot = last[0] * candidate[0] + last[1] * candidate[1]
    cos = dot / (last_len * cand_len)
    return cos < -0.8


def _choose_forward_with_fallback(grid: Grid, current: int, last_delta: Optional[Tuple[float, float]]):
    neighbors = grid.adjacency[current]
    best_right = None
    best_dx = float("-inf")
    for n in neighbors:
        delta = _vec_sub(grid.nodes[n], grid.nodes[current])
        if _is_inverse(last_delta, delta):
            continue
        if delta[0] > 1e-6 and delta[0] > best_dx:
            best_dx = delta[0]
            best_right = (n, delta, "forward")
    if best_right is not None:
        return best_right

    def prefers_vertical(candidate: Tuple[float, float], current_delta: Tuple[float, float]) -> bool:
        candidate_back = candidate[0] < -1e-6
        current_back = current_delta[0] < -1e-6
        if candidate_back != current_back:
            return not candidate_back
        cand_abs = abs(candidate[0])
        curr_abs = abs(current_delta[0])
        if abs(cand_abs - curr_abs) > 1e-6:
            return cand_abs < curr_abs
        return candidate[0] > current_delta[0]

    best_vertical = None
    best_vertical_inverse = None
    for n in neighbors:
        delta = _vec_sub(grid.nodes[n], grid.nodes[current])
        if abs(delta[1]) <= 1e-6:
            continue
        choice = (n, delta, "side")
        if _is_inverse(last_delta, delta):
            if best_vertical_inverse is None or prefers_vertical(delta, best_vertical_inverse[1]):
                best_vertical_inverse = choice
        else:
            if best_vertical is None or prefers_vertical(delta, best_vertical[1]):
                best_vertical = choice
    if best_vertical is not None:
        return best_vertical
    if best_vertical_inverse is not None:
        return best_vertical_inverse

    for n in neighbors:
        delta = _vec_sub(grid.nodes[n], grid.nodes[current])
        if _is_inverse(last_delta, delta):
            continue
        kind = "back" if delta[0] < -1e-6 else "side"
        return (n, delta, kind)

    return (current, (0.0, 0.0), "side")


def _choose_vertical_or_left(grid: Grid, current: int, last_delta: Optional[Tuple[float, float]]):
    neighbors = grid.adjacency[current]
    best_vertical = None
    for n in neighbors:
        delta = _vec_sub(grid.nodes[n], grid.nodes[current])
        if abs(delta[1]) > 1e-6:
            last_was_vertical = last_delta is not None and abs(last_delta[1]) > 1e-6
            would_reverse_vertical = (
                last_was_vertical
                and (1 if delta[1] > 0 else -1) == (-1 if last_delta[1] > 0 else 1)
            )
            if would_reverse_vertical:
                continue
            if abs(delta[0]) > abs(delta[1]) * 0.3:
                continue
            if best_vertical is None:
                best_vertical = (n, delta, "side")
            else:
                best_delta = best_vertical[1]
                if abs(delta[0]) < abs(best_delta[0]) or (
                    abs(delta[0]) == abs(best_delta[0]) and abs(delta[1]) > abs(best_delta[1])
                ):
                    best_vertical = (n, delta, "side")
    if best_vertical is not None:
        return best_vertical

    left_idx = None
    left_delta = None
    best_dx = 0.0
    for n in neighbors:
        delta = _vec_sub(grid.nodes[n], grid.nodes[current])
        if delta[0] < -1e-6 and delta[0] < best_dx:
            best_dx = delta[0]
            left_idx = n
            left_delta = delta
    if left_idx is not None and left_delta is not None:
        return (left_idx, left_delta, "back")

    return (current, (0.0, 0.0), "side")


def _apply_move(
    grid: Grid,
    runner: Runner,
    correct: bool,
    *,
    is_you: bool,
) -> None:
    current = runner.index
    if correct:
        runner.progress += 1
        next_idx, _delta, _kind = _choose_forward_with_fallback(grid, current, runner.last_delta)
    else:
        runner.progress = max(0, runner.progress - 1)
        next_idx, _delta, _kind = _choose_vertical_or_left(grid, current, runner.last_delta)

    if next_idx < 0 or next_idx >= len(grid.nodes):
        next_idx = current

    delta = _vec_sub(grid.nodes[next_idx], grid.nodes[current])
    runner.index = next_idx
    runner.last_dir = 1 if delta[0] > 1e-6 else (-1 if delta[0] < -1e-6 else 0)
    runner.last_delta = delta


def _idle_boost(idle_days: int, params: Params) -> float:
    extra = max(0, idle_days - params.idle_grace_days)
    return min(params.idle_boost_max, extra * params.idle_boost_per_day)


def _advance_mood(
    mood: int,
    mood_moves: int,
    *,
    idle_boost: float,
    rng: random.Random,
    params: Params,
) -> Tuple[int, int]:
    mood_moves += 1
    if mood_moves < params.mood_min_moves:
        return mood, mood_moves
    if rng.random() < params.mood_stay_prob:
        return mood, mood_moves

    mood_moves = 0
    up_bias = clamp(0.5 + idle_boost, 0.05, 0.95)
    if mood == 0:
        return 1, mood_moves
    if mood == 1:
        return (2, mood_moves) if rng.random() < up_bias else (0, mood_moves)
    return 1, mood_moves


def _rival_p_correct(
    state: DuelState,
    history: Sequence[bool],
    last_player_correct: Optional[bool],
    *,
    mood: int,
    idle_boost: float,
    params: Params,
) -> float:
    diff = state.rival.progress - state.you.progress
    diff_clamped = clamp(diff, -20, 20)
    catchup = 1 / (1 + math.exp(diff_clamped / params.sigma))
    mood_offset = params.mood_offsets[mood]
    min_ratio = clamp(params.min_prob_ratio, 0.0, 1.0)

    if len(history) < START_PHASE_LEN and last_player_correct is not None:
        base = params.coupled_prob if last_player_correct else (1 - params.coupled_prob)
        boosted = clamp(base + mood_offset + idle_boost, 0.0, 1.0)
        min_prob = clamp(boosted * min_ratio, 0.0, boosted)
        return min_prob + (boosted - min_prob) * catchup

    acc = sum(history) / len(history) if history else 0.0
    base_max = clamp(params.max_prob_base + params.max_prob_slope * acc, 0.0, 1.0)
    max_prob = clamp(base_max + mood_offset + idle_boost, 0.0, 1.0)
    min_prob = clamp(max_prob * min_ratio, 0.0, max_prob)
    return min_prob + (max_prob - min_prob) * catchup


def build_accuracy_profile(
    steps: int,
    *,
    acc: float,
    profile: Optional[str],
) -> List[float]:
    if not profile:
        return [clamp(acc, 0.0, 1.0)] * steps

    points: List[Tuple[int, float]] = []
    for part in profile.split(","):
        part = part.strip()
        if not part:
            continue
        if ":" not in part:
            raise ValueError(f"invalid profile segment: {part}")
        step_s, p_s = part.split(":", 1)
        step = int(step_s)
        prob = clamp(float(p_s), 0.0, 1.0)
        points.append((step, prob))

    if not points:
        return [clamp(acc, 0.0, 1.0)] * steps

    points.sort(key=lambda x: x[0])
    if points[0][0] > 0:
        points.insert(0, (0, points[0][1]))
    if points[-1][0] < steps - 1:
        points.append((steps - 1, points[-1][1]))

    profile_vals: List[float] = []
    for (s0, p0), (s1, p1) in zip(points, points[1:]):
        span = max(1, s1 - s0)
        for step in range(s0, min(s1, steps - 1) + 1):
            t = 0.0 if span == 0 else (step - s0) / span
            profile_vals.append(clamp(p0 + (p1 - p0) * t, 0.0, 1.0))

    if len(profile_vals) < steps:
        profile_vals.extend([profile_vals[-1]] * (steps - len(profile_vals)))
    return profile_vals[:steps]


def simulate_run(
    *,
    grid: Grid,
    accuracy: List[float],
    rng: random.Random,
    params: Params,
    idle_days: int,
    mode: str,
) -> RunResult:
    state = DuelState(you=Runner(index=grid.start_you), rival=Runner(index=grid.start_rival))
    history: List[bool] = []
    last_player_correct: Optional[bool] = None
    mood = 1  # steady
    mood_moves = 0
    idle_boost = _idle_boost(idle_days, params)

    steps = len(accuracy)
    for step in range(steps):
        player_correct = rng.random() < accuracy[step]
        history.append(player_correct)
        if len(history) > START_PHASE_LEN:
            history.pop(0)

        _apply_move(grid, state.you, player_correct, is_you=True)
        if state.you.index in grid.finish_nodes:
            state.wins_you += 1
            if mode == "race":
                return RunResult(state.wins_you, state.wins_rival, "you", step + 1)
            state.you.index = grid.start_you
            state.you.last_dir = 0

        last_player_correct = player_correct

        mood, mood_moves = _advance_mood(
            mood,
            mood_moves,
            idle_boost=idle_boost,
            rng=rng,
            params=params,
        )
        p_rival = _rival_p_correct(
            state,
            history,
            last_player_correct,
            mood=mood,
            idle_boost=idle_boost,
            params=params,
        )
        rival_correct = rng.random() < p_rival
        _apply_move(grid, state.rival, rival_correct, is_you=False)
        if state.rival.index in grid.finish_nodes:
            state.wins_rival += 1
            if mode == "race":
                return RunResult(state.wins_you, state.wins_rival, "rival", step + 1)
            state.rival.index = grid.start_rival
            state.rival.last_dir = 0

    return RunResult(state.wins_you, state.wins_rival, None, None)


def simulate_trace(
    *,
    grid: Grid,
    accuracy: List[float],
    rng: random.Random,
    params: Params,
    idle_days: int,
    mode: str,
) -> List[int]:
    state = DuelState(you=Runner(index=grid.start_you), rival=Runner(index=grid.start_rival))
    history: List[bool] = []
    last_player_correct: Optional[bool] = None
    mood = 1  # steady
    mood_moves = 0
    idle_boost = _idle_boost(idle_days, params)
    winner: Optional[str] = None
    flags: List[int] = []

    steps = len(accuracy)
    for step in range(steps):
        if mode == "race" and winner is not None:
            flag = 1 if winner == "you" else 0
            flags.extend([flag] * (steps - step))
            break

        player_correct = rng.random() < accuracy[step]
        history.append(player_correct)
        if len(history) > START_PHASE_LEN:
            history.pop(0)

        _apply_move(grid, state.you, player_correct, is_you=True)
        if state.you.index in grid.finish_nodes:
            state.wins_you += 1
            if mode == "race" and winner is None:
                winner = "you"
            state.you.index = grid.start_you
            state.you.last_dir = 0

        last_player_correct = player_correct

        mood, mood_moves = _advance_mood(
            mood,
            mood_moves,
            idle_boost=idle_boost,
            rng=rng,
            params=params,
        )
        p_rival = _rival_p_correct(
            state,
            history,
            last_player_correct,
            mood=mood,
            idle_boost=idle_boost,
            params=params,
        )
        rival_correct = rng.random() < p_rival
        _apply_move(grid, state.rival, rival_correct, is_you=False)
        if state.rival.index in grid.finish_nodes:
            state.wins_rival += 1
            if mode == "race" and winner is None:
                winner = "rival"
            state.rival.index = grid.start_rival
            state.rival.last_dir = 0

        if mode == "series":
            flags.append(1 if state.wins_you > state.wins_rival else 0)
        else:
            flags.append(1 if winner == "you" else 0)
            if winner is not None and step < steps - 1:
                flag = 1 if winner == "you" else 0
                flags.extend([flag] * (steps - step - 1))
                break

    if len(flags) < steps:
        flags.extend([0] * (steps - len(flags)))
    return flags


def monte_carlo_trace(
    *,
    runs: int,
    grid: Grid,
    accuracy: List[float],
    params: Params,
    idle_days: int,
    mode: str,
    seed: int,
) -> List[float]:
    accum = [0] * len(accuracy)
    base_rng = random.Random(seed)
    for _ in range(runs):
        run_rng = random.Random(base_rng.random())
        trace = simulate_trace(
            grid=grid,
            accuracy=accuracy,
            rng=run_rng,
            params=params,
            idle_days=idle_days,
            mode=mode,
        )
        accum = [a + b for a, b in zip(accum, trace)]
    return [a / runs for a in accum]


def _plot_trace(probs: List[float], *, mode: str, out: Optional[str]) -> None:
    try:
        import matplotlib.pyplot as plt  # type: ignore
    except ImportError as exc:
        raise SystemExit(f"matplotlib not installed: {exc}")

    xs = list(range(1, len(probs) + 1))
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(xs, probs, label="player win/lead probability")
    ax.set_xlabel("Step")
    ax.set_ylabel("Probability")
    if mode == "race":
        title = "P(player already won) over steps"
    else:
        title = "P(player leads) over steps"
    ax.set_title(title)
    ax.set_ylim(0, 1)
    ax.grid(True, linestyle=":", alpha=0.4)
    ax.legend()
    fig.tight_layout()
    if out:
        fig.savefig(out, dpi=150)
    else:
        plt.show()


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Monte-Carlo simulation for the hex duel rival logic.")
    parser.add_argument("--runs", type=int, default=5000, help="Monte-Carlo runs (default: 5000)")
    parser.add_argument("--steps", type=int, default=120, help="Trials per run (default: 120)")
    parser.add_argument("--mode", choices=["race", "series"], default="race", help="race=stop on first win")
    parser.add_argument("--acc", type=float, default=0.75, help="Player accuracy if no profile (default: 0.75)")
    parser.add_argument(
        "--acc-profile",
        type=str,
        default=None,
        help="Accuracy profile as step:prob pairs, e.g. 0:0.65,60:0.8,120:0.9",
    )
    parser.add_argument("--idle-days", type=int, default=0, help="Idle days (default: 0)")

    parser.add_argument("--sigma", type=float, default=7.2)
    parser.add_argument("--coupled-prob", type=float, default=0.9)
    parser.add_argument("--max-prob-base", type=float, default=0.4)
    parser.add_argument("--max-prob-slope", type=float, default=0.6)
    parser.add_argument("--min-prob-ratio", type=float, default=0.8)
    parser.add_argument("--mood-offsets", type=str, default="-0.06,0.0,0.08")
    parser.add_argument("--mood-stay", type=float, default=0.85)
    parser.add_argument("--mood-min", type=int, default=3)
    parser.add_argument("--idle-grace", type=int, default=2)
    parser.add_argument("--idle-per-day", type=float, default=0.02)
    parser.add_argument("--idle-max", type=float, default=0.10)
    parser.add_argument("--seed", type=int, default=1234)
    parser.add_argument("--plot", action="store_true", help="Plot win/lead probability over steps.")
    parser.add_argument("--out", type=str, default=None, help="Save plot to file instead of showing it.")
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    mood_offsets = tuple(float(x.strip()) for x in args.mood_offsets.split(","))
    if len(mood_offsets) != 3:
        raise SystemExit("--mood-offsets needs exactly 3 values")

    params = Params(
        sigma=args.sigma,
        coupled_prob=args.coupled_prob,
        max_prob_base=args.max_prob_base,
        max_prob_slope=args.max_prob_slope,
        min_prob_ratio=args.min_prob_ratio,
        mood_offsets=mood_offsets,
        mood_stay_prob=args.mood_stay,
        mood_min_moves=args.mood_min,
        idle_grace_days=args.idle_grace,
        idle_boost_per_day=args.idle_per_day,
        idle_boost_max=args.idle_max,
    )

    accuracy = build_accuracy_profile(args.steps, acc=args.acc, profile=args.acc_profile)
    grid = build_hex_grid()

    base_rng = random.Random(args.seed)
    wins_you = 0
    wins_rival = 0
    no_result = 0
    total_steps_to_win = 0
    finished_runs = 0

    for _ in range(args.runs):
        run_rng = random.Random(base_rng.random())
        result = simulate_run(
            grid=grid,
            accuracy=accuracy,
            rng=run_rng,
            params=params,
            idle_days=args.idle_days,
            mode=args.mode,
        )
        wins_you += result.wins_you
        wins_rival += result.wins_rival
        if args.mode == "race":
            if result.winner is None:
                no_result += 1
            else:
                total_steps_to_win += result.steps_to_win or 0
                finished_runs += 1

    print("=== Hex Duel Monte Carlo ===")
    print(f"runs={args.runs} steps={args.steps} mode={args.mode} seed={args.seed}")
    print(f"acc_profile={args.acc_profile or args.acc}")
    print(f"idle_days={args.idle_days}")
    print(
        "params: sigma={:.2f} coupled={:.2f} max_base={:.2f} max_slope={:.2f} min_ratio={:.2f}".format(
            params.sigma,
            params.coupled_prob,
            params.max_prob_base,
            params.max_prob_slope,
            params.min_prob_ratio,
        )
    )
    print(
        "mood_offsets={} stay={:.2f} min_moves={} idle_grace={} idle_per_day={:.3f} idle_max={:.2f}".format(
            params.mood_offsets,
            params.mood_stay_prob,
            params.mood_min_moves,
            params.idle_grace_days,
            params.idle_boost_per_day,
            params.idle_boost_max,
        )
    )

    if args.mode == "race":
        win_total = wins_you + wins_rival
        win_rate = wins_you / win_total if win_total else 0.0
        no_rate = no_result / args.runs if args.runs else 0.0
        avg_steps = total_steps_to_win / finished_runs if finished_runs else 0.0
        print(f"player_win_rate={win_rate:.3f} (wins {wins_you}, rival {wins_rival})")
        print(f"no_result_rate={no_rate:.3f}")
        print(f"avg_steps_to_win={avg_steps:.1f}")
    else:
        total_wins = wins_you + wins_rival
        win_rate = wins_you / total_wins if total_wins else 0.0
        print(f"wins_you={wins_you} wins_rival={wins_rival}")
        print(f"player_win_rate={win_rate:.3f}")

    if args.plot:
        probs = monte_carlo_trace(
            runs=args.runs,
            grid=grid,
            accuracy=accuracy,
            params=params,
            idle_days=args.idle_days,
            mode=args.mode,
            seed=args.seed,
        )
        _plot_trace(probs, mode=args.mode, out=args.out)


if __name__ == "__main__":
    main()
