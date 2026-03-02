#!/usr/bin/env python3
"""Shared helpers for local song processing scripts."""

from __future__ import annotations

import re
import unicodedata
from pathlib import Path
from typing import Any

NOTE_ACTIVE = {"1", "2", "4"}


def slugify(value: str) -> str:
    text = unicodedata.normalize("NFKD", value)
    text = text.encode("ascii", "ignore").decode("ascii")
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return text or "song"


def list_song_dirs(songs_root: Path) -> list[Path]:
    return sorted((p for p in songs_root.iterdir() if p.is_dir()), key=lambda p: p.name.lower())


def relative_posix(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def read_text_file(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def pick_preferred_file(song_dir: Path, extension: str) -> Path | None:
    ext = extension.lower()
    candidates = sorted(
        (p for p in song_dir.iterdir() if p.is_file() and p.suffix.lower() == ext),
        key=lambda p: p.name.lower(),
    )
    if not candidates:
        return None

    preferred = [p for p in candidates if p.stem.lower() == song_dir.name.lower()]
    return preferred[0] if preferred else candidates[0]


def extract_tag(sm_text: str, tag: str) -> str | None:
    pattern = re.compile(rf"#{re.escape(tag)}:(.*?);", flags=re.IGNORECASE | re.DOTALL)
    match = pattern.search(sm_text)
    if not match:
        return None
    return match.group(1).strip()


def parse_bpms(raw_bpms: str | None) -> list[dict[str, float]]:
    if not raw_bpms:
        return []
    pairs: list[dict[str, float]] = []
    for piece in raw_bpms.split(","):
        item = piece.strip()
        if not item or "=" not in item:
            continue
        beat_text, bpm_text = item.split("=", 1)
        try:
            pairs.append({"beat": float(beat_text.strip()), "bpm": float(bpm_text.strip())})
        except ValueError:
            continue
    return sorted(pairs, key=lambda entry: entry["beat"])


def extract_notes_sections(sm_text: str) -> list[dict[str, str]]:
    sections: list[dict[str, str]] = []
    for match in re.finditer(r"#NOTES:(.*?);", sm_text, flags=re.IGNORECASE | re.DOTALL):
        body = match.group(1)
        fields: list[str] = []
        remaining = body
        for _ in range(5):
            idx = remaining.find(":")
            if idx < 0:
                break
            fields.append(remaining[:idx].strip())
            remaining = remaining[idx + 1 :]
        if len(fields) != 5:
            continue
        sections.append(
            {
                "step_type": fields[0],
                "description": fields[1],
                "difficulty": fields[2],
                "meter": fields[3],
                "radar": fields[4],
                "note_data": remaining.strip(),
            }
        )
    return sections


def _iter_measure_rows(note_data: str) -> tuple[int, list[str]]:
    raw_measures = note_data.split(",")
    measure_index = 0
    for raw_measure in raw_measures:
        lines = []
        for line in raw_measure.splitlines():
            value = line.strip()
            if not value or value.startswith("//"):
                continue
            lines.append(value)
        if lines:
            yield measure_index, lines
        measure_index += 1


def summarize_single_chart(note_data: str) -> dict[str, Any]:
    measures = 0
    rows = 0
    step_rows = 0
    notes = 0
    taps = 0
    holds = 0
    jumps = 0
    max_simultaneous = 0

    for _, measure_rows in _iter_measure_rows(note_data):
        measures += 1
        rows += len(measure_rows)
        for row in measure_rows:
            lane_values = row[:4]
            starts_in_row = 0
            taps_in_row = 0
            holds_in_row = 0
            for value in lane_values:
                if value == "1":
                    taps_in_row += 1
                    starts_in_row += 1
                elif value in {"2", "4"}:
                    holds_in_row += 1
                    starts_in_row += 1
            if starts_in_row > 0:
                step_rows += 1
            if starts_in_row >= 2:
                jumps += 1
            max_simultaneous = max(max_simultaneous, starts_in_row)
            taps += taps_in_row
            holds += holds_in_row
            notes += taps_in_row + holds_in_row

    beat_span = round(measures * 4.0, 6)
    note_density = round(notes / beat_span, 6) if beat_span > 0 else 0.0
    return {
        "measures": measures,
        "rows": rows,
        "stepRows": step_rows,
        "notes": notes,
        "taps": taps,
        "holds": holds,
        "jumps": jumps,
        "maxSimultaneous": max_simultaneous,
        "beatSpan": beat_span,
        "notesPerBeat": note_density,
    }


def parse_single_charts(sm_text: str) -> list[dict[str, Any]]:
    parsed: list[dict[str, Any]] = []
    for section in extract_notes_sections(sm_text):
        step_type = section["step_type"].strip().lower()
        if step_type != "dance-single":
            continue
        meter_text = section["meter"].strip()
        try:
            meter_value: int | None = int(float(meter_text))
        except ValueError:
            meter_value = None
        parsed.append(
            {
                "stepType": "dance-single",
                "description": section["description"].strip(),
                "difficulty": section["difficulty"].strip() or "Unknown",
                "meter": meter_value,
                "radarRaw": section["radar"].strip(),
                "stats": summarize_single_chart(section["note_data"]),
            }
        )
    return parsed


def parse_bgchanges_first_avi(bgchanges_raw: str | None, song_dir: Path) -> Path | None:
    if not bgchanges_raw:
        return None
    for piece in bgchanges_raw.split(","):
        item = piece.strip()
        if not item:
            continue
        parts = item.split("=")
        if len(parts) < 2:
            continue
        media_name = parts[1].strip()
        if not media_name.lower().endswith(".avi"):
            continue
        candidate = (song_dir / media_name).resolve()
        if candidate.exists() and candidate.is_file():
            return candidate
    return None

