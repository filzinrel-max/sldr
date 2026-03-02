#!/usr/bin/env python3
"""Prebuild chunked sparse per-difficulty chart payloads for LSL runtime."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from _songlib import extract_notes_sections, extract_tag, parse_bpms, read_text_file, slugify


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


def bit_count4(mask: int) -> int:
    count = 0
    if mask & 1:
        count += 1
    if mask & 2:
        count += 1
    if mask & 4:
        count += 1
    if mask & 8:
        count += 1
    return count


def merge_event(
    events_by_time: dict[int, tuple[int, int, int]],
    time_cs: int,
    press_mask: int,
    hold_start_mask: int,
    hold_end_mask: int,
) -> None:
    previous = events_by_time.get(time_cs, (0, 0, 0))
    events_by_time[time_cs] = (
        previous[0] | press_mask,
        previous[1] | hold_start_mask,
        previous[2] | hold_end_mask,
    )


def parse_chart_section(
    note_data: str,
    offset_seconds: float,
    bpm_pairs: list[dict[str, float]],
) -> dict[str, Any]:
    events_by_time: dict[int, tuple[int, int, int]] = {}

    open_holds = [False, False, False, False]
    latest_note_cs = 0
    duration_cs = 0

    total_rows = 0
    chord_rows = 0
    max_simultaneous = 0
    offbeat_notes = 0
    total_notes = 0
    total_holds = 0

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

            press_mask = 0
            hold_start_mask = 0
            hold_end_mask = 0

            for lane in range(4):
                bit = 1 << lane
                symbol = row[lane]
                if symbol == "1":
                    press_mask |= bit
                elif symbol in {"2", "4"}:
                    press_mask |= bit
                    hold_start_mask |= bit
                    open_holds[lane] = True
                    total_holds += 1
                elif symbol == "3":
                    if open_holds[lane]:
                        hold_end_mask |= bit
                        open_holds[lane] = False

            starts_in_row = bit_count4(press_mask)
            if starts_in_row > 0:
                total_rows += 1
                total_notes += starts_in_row
                if starts_in_row >= 2:
                    chord_rows += 1
                if starts_in_row > max_simultaneous:
                    max_simultaneous = starts_in_row
                if ((row_index * 4) % row_count) != 0:
                    offbeat_notes += starts_in_row
                if note_cs > latest_note_cs:
                    latest_note_cs = note_cs

            if (press_mask | hold_start_mask | hold_end_mask) != 0:
                merge_event(events_by_time, note_cs, press_mask, hold_start_mask, hold_end_mask)
                if note_cs > duration_cs:
                    duration_cs = note_cs

    for lane in range(4):
        if open_holds[lane]:
            hold_end = latest_note_cs + 25
            merge_event(events_by_time, hold_end, 0, 0, 1 << lane)
            if hold_end > duration_cs:
                duration_cs = hold_end

    sorted_times = sorted(events_by_time.keys())
    events: list[tuple[int, int, int, int]] = []
    for time_cs in sorted_times:
        masks = events_by_time[time_cs]
        events.append((time_cs, masks[0], masks[1], masks[2]))

    duration_seconds = 0.0
    if duration_cs > 0:
        duration_seconds = round(duration_cs / 100.0, 3)

    return {
        "durationCs": duration_cs,
        "duration": duration_seconds,
        "totalRows": total_rows,
        "chordRows": chord_rows,
        "maxSimultaneous": max_simultaneous,
        "offbeatNotes": offbeat_notes,
        "totalNotes": total_notes,
        "totalHolds": total_holds,
        "events": events,
    }


def encode_event_deltas(events: list[tuple[int, int, int, int]]) -> list[str]:
    rows: list[str] = []
    previous_time = 0
    for time_cs, press_mask, hold_start_mask, hold_end_mask in events:
        delta_cs = time_cs - previous_time
        previous_time = time_cs
        rows.append(f"{delta_cs},{press_mask},{hold_start_mask},{hold_end_mask}")
    return rows


def split_rows_into_chunks(rows: list[str], max_chunk_bytes: int) -> list[str]:
    if not rows:
        return []

    chunks: list[str] = []
    current_rows: list[str] = []
    current_bytes = 0

    for row in rows:
        piece = row + ";"
        piece_bytes = len(piece.encode("utf-8"))
        if current_rows and (current_bytes + piece_bytes) > max_chunk_bytes:
            chunks.append("".join(current_rows))
            current_rows = [piece]
            current_bytes = piece_bytes
        else:
            current_rows.append(piece)
            current_bytes += piece_bytes

    if current_rows:
        chunks.append("".join(current_rows))
    return chunks


def make_chart_index_payload(
    song_id: str,
    difficulty: str,
    meter: int,
    parsed: dict[str, Any],
    chunk_file_names: list[str],
) -> dict[str, Any]:
    return {
        "v": 2,
        "fmt": "sldr-chart-chunks-v1",
        "id": song_id,
        "d": difficulty,
        "m": meter,
        "du": parsed["duration"],
        "n": parsed["totalNotes"],
        "h": parsed["totalHolds"],
        "c": chunk_file_names,
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
        help="Output directory for generated chart payloads (default: game-data/charts)",
    )
    parser.add_argument(
        "--chunk-max-bytes",
        type=int,
        default=3200,
        help="Max bytes per chunk payload (default: 3200)",
    )
    parser.add_argument(
        "--max-index-bytes",
        type=int,
        default=12000,
        help="Warn when an index payload exceeds this size (default: 12000)",
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

    generated_indexes = 0
    generated_chunks = 0
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
        song_chart_dir = charts_root / song_id
        song_chart_dir.mkdir(parents=True, exist_ok=True)

        for section in singles:
            difficulty = section["difficulty"].strip() or "Unknown"
            meter = parse_meter(section["meter"])
            parsed = parse_chart_section(section["note_data"], offset_seconds=offset_seconds, bpm_pairs=bpm_pairs)

            diff_slug = slugify(difficulty)
            chart_name = diff_slug
            suffix = 2
            while chart_name in used_chart_names:
                chart_name = f"{diff_slug}-{suffix}"
                suffix += 1
            used_chart_names.add(chart_name)

            encoded_rows = encode_event_deltas(parsed["events"])
            chunk_payloads = split_rows_into_chunks(encoded_rows, max_chunk_bytes=args.chunk_max_bytes)

            chunk_file_names: list[str] = []
            for chunk_index, chunk_payload in enumerate(chunk_payloads, start=1):
                chunk_name = f"{chart_name}.chart.c{chunk_index:03d}.txt"
                chunk_path = song_chart_dir / chunk_name
                chunk_path.write_text(chunk_payload, encoding="utf-8")
                chunk_file_names.append(chunk_name)
                generated_chunks += 1

            index_payload = make_chart_index_payload(
                song_id=song_id,
                difficulty=difficulty,
                meter=meter,
                parsed=parsed,
                chunk_file_names=chunk_file_names,
            )

            index_name = f"{chart_name}.chart.idx.json"
            index_path = song_chart_dir / index_name
            index_encoded = json.dumps(index_payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
            index_path.write_bytes(index_encoded)
            generated_indexes += 1

            if len(index_encoded) > args.max_index_bytes:
                warnings.append(
                    f"{song_id} [{difficulty}] chart index {len(index_encoded)} bytes exceeds {args.max_index_bytes}"
                )

            chart_rel = f"game-data/charts/{song_id}/{index_name}"
            chart_map[difficulty] = chart_rel

        song["chartJsonByDifficulty"] = chart_map
        compact_song = compact_index_by_id.get(song_id)
        if compact_song is not None:
            compact_song["cj"] = chart_map

    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    compact_manifest_path.write_text(
        json.dumps(compact_manifest, separators=(",", ":"), ensure_ascii=False), encoding="utf-8"
    )

    print(f"Generated chart index files: {generated_indexes}")
    print(f"Generated chart chunk files: {generated_chunks}")
    print(f"Updated full manifest: {manifest_path.as_posix()}")
    print(f"Updated compact manifest: {compact_manifest_path.as_posix()}")
    if warnings:
        print("WARNINGS:")
        for warning in warnings:
            print(f"  - {warning}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
