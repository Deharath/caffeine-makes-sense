#!/usr/bin/env python3
"""
Summarize Caffeine Makes Sense dev-panel recordings.

Supports both:
- legacy crash-era schema
- current raw-stim / mask-load / sleep-disruption schema
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from pathlib import Path


def to_float(value, default=0.0):
    try:
        if value is None or value == "":
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def to_int(value, default=0):
    try:
        if value is None or value == "":
            return default
        return int(float(value))
    except (TypeError, ValueError):
        return default


def to_bool(value):
    if value is None:
        return False
    return str(value).strip().lower() in {"1", "true", "yes"}


def fmt_num(value, digits=3):
    if value is None:
        return "n/a"
    return f"{float(value):.{digits}f}"


def normalize_row(row):
    is_new = "raw_stim_load" in row
    raw_stim = to_float(row.get("raw_stim_load", row.get("caffeine_level")))
    mask_load = to_float(row.get("mask_load", row.get("caffeine_level")))
    normalized = {
        "elapsed_min": to_float(row.get("elapsed_min")),
        "game_min": to_float(row.get("game_min")),
        "game_speed": to_float(row.get("game_speed")),
        "stage": (row.get("stage") or "").strip() or "unknown",
        "raw_stim_load": raw_stim,
        "mask_load": mask_load,
        "caffeine_max": to_float(row.get("caffeine_max"), 4.0),
        "mask_pct": to_float(row.get("mask_pct")),
        "frac_of_peak_pct": to_float(row.get("frac_of_peak_pct")),
        "fatigue_pre": to_float(row.get("fatigue_pre")),
        "fatigue_post": to_float(row.get("fatigue_post")),
        "real_fatigue_est": to_float(row.get("real_fatigue_est")),
        "hidden_debt": to_float(row.get("hidden_debt")),
        "stress_total_pct": to_float(row.get("stress_total_pct")),
        "stress_cms_pct": to_float(row.get("stress_cms_pct")),
        "stress_target_pct": to_float(row.get("stress_target_pct")),
        "sleep_disruption_pct": to_float(row.get("sleep_disruption_pct", row.get("sleep_penalty_pct"))),
        "sleep_recovery_penalty_pct": to_float(row.get("sleep_recovery_penalty_pct")),
        "sleep_recovery_fatigue": to_float(row.get("sleep_recovery_fatigue")),
        "sleep_session_min": to_float(row.get("sleep_session_min")),
        "dose_count": to_int(row.get("dose_count")),
        "sleeping": to_bool(row.get("sleeping")),
        "event": (row.get("event") or "").strip(),
        "event_profile": (row.get("event_profile") or "").strip(),
        "legacy_crash_penalty": to_float(row.get("crash_penalty")),
        "legacy_remaining_debt": to_float(row.get("remaining_debt")),
        "legacy_crash_applied": to_float(row.get("crash_applied")),
        "_schema": "current" if is_new else "legacy",
    }
    return normalized


def load_rows(path):
    with path.open("r", encoding="utf-8", errors="replace", newline="") as fh:
        reader = csv.DictReader(fh)
        rows = [normalize_row(row) for row in reader]
    return rows


def build_summary(path, rows):
    if not rows:
        raise ValueError("recording is empty")

    first = rows[0]
    last = rows[-1]
    schema = "current" if any(row["_schema"] == "current" for row in rows) else "legacy"

    events = [
        {
            "elapsed_min": row["elapsed_min"],
            "event": row["event"],
            "profile": row["event_profile"] or None,
            "stage": row["stage"],
            "raw_stim_load": row["raw_stim_load"],
            "fatigue_post": row["fatigue_post"],
        }
        for row in rows
        if row["event"]
    ]

    stage_changes = []
    prev_stage = None
    for row in rows:
        if row["stage"] != prev_stage:
            stage_changes.append(
                {
                    "elapsed_min": row["elapsed_min"],
                    "stage": row["stage"],
                    "raw_stim_load": row["raw_stim_load"],
                    "mask_pct": row["mask_pct"],
                    "fatigue_post": row["fatigue_post"],
                }
            )
            prev_stage = row["stage"]

    peak_raw = max(rows, key=lambda r: r["raw_stim_load"])
    peak_mask = max(rows, key=lambda r: r["mask_load"])
    peak_hidden = max(rows, key=lambda r: r["hidden_debt"])
    peak_stress_total = max(rows, key=lambda r: r["stress_total_pct"])
    peak_stress_cms = max(rows, key=lambda r: r["stress_cms_pct"])
    peak_stress_target = max(rows, key=lambda r: r["stress_target_pct"])
    peak_sleep = max(rows, key=lambda r: r["sleep_disruption_pct"])
    peak_sleep_recovery_penalty = max(rows, key=lambda r: r["sleep_recovery_penalty_pct"])
    peak_sleep_recovery_fatigue = max(rows, key=lambda r: r["sleep_recovery_fatigue"])
    min_fatigue = min(rows, key=lambda r: r["fatigue_post"])
    max_fatigue = max(rows, key=lambda r: r["fatigue_post"])

    stage_counts = {}
    stage_means = {}
    for row in rows:
        stage = row["stage"]
        bucket = stage_means.setdefault(
            stage,
            {
                "rows": 0,
                "raw_stim_load_sum": 0.0,
                "mask_load_sum": 0.0,
                "mask_pct_sum": 0.0,
                "fatigue_post_sum": 0.0,
                "hidden_debt_sum": 0.0,
                "stress_total_pct_sum": 0.0,
                "stress_cms_pct_sum": 0.0,
                "stress_target_pct_sum": 0.0,
                "sleep_disruption_pct_sum": 0.0,
                "sleep_recovery_penalty_pct_sum": 0.0,
                "sleep_recovery_fatigue_sum": 0.0,
            },
        )
        bucket["rows"] += 1
        bucket["raw_stim_load_sum"] += row["raw_stim_load"]
        bucket["mask_load_sum"] += row["mask_load"]
        bucket["mask_pct_sum"] += row["mask_pct"]
        bucket["fatigue_post_sum"] += row["fatigue_post"]
        bucket["hidden_debt_sum"] += row["hidden_debt"]
        bucket["stress_total_pct_sum"] += row["stress_total_pct"]
        bucket["stress_cms_pct_sum"] += row["stress_cms_pct"]
        bucket["stress_target_pct_sum"] += row["stress_target_pct"]
        bucket["sleep_disruption_pct_sum"] += row["sleep_disruption_pct"]
        bucket["sleep_recovery_penalty_pct_sum"] += row["sleep_recovery_penalty_pct"]
        bucket["sleep_recovery_fatigue_sum"] += row["sleep_recovery_fatigue"]

    for stage, bucket in stage_means.items():
        rows_n = max(1, bucket["rows"])
        stage_counts[stage] = bucket["rows"]
        stage_means[stage] = {
            "rows": bucket["rows"],
            "raw_stim_load_avg": bucket["raw_stim_load_sum"] / rows_n,
            "mask_load_avg": bucket["mask_load_sum"] / rows_n,
            "mask_pct_avg": bucket["mask_pct_sum"] / rows_n,
            "fatigue_post_avg": bucket["fatigue_post_sum"] / rows_n,
            "hidden_debt_avg": bucket["hidden_debt_sum"] / rows_n,
            "stress_total_pct_avg": bucket["stress_total_pct_sum"] / rows_n,
            "stress_cms_pct_avg": bucket["stress_cms_pct_sum"] / rows_n,
            "stress_target_pct_avg": bucket["stress_target_pct_sum"] / rows_n,
            "sleep_disruption_pct_avg": bucket["sleep_disruption_pct_sum"] / rows_n,
            "sleep_recovery_penalty_pct_avg": bucket["sleep_recovery_penalty_pct_sum"] / rows_n,
            "sleep_recovery_fatigue_avg": bucket["sleep_recovery_fatigue_sum"] / rows_n,
        }

    return {
        "file": str(path),
        "schema": schema,
        "rows": len(rows),
        "time_window": {
            "elapsed_start_min": first["elapsed_min"],
            "elapsed_end_min": last["elapsed_min"],
            "game_start_min": first["game_min"],
            "game_end_min": last["game_min"],
        },
        "fatigue": {
            "start": first["fatigue_post"],
            "min": min_fatigue["fatigue_post"],
            "min_at_elapsed_min": min_fatigue["elapsed_min"],
            "end": last["fatigue_post"],
            "max": max_fatigue["fatigue_post"],
            "max_at_elapsed_min": max_fatigue["elapsed_min"],
        },
        "raw_stim": {
            "peak": peak_raw["raw_stim_load"],
            "peak_at_elapsed_min": peak_raw["elapsed_min"],
            "end": last["raw_stim_load"],
        },
        "mask": {
            "peak_load": peak_mask["mask_load"],
            "peak_load_at_elapsed_min": peak_mask["elapsed_min"],
            "peak_pct": max(row["mask_pct"] for row in rows),
            "end_load": last["mask_load"],
            "end_pct": last["mask_pct"],
        },
        "hidden_debt": {
            "peak": peak_hidden["hidden_debt"],
            "peak_at_elapsed_min": peak_hidden["elapsed_min"],
            "end": last["hidden_debt"],
        },
        "stress": {
            "peak_total_pct": peak_stress_total["stress_total_pct"],
            "peak_total_at_elapsed_min": peak_stress_total["elapsed_min"],
            "peak_cms_pct": peak_stress_cms["stress_cms_pct"],
            "peak_cms_at_elapsed_min": peak_stress_cms["elapsed_min"],
            "peak_target_pct": peak_stress_target["stress_target_pct"],
            "peak_target_at_elapsed_min": peak_stress_target["elapsed_min"],
            "end_total_pct": last["stress_total_pct"],
            "end_cms_pct": last["stress_cms_pct"],
        },
        "sleep_disruption": {
            "peak_pct": peak_sleep["sleep_disruption_pct"],
            "peak_at_elapsed_min": peak_sleep["elapsed_min"],
            "end_pct": last["sleep_disruption_pct"],
            "peak_recovery_penalty_pct": peak_sleep_recovery_penalty["sleep_recovery_penalty_pct"],
            "peak_recovery_penalty_at_elapsed_min": peak_sleep_recovery_penalty["elapsed_min"],
            "end_recovery_penalty_pct": last["sleep_recovery_penalty_pct"],
            "peak_recovery_fatigue": peak_sleep_recovery_fatigue["sleep_recovery_fatigue"],
            "peak_recovery_fatigue_at_elapsed_min": peak_sleep_recovery_fatigue["elapsed_min"],
            "end_recovery_fatigue": last["sleep_recovery_fatigue"],
            "sleeping_rows": sum(1 for row in rows if row["sleeping"]),
        },
        "events": events,
        "stage_changes": stage_changes,
        "stage_counts": stage_counts,
        "stage_means": stage_means,
        "legacy": {
            "peak_crash_penalty": max(row["legacy_crash_penalty"] for row in rows),
            "peak_remaining_debt": max(row["legacy_remaining_debt"] for row in rows),
            "peak_crash_applied": max(row["legacy_crash_applied"] for row in rows),
        },
        "sample_rows": [],
    }


def select_sample_rows(rows, limit):
    if limit <= 0 or not rows:
        return []
    if limit >= len(rows):
        picked = rows
    else:
        last_index = len(rows) - 1
        indices = {0, last_index}
        if limit > 2:
            for i in range(1, limit - 1):
                idx = int(round(i * last_index / (limit - 1)))
                indices.add(idx)
        picked = [rows[i] for i in sorted(indices)]
    return [
        {
            "elapsed_min": row["elapsed_min"],
            "stage": row["stage"],
            "raw_stim_load": row["raw_stim_load"],
            "mask_load": row["mask_load"],
            "mask_pct": row["mask_pct"],
            "fatigue_pre": row["fatigue_pre"],
            "fatigue_post": row["fatigue_post"],
            "hidden_debt": row["hidden_debt"],
            "stress_total_pct": row["stress_total_pct"],
            "stress_cms_pct": row["stress_cms_pct"],
            "stress_target_pct": row["stress_target_pct"],
            "sleep_disruption_pct": row["sleep_disruption_pct"],
            "sleep_recovery_penalty_pct": row["sleep_recovery_penalty_pct"],
            "sleep_recovery_fatigue": row["sleep_recovery_fatigue"],
            "event": row["event"] or None,
            "event_profile": row["event_profile"] or None,
        }
        for row in picked
    ]


def print_text(summary):
    tw = summary["time_window"]
    fatigue = summary["fatigue"]
    raw_stim = summary["raw_stim"]
    mask = summary["mask"]
    hidden = summary["hidden_debt"]
    stress = summary["stress"]
    sleep = summary["sleep_disruption"]

    print(f"file: {summary['file']}")
    print(f"schema: {summary['schema']} rows={summary['rows']} elapsed={fmt_num(tw['elapsed_end_min'], 1)} min")
    print(
        "fatigue:"
        f" start={fmt_num(fatigue['start'], 4)}"
        f" min={fmt_num(fatigue['min'], 4)}@{fmt_num(fatigue['min_at_elapsed_min'], 1)}"
        f" end={fmt_num(fatigue['end'], 4)}"
        f" max={fmt_num(fatigue['max'], 4)}@{fmt_num(fatigue['max_at_elapsed_min'], 1)}"
    )
    print(
        "stim:"
        f" peak={fmt_num(raw_stim['peak'], 4)}@{fmt_num(raw_stim['peak_at_elapsed_min'], 1)}"
        f" end={fmt_num(raw_stim['end'], 4)}"
    )
    print(
        "mask:"
        f" peak_load={fmt_num(mask['peak_load'], 4)}@{fmt_num(mask['peak_load_at_elapsed_min'], 1)}"
        f" peak_pct={fmt_num(mask['peak_pct'], 2)}"
        f" end_load={fmt_num(mask['end_load'], 4)}"
        f" end_pct={fmt_num(mask['end_pct'], 2)}"
    )
    print(
        "hidden_debt:"
        f" peak={fmt_num(hidden['peak'], 4)}@{fmt_num(hidden['peak_at_elapsed_min'], 1)}"
        f" end={fmt_num(hidden['end'], 4)}"
    )
    print(
        "stress:"
        f" peak_total={fmt_num(stress['peak_total_pct'], 2)}%@{fmt_num(stress['peak_total_at_elapsed_min'], 1)}"
        f" peak_cms={fmt_num(stress['peak_cms_pct'], 2)}%@{fmt_num(stress['peak_cms_at_elapsed_min'], 1)}"
        f" peak_target={fmt_num(stress['peak_target_pct'], 2)}%@{fmt_num(stress['peak_target_at_elapsed_min'], 1)}"
        f" end_total={fmt_num(stress['end_total_pct'], 2)}%"
        f" end_cms={fmt_num(stress['end_cms_pct'], 2)}%"
    )
    print(
        "sleep_disruption:"
        f" peak_pct={fmt_num(sleep['peak_pct'], 2)}@{fmt_num(sleep['peak_at_elapsed_min'], 1)}"
        f" end_pct={fmt_num(sleep['end_pct'], 2)}"
        f" peak_recovery_penalty={fmt_num(sleep['peak_recovery_penalty_pct'], 2)}@{fmt_num(sleep['peak_recovery_penalty_at_elapsed_min'], 1)}"
        f" end_recovery_penalty={fmt_num(sleep['end_recovery_penalty_pct'], 2)}"
        f" peak_recovery_loss={fmt_num(sleep['peak_recovery_fatigue'], 4)}@{fmt_num(sleep['peak_recovery_fatigue_at_elapsed_min'], 1)}"
        f" end_recovery_loss={fmt_num(sleep['end_recovery_fatigue'], 4)}"
        f" sleeping_rows={sleep['sleeping_rows']}"
    )

    if summary["events"]:
        print("events:")
        for event in summary["events"]:
            profile = f" profile={event['profile']}" if event["profile"] else ""
            print(
                f"  {fmt_num(event['elapsed_min'], 1)} min"
                f" {event['event']}{profile}"
                f" stage={event['stage']}"
                f" stim={fmt_num(event['raw_stim_load'], 4)}"
                f" fatigue={fmt_num(event['fatigue_post'], 4)}"
            )

    if summary["stage_changes"]:
        print("stage_changes:")
        for change in summary["stage_changes"]:
            print(
                f"  {fmt_num(change['elapsed_min'], 1)} min"
                f" {change['stage']}"
                f" stim={fmt_num(change['raw_stim_load'], 4)}"
                f" mask={fmt_num(change['mask_pct'], 2)}%"
                f" fatigue={fmt_num(change['fatigue_post'], 4)}"
            )

    if summary["stage_means"]:
        print("stage_means:")
        for stage in sorted(summary["stage_means"].keys()):
            data = summary["stage_means"][stage]
            print(
                f"  {stage}:"
                f" rows={data['rows']}"
                f" stim_avg={fmt_num(data['raw_stim_load_avg'], 4)}"
                f" mask_avg={fmt_num(data['mask_load_avg'], 4)}"
                f" mask_pct_avg={fmt_num(data['mask_pct_avg'], 2)}"
                f" fatigue_avg={fmt_num(data['fatigue_post_avg'], 4)}"
                f" hidden_avg={fmt_num(data['hidden_debt_avg'], 4)}"
                f" stress_total_avg={fmt_num(data['stress_total_pct_avg'], 2)}"
                f" stress_cms_avg={fmt_num(data['stress_cms_pct_avg'], 2)}"
                f" sleep_disruption_avg={fmt_num(data['sleep_disruption_pct_avg'], 2)}"
                f" recovery_penalty_avg={fmt_num(data['sleep_recovery_penalty_pct_avg'], 2)}"
                f" recovery_loss_avg={fmt_num(data['sleep_recovery_fatigue_avg'], 4)}"
            )

    if summary["sample_rows"]:
        print("samples:")
        for row in summary["sample_rows"]:
            profile = f"/{row['event_profile']}" if row["event_profile"] else ""
            event = f" event={row['event']}{profile}" if row["event"] else ""
            print(
                f"  {fmt_num(row['elapsed_min'], 1)} min"
                f" {row['stage']}"
                f" stim={fmt_num(row['raw_stim_load'], 4)}"
                f" mask={fmt_num(row['mask_load'], 4)}"
                f" mask_pct={fmt_num(row['mask_pct'], 2)}"
                f" pre={fmt_num(row['fatigue_pre'], 4)}"
                f" post={fmt_num(row['fatigue_post'], 4)}"
                f" hidden={fmt_num(row['hidden_debt'], 4)}"
                f" stress_total={fmt_num(row['stress_total_pct'], 2)}"
                f" stress_cms={fmt_num(row['stress_cms_pct'], 2)}"
                f" stress_target={fmt_num(row['stress_target_pct'], 2)}"
                f" sleep_disruption={fmt_num(row['sleep_disruption_pct'], 2)}"
                f" recovery_penalty={fmt_num(row['sleep_recovery_penalty_pct'], 2)}"
                f" recovery_loss={fmt_num(row['sleep_recovery_fatigue'], 4)}"
                f"{event}"
            )


def main():
    parser = argparse.ArgumentParser(description="Summarize Caffeine Makes Sense recording CSV files.")
    parser.add_argument("path", help="Path to a cms_recording_*.csv file")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of compact text")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON output")
    parser.add_argument("--samples", type=int, default=8, help="Number of evenly spaced sample rows to include")
    args = parser.parse_args()

    path = Path(args.path)
    rows = load_rows(path)
    summary = build_summary(path, rows)
    summary["sample_rows"] = select_sample_rows(rows, args.samples)

    if args.json:
        indent = 2 if args.pretty else None
        json.dump(summary, sys.stdout, indent=indent, sort_keys=False)
        sys.stdout.write("\n")
        return

    print_text(summary)


if __name__ == "__main__":
    main()
