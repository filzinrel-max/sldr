#!/usr/bin/env python3
"""Generate song manifests for web UI and LSL startup."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote

from _songlib import (
    extract_tag,
    list_song_dirs,
    parse_bgchanges_first_avi,
    parse_bpms,
    parse_single_charts,
    pick_preferred_file,
    read_text_file,
    relative_posix,
    slugify,
)


LSL_HTTP_BODY_LIMIT = 16384


def discover_chart_json_map(
    song_id: str,
    project_root: Path,
    difficulties: dict[str, int],
) -> dict[str, str]:
    chart_map: dict[str, str] = {}
    chart_dir = (project_root / "game-data" / "charts" / song_id).resolve()
    if not chart_dir.exists() or not chart_dir.is_dir():
        return chart_map

    chart_files = sorted(chart_dir.glob("*.chart.idx.json"), key=lambda path: path.name.lower())
    for chart_file in chart_files:
        try:
            chart_payload = json.loads(chart_file.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(chart_payload, dict):
            continue

        difficulty_raw = chart_payload.get("d")
        if not isinstance(difficulty_raw, str):
            continue

        difficulty = difficulty_raw.strip()
        if difficulty == "" or difficulty in chart_map:
            continue

        chart_map[difficulty] = relative_posix(chart_file.resolve(), project_root)

    for difficulty in difficulties.keys():
        if difficulty in chart_map:
            continue
        diff_slug = slugify(difficulty)
        if diff_slug == "":
            continue

        guessed_file = chart_dir / f"{diff_slug}.chart.idx.json"
        if guessed_file.exists():
            chart_map[difficulty] = relative_posix(guessed_file.resolve(), project_root)

    return chart_map


def build_song_record(song_dir: Path, project_root: Path, used_ids: set[str]) -> dict[str, Any] | None:
    sm_file = pick_preferred_file(song_dir, ".sm")
    if not sm_file:
        return None

    sm_text = read_text_file(sm_file)
    title = extract_tag(sm_text, "TITLE") or song_dir.name
    artist = extract_tag(sm_text, "ARTIST") or "Unknown Artist"
    music_tag = extract_tag(sm_text, "MUSIC")
    banner_tag = extract_tag(sm_text, "BANNER")
    background_tag = extract_tag(sm_text, "BACKGROUND")
    bpms_raw = extract_tag(sm_text, "BPMS")
    offset_raw = extract_tag(sm_text, "OFFSET")
    bgchanges_raw = extract_tag(sm_text, "BGCHANGES")

    song_id_base = slugify(title)
    song_id = song_id_base
    suffix = 2
    while song_id in used_ids:
        song_id = f"{song_id_base}-{suffix}"
        suffix += 1
    used_ids.add(song_id)

    ogg_file = (song_dir / music_tag) if music_tag else pick_preferred_file(song_dir, ".ogg")
    if ogg_file and not ogg_file.exists():
        ogg_file = pick_preferred_file(song_dir, ".ogg")
    if ogg_file:
        ogg_file = ogg_file.resolve()

    mp3_file = None
    if ogg_file:
        mp3_candidate = ogg_file.with_suffix(".mp3")
        if mp3_candidate.exists():
            mp3_file = mp3_candidate
    if not mp3_file:
        mp3_file = pick_preferred_file(song_dir, ".mp3")
        if mp3_file:
            mp3_file = mp3_file.resolve()

    avi_file = parse_bgchanges_first_avi(bgchanges_raw, song_dir)
    if not avi_file:
        fallback_avi = pick_preferred_file(song_dir, ".avi")
        if fallback_avi:
            avi_file = fallback_avi.resolve()

    mp4_file = pick_preferred_file(song_dir, ".mp4")
    if mp4_file:
        mp4_file = mp4_file.resolve()

    banner_file = (song_dir / banner_tag) if banner_tag else None
    if banner_file and not banner_file.exists():
        banner_file = None
    if not banner_file:
        banner_file = pick_preferred_file(song_dir, ".png")
    if banner_file:
        banner_file = banner_file.resolve()

    background_file = (song_dir / background_tag) if background_tag else None
    if background_file and not background_file.exists():
        background_file = None
    if not background_file:
        bg_candidates = sorted(song_dir.glob("*-bg.png"), key=lambda p: p.name.lower())
        background_file = bg_candidates[0] if bg_candidates else None
    if background_file:
        background_file = background_file.resolve()

    charts = parse_single_charts(sm_text)
    difficulties = {
        chart["difficulty"]: chart["meter"]
        for chart in charts
        if chart["difficulty"] and chart["meter"] is not None
    }
    chart_json_map = discover_chart_json_map(song_id=song_id, project_root=project_root, difficulties=difficulties)

    try:
        offset_value = float(offset_raw) if offset_raw else 0.0
    except ValueError:
        offset_value = 0.0

    def rel(path: Path | None) -> str | None:
        if not path:
            return None
        return relative_posix(path, project_root)

    return {
        "id": song_id,
        "title": title,
        "artist": artist,
        "folder": song_dir.name,
        "offset": offset_value,
        "bpms": parse_bpms(bpms_raw),
        "paths": {
            "sm": rel(sm_file.resolve()),
            "ogg": rel(ogg_file),
            "mp3": rel(mp3_file),
            "banner": rel(banner_file),
            "background": rel(background_file),
            "avi": rel(avi_file),
            "mp4": rel(mp4_file),
        },
        "charts": charts,
        "difficultyMeters": difficulties,
        "chartJsonByDifficulty": chart_json_map,
    }


def add_urls(manifest: dict[str, Any], base_url: str) -> None:
    base = base_url.rstrip("/")
    for song in manifest["songs"]:
        urls: dict[str, str] = {}
        for key, path in song["paths"].items():
            if not path:
                continue
            urls[key] = f"{base}/{quote(path)}"
        song["urls"] = urls


def build_compact_manifest(full_manifest: dict[str, Any]) -> dict[str, Any]:
    songs = []
    for song in full_manifest["songs"]:
        paths = song.get("paths", {})
        mp4_path = ""
        mp3_path = ""
        if isinstance(paths, dict):
            mp4_raw = paths.get("mp4")
            mp3_raw = paths.get("mp3")
            if isinstance(mp4_raw, str):
                mp4_path = mp4_raw
            if isinstance(mp3_raw, str):
                mp3_path = mp3_raw
        preferred_media = mp4_path
        if preferred_media == "":
            preferred_media = mp3_path

        full_chart_map = song.get("chartJsonByDifficulty", {})
        compact_chart_map: dict[str, str] = {}
        if isinstance(full_chart_map, dict):
            for difficulty, chart_path in full_chart_map.items():
                if not isinstance(difficulty, str):
                    continue
                if not isinstance(chart_path, str):
                    continue
                difficulty = difficulty.strip()
                chart_path = chart_path.strip()
                if difficulty == "" or chart_path == "":
                    continue
                compact_chart_map[difficulty] = chart_path

        songs.append(
            {
                "id": song["id"],
                "t": song["title"],
                "a": song["artist"],
                "d": song["difficultyMeters"],
                "cj": compact_chart_map,
                "sm": song["paths"]["sm"],
                "m4": mp4_path,
                "m3": mp3_path,
                "m": preferred_media,
            }
        )
    return {
        "v": 1,
        "generatedUtc": full_manifest["generatedUtc"],
        "songCount": len(songs),
        "songs": songs,
    }


def write_json(path: Path, payload: dict[str, Any], pretty: bool) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    if pretty:
        encoded = json.dumps(payload, indent=2, ensure_ascii=False).encode("utf-8")
    else:
        encoded = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    path.write_bytes(encoded)
    return len(encoded)


def build_lsl_pages(
    compact_manifest: dict[str, Any], max_page_bytes: int
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    songs = compact_manifest["songs"]
    pages_songs: list[list[dict[str, Any]]] = []
    current_page_songs: list[dict[str, Any]] = []

    def page_size_for(songs_subset: list[dict[str, Any]]) -> int:
        payload = {
            "v": 1,
            "generatedUtc": compact_manifest["generatedUtc"],
            "songCount": compact_manifest["songCount"],
            "page": 1,
            "pageCount": 1,
            "songs": songs_subset,
        }
        return len(json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))

    for song in songs:
        trial = current_page_songs + [song]
        if current_page_songs and page_size_for(trial) > max_page_bytes:
            pages_songs.append(current_page_songs)
            current_page_songs = [song]
        else:
            current_page_songs = trial

    if current_page_songs:
        pages_songs.append(current_page_songs)

    page_payloads: list[dict[str, Any]] = []
    page_count = len(pages_songs)
    for page_number, page_songs in enumerate(pages_songs, start=1):
        page_payloads.append(
            {
                "v": 1,
                "generatedUtc": compact_manifest["generatedUtc"],
                "songCount": compact_manifest["songCount"],
                "page": page_number,
                "pageCount": page_count,
                "songs": page_songs,
            }
        )

    index_payload = {
        "v": 1,
        "generatedUtc": compact_manifest["generatedUtc"],
        "songCount": compact_manifest["songCount"],
        "pageCount": page_count,
        "pages": [{"page": page["page"], "songCount": len(page["songs"])} for page in page_payloads],
    }
    return index_payload, page_payloads


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--songs-root",
        default="songs",
        help="Path to song folders (default: songs)",
    )
    parser.add_argument(
        "--output",
        default="game-data/song-manifest.json",
        help="Path for full manifest output",
    )
    parser.add_argument(
        "--compact-output",
        default="game-data/song-manifest.lsl.json",
        help="Path for compact LSL-oriented manifest output",
    )
    parser.add_argument(
        "--base-url",
        default="",
        help="Optional base URL (for example GitHub Pages root) to add URL fields",
    )
    parser.add_argument(
        "--lsl-max-bytes",
        type=int,
        default=15000,
        help="Target maximum bytes for LSL compact manifest/page payloads (default: 15000)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    songs_root = Path(args.songs_root).resolve()
    if not songs_root.exists() or not songs_root.is_dir():
        raise SystemExit(f"songs root not found: {songs_root}")

    project_root = songs_root.parent.resolve()
    now = datetime.now(timezone.utc).isoformat()

    records = []
    used_ids: set[str] = set()
    for song_dir in list_song_dirs(songs_root):
        record = build_song_record(song_dir, project_root=project_root, used_ids=used_ids)
        if record:
            records.append(record)

    manifest: dict[str, Any] = {
        "version": 1,
        "generatedUtc": now,
        "songCount": len(records),
        "songs": records,
    }
    if args.base_url:
        add_urls(manifest, args.base_url)

    full_size = write_json(Path(args.output), manifest, pretty=True)
    compact = build_compact_manifest(manifest)
    compact_output_path = Path(args.compact_output)
    compact_size = write_json(compact_output_path, compact, pretty=False)

    print(f"Generated full manifest: {args.output} ({full_size} bytes)")
    print(f"Generated compact manifest: {args.compact_output} ({compact_size} bytes)")
    if compact_size > args.lsl_max_bytes:
        index_payload, page_payloads = build_lsl_pages(compact, max_page_bytes=args.lsl_max_bytes)
        base_no_ext = compact_output_path.with_suffix("")
        index_path = base_no_ext.with_name(f"{base_no_ext.name}.index.json")
        index_path.parent.mkdir(parents=True, exist_ok=True)
        index_size = write_json(index_path, index_payload, pretty=False)

        page_sizes = []
        for page in page_payloads:
            page_no = int(page["page"])
            page_path = base_no_ext.with_name(f"{base_no_ext.name}.p{page_no:03d}.json")
            page_size = write_json(page_path, page, pretty=False)
            page_sizes.append((page_no, page_size, page_path))

        print(
            f"Generated paged LSL index: {index_path.as_posix()} ({index_size} bytes), "
            f"pages={len(page_sizes)}"
        )
        for page_no, page_size, page_path in page_sizes:
            print(f"  page {page_no:03d}: {page_path.as_posix()} ({page_size} bytes)")

    if compact_size > LSL_HTTP_BODY_LIMIT:
        print(
            "WARNING: compact manifest exceeds ~16KB LSL HTTP response limit "
            f"({compact_size} > {LSL_HTTP_BODY_LIMIT}). Consider paging or field reduction."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
