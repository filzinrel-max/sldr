#!/usr/bin/env python3
"""Prebuild compact per-difficulty chart JSON for LSL runtime."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from _songlib import extract_notes_sections, extract_tag, parse_bpms, read_text_file, slugify


def clamp_float(value: float, low: float, high: float) -> float:
    if value < low:
        return low
    if value > high:
        return high
    return value


def parse_meter(value: str) -> int:
    try:
        return int(float(value.strip()))
    except ValueError:
        return 0


def beat_to_seconds(beat_value: float, bpm_pairs: list[dict[str, float]]) -> float:
    if not bpm_pairs:
        return beat_value * 0.5

    sorted_pairs = sorted(bpm_pairs, key=lambda entry: entry["beat"])
    previous_beat = float(sorted_pairs[0]["beat"])
    previous_bpm = float(sorted_pairs[0]["bpm"])
    seconds = 0.0

    if beat_value < previous_beat:
        return (beat_value - previous_beat) * (60.0 / previous_bpm)

    for entry in sorted_pairs[1:]:
        segment_beat = float(entry["beat"])
        segment_bpm = float(entry["bpm"])
        if beat_value <= segment_beat:
            seconds += (beat_value - previous_beat) * (60.0 / previous_bpm)
            return seconds
        seconds += (segment_beat - previous_beat) * (60.0 / previous_bpm)
        previous_beat = segment_beat
        previous_bpm = segment_bpm

    seconds += (beat_value - previous_beat) * (60.0 / previous_bpm)
    return seconds


def iter_measure_rows(note_data: str) -> list[tuple[int, list[str]]]:
    out: list[tuple[int, list[str]]] = []
    raw_measures = note_data.split(",")
    measure_index = 0
    for raw_measure in raw_measures:
        rows: list[str] = []
        for line in raw_measure.splitlines():
            value = line.strip()
            if not value or value.startswith("//"):
                continue
            rows.append(value)
        if rows:
            out.append((measure_index, rows))
        measure_index += 1
    return out


def parse_chart_section(
    note_data: str,
    offset_seconds: float,
    bpm_pairs: list[dict[str, float]],
) -> dict[str, Any]:
    note_events: list[tuple[int, int, int, int, int]] = []
    hold_events: list[tuple[int, int, int, int]] = []

    hold_serial = 1
    open_hold_ids = [-1, -1, -1, -1]
    open_hold_starts = [0, 0, 0, 0]

    total_rows = 0
    chord_rows = 0
    max_simultaneous = 0
    offbeat_notes = 0
    latest_note_cs = 0
    duration_cs = 0

    for measure_index, rows in iter_measure_rows(note_data):
        row_count = len(rows)
        if row_count <= 0:
            continue

        for row_index, raw_row in enumerate(rows):
            if len(raw_row) < 4:
                continue

            row = raw_row[:4]
            beat = (float(measure_index) * 4.0) + ((4.0 * float(row_index)) / float(row_count))
            note_time = beat_to_seconds(beat, bpm_pairs) - offset_seconds
            note_cs = int(round(note_time * 100.0))
            if note_cs > latest_note_cs:
                latest_note_cs = note_cs
            if note_cs > duration_cs:
                duration_cs = note_cs

            starts_in_row = 0
            row_cells: list[str] = []
            for lane in range(4):
                cell = row[lane]
                row_cells.append(cell)
                if cell in {"1", "2", "4"}:
                    starts_in_row += 1

            row_flags = 0
            if ((row_index * 4) % row_count) != 0:
                row_flags |= 2
            if starts_in_row >= 2:
                row_flags |= 1
                chord_rows += 1
            if starts_in_row > max_simultaneous:
                max_simultaneous = starts_in_row
            if starts_in_row > 0:
                total_rows += 1

            for lane in range(4):
                symbol = row_cells[lane]
                if symbol == "1":
                    note_events.append((note_cs, lane, 1, -1, row_flags))
                    if row_flags & 2:
                        offbeat_notes += 1
                elif symbol in {"2", "4"}:
                    hold_id = hold_serial
                    hold_serial += 1
                    open_hold_ids[lane] = hold_id
                    open_hold_starts[lane] = note_cs
                    note_events.append((note_cs, lane, 2, hold_id, row_flags))
                    if row_flags & 2:
                        offbeat_notes += 1
                elif symbol == "3":
                    active_hold_id = open_hold_ids[lane]
                    if active_hold_id >= 0:
                        hold_start = open_hold_starts[lane]
                        hold_events.append((active_hold_id, lane, hold_start, note_cs))
                        if note_cs > duration_cs:
                            duration_cs = note_cs
                        open_hold_ids[lane] = -1
                        open_hold_starts[lane] = 0

    for lane in range(4):
        dangling_hold_id = open_hold_ids[lane]
        if dangling_hold_id >= 0:
            hold_end = latest_note_cs + 25
            hold_start = open_hold_starts[lane]
            if hold_end < hold_start:
                hold_end = hold_start
            hold_events.append((dangling_hold_id, lane, hold_start, hold_end))
            if hold_end > duration_cs:
                duration_cs = hold_end

    total_notes = len(note_events)
    total_holds = len(hold_events)

    duration_seconds = max(duration_cs / 100.0, 0.0)
    radar_duration = duration_seconds
    if radar_duration < 1.0:
        radar_duration = 1.0

    note_rate = float(total_notes) / radar_duration
    stream = clamp_float(note_rate / 6.0, 0.0, 1.0)
    voltage = clamp_float(float(max_simultaneous) / 4.0, 0.0, 1.0)
    air = 0.0
    freeze = 0.0
    chaos = 0.0
    if total_rows > 0:
        air = clamp_float(float(chord_rows) / float(total_rows), 0.0, 1.0)
    if total_notes > 0:
        freeze = clamp_float(float(total_holds) / float(total_notes), 0.0, 1.0)
        chaos = clamp_float(float(offbeat_notes) / float(total_notes), 0.0, 1.0)

    return {
        "durationCs": duration_cs,
        "duration": round(duration_seconds, 3),
        "totalRows": total_rows,
        "chordRows": chord_rows,
        "maxSimultaneous": max_simultaneous,
        "offbeatNotes": offbeat_notes,
        "notes": note_events,
        "holds": hold_events,
        "radarSong": [
            round(stream, 6),
            round(voltage, 6),
            round(air, 6),
            round(freeze, 6),
            round(chaos, 6),
        ],
    }


def encode_records(rows: list[tuple[int, ...]]) -> str:
    if not rows:
        return ""
    return ";".join(",".join(str(value) for value in row) for row in rows)


def make_chart_payload(song_id: str, difficulty: str, meter: int, parsed: dict[str, Any]) -> dict[str, Any]:
    return {
        "v": 1,
        "fmt": "sldr-chart-v1",
        "id": song_id,
        "d": difficulty,
        "m": meter,
        "du": parsed["duration"],
        "tr": parsed["totalRows"],
        "ch": parsed["chordRows"],
        "mx": parsed["maxSimultaneous"],
        "of": parsed["offbeatNotes"],
        "sr": parsed["radarSong"],
        "n": encode_records(parsed["notes"]),
        "h": encode_records(parsed["holds"]),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        default="game-data/song-manifest.json",
        help="Input/output full manifest path (default: game-data/song-manifest.json)",
    )
    parser.add_argument(
        "--compact-manifest",
        default="game-data/song-manifest.lsl.json",
        help="Input/output compact manifest path (default: game-data/song-manifest.lsl.json)",
    )
    parser.add_argument(
        "--charts-root",
        default="game-data/charts",
        help="Output directory for generated chart JSON (default: game-data/charts)",
    )
    parser.add_argument(
        "--max-bytes",
        type=int,
        default=15000,
        help="Warn when a generated chart file exceeds this byte size (default: 15000)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest_path = Path(args.manifest).resolve()
    compact_manifest_path = Path(args.compact_manifest).resolve()
    charts_root = Path(args.charts_root).resolve()

    if not manifest_path.exists():
        raise SystemExit(f"manifest not found: {manifest_path}")
    if not compact_manifest_path.exists():
        raise SystemExit(f"compact manifest not found: {compact_manifest_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    compact_manifest = json.loads(compact_manifest_path.read_text(encoding="utf-8"))
    compact_index_by_id = {
        song.get("id", ""): song for song in compact_manifest.get("songs", []) if isinstance(song, dict)
    }

    generated = 0
    warnings: list[str] = []

    for song in manifest.get("songs", []):
        if not isinstance(song, dict):
            continue

        song_id = str(song.get("id", "")).strip()
        paths = song.get("paths", {})
        sm_rel = ""
        if isinstance(paths, dict):
            sm_rel = str(paths.get("sm", "")).strip()
        if song_id == "" or sm_rel == "":
            continue

        sm_path = (manifest_path.parent.parent / sm_rel).resolve()
        if not sm_path.exists():
            continue

        sm_text = read_text_file(sm_path)
        bpm_pairs = parse_bpms(extract_tag(sm_text, "BPMS"))
        offset_raw = extract_tag(sm_text, "OFFSET")
        try:
            offset_seconds = float(offset_raw) if offset_raw else 0.0
        except ValueError:
            offset_seconds = 0.0

        sections = extract_notes_sections(sm_text)
        singles = [section for section in sections if section["step_type"].strip().lower() == "dance-single"]
        if not singles:
            continue

        chart_map: dict[str, str] = {}
        used_chart_names: set[str] = set()
        for section in singles:
            difficulty = section["difficulty"].strip() or "Unknown"
            meter = parse_meter(section["meter"])
            parsed = parse_chart_section(section["note_data"], offset_seconds=offset_seconds, bpm_pairs=bpm_pairs)
            chart_payload = make_chart_payload(song_id=song_id, difficulty=difficulty, meter=meter, parsed=parsed)

            diff_slug = slugify(difficulty)
            chart_name = diff_slug
            suffix = 2
            while chart_name in used_chart_names:
                chart_name = f"{diff_slug}-{suffix}"
                suffix += 1
            used_chart_names.add(chart_name)

            chart_rel = f"game-data/charts/{song_id}/{chart_name}.chart.json"
            chart_abs = (manifest_path.parent.parent / chart_rel).resolve()
            chart_abs.parent.mkdir(parents=True, exist_ok=True)
            encoded = json.dumps(chart_payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
            chart_abs.write_bytes(encoded)

            generated += 1
            chart_map[difficulty] = chart_rel
            if len(encoded) > args.max_bytes:
                warnings.append(
                    f"{song_id} [{difficulty}] chart payload {len(encoded)} bytes exceeds {args.max_bytes}"
                )

        song["chartJsonByDifficulty"] = chart_map

        compact_song = compact_index_by_id.get(song_id)
        if compact_song is not None:
            compact_song["cj"] = chart_map

    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    compact_manifest_path.write_text(
        json.dumps(compact_manifest, separators=(",", ":"), ensure_ascii=False), encoding="utf-8"
    )

    print(f"Generated chart JSON files: {generated}")
    print(f"Updated full manifest: {manifest_path.as_posix()}")
    print(f"Updated compact manifest: {compact_manifest_path.as_posix()}")
    if warnings:
        print("WARNINGS:")
        for warning in warnings:
            print(f"  - {warning}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
