"""Detecta escenas y genera keyframes cartoon para cubrir un video completo."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import cv2
import numpy as np

from free_anime_draw import cartoon_frame


def write_status(path: Path, stage: str, percent: int, message: str) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.write_text(f"{stage}|{percent}|{message}", encoding="utf-8")
    temporary.replace(path)


def compact_view(frame: np.ndarray) -> np.ndarray:
    height, width = frame.shape[:2]
    target_width = 256
    target_height = max(2, int(round(height * target_width / width)))
    small = cv2.resize(frame, (target_width, target_height), interpolation=cv2.INTER_AREA)
    return cv2.cvtColor(small, cv2.COLOR_BGR2HSV)


def scene_distance(previous: np.ndarray, current: np.ndarray) -> float:
    previous_hist = cv2.calcHist([previous], [0, 1], None, [32, 16], [0, 180, 0, 256])
    current_hist = cv2.calcHist([current], [0, 1], None, [32, 16], [0, 180, 0, 256])
    cv2.normalize(previous_hist, previous_hist, 0, 1, cv2.NORM_MINMAX)
    cv2.normalize(current_hist, current_hist, 0, 1, cv2.NORM_MINMAX)
    return float(cv2.compareHist(previous_hist, current_hist, cv2.HISTCMP_BHATTACHARYYA))


def frame_name(index: int, frame_number: int, timestamp: float) -> str:
    milliseconds = int(round(timestamp * 1000.0))
    return f"key_{index:04d}_frame_{frame_number:07d}_t_{milliseconds:09d}ms.png"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--status-file", required=True)
    parser.add_argument("--interval", type=float, default=2.0)
    parser.add_argument("--scene-threshold", type=float, default=0.43)
    parser.add_argument("--min-gap", type=float, default=0.60)
    args = parser.parse_args()

    input_path = Path(args.input)
    output_dir = Path(args.output_dir)
    status_file = Path(args.status_file)
    originals_dir = output_dir / "01_ORIGINALES"
    cartoon_dir = output_dir / "02_CARTOON_VIBRANTE"
    originals_dir.mkdir(parents=True, exist_ok=True)
    cartoon_dir.mkdir(parents=True, exist_ok=True)

    capture = cv2.VideoCapture(str(input_path))
    if not capture.isOpened():
        raise RuntimeError(f"No se pudo abrir {input_path}")
    fps = capture.get(cv2.CAP_PROP_FPS) or 24.0
    total_frames = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total_frames / fps if total_frames else 0.0

    records: list[dict[str, object]] = []
    previous_compact: np.ndarray | None = None
    next_regular = 0.0
    last_selected = -1_000.0
    shot_number = 1
    frame_number = 0
    last_frame: np.ndarray | None = None

    while True:
        ok, frame = capture.read()
        if not ok:
            break
        timestamp = frame_number / fps
        compact = compact_view(frame)
        distance = scene_distance(previous_compact, compact) if previous_compact is not None else 1.0
        is_cut = previous_compact is not None and distance >= args.scene_threshold
        if is_cut and timestamp - last_selected >= args.min_gap:
            shot_number += 1

        is_regular = timestamp + 1e-6 >= next_regular
        select = frame_number == 0 or (
            timestamp - last_selected >= args.min_gap and (is_cut or is_regular)
        )
        if select:
            key_index = len(records) + 1
            name = frame_name(key_index, frame_number, timestamp)
            original_path = originals_dir / name
            cartoon_path = cartoon_dir / name
            cv2.imwrite(str(original_path), frame, [cv2.IMWRITE_PNG_COMPRESSION, 5])
            cv2.imwrite(str(cartoon_path), cartoon_frame(frame), [cv2.IMWRITE_PNG_COMPRESSION, 5])
            records.append(
                {
                    "keyframe": key_index,
                    "shot": shot_number,
                    "frame": frame_number,
                    "time_seconds": f"{timestamp:.3f}",
                    "reason": "scene_cut" if is_cut else "interval",
                    "scene_score": f"{distance:.4f}",
                    "original": str(original_path),
                    "cartoon": str(cartoon_path),
                }
            )
            last_selected = timestamp
            next_regular = timestamp + max(args.interval, args.min_gap)

        previous_compact = compact
        last_frame = frame
        frame_number += 1
        if frame_number == 1 or frame_number % 48 == 0:
            percent = min(99, int(round(frame_number * 100 / max(total_frames, 1))))
            write_status(
                status_file,
                "ALL_KEYFRAMES",
                percent,
                f"Analizando {frame_number}/{total_frames}; keyframes creados: {len(records)}",
            )

    capture.release()

    if last_frame is not None and records:
        final_time = max(0.0, (frame_number - 1) / fps)
        if final_time - float(records[-1]["time_seconds"]) >= args.min_gap:
            key_index = len(records) + 1
            name = frame_name(key_index, frame_number - 1, final_time)
            original_path = originals_dir / name
            cartoon_path = cartoon_dir / name
            cv2.imwrite(str(original_path), last_frame, [cv2.IMWRITE_PNG_COMPRESSION, 5])
            cv2.imwrite(str(cartoon_path), cartoon_frame(last_frame), [cv2.IMWRITE_PNG_COMPRESSION, 5])
            records.append(
                {
                    "keyframe": key_index,
                    "shot": shot_number,
                    "frame": frame_number - 1,
                    "time_seconds": f"{final_time:.3f}",
                    "reason": "last_frame",
                    "scene_score": "0.0000",
                    "original": str(original_path),
                    "cartoon": str(cartoon_path),
                }
            )

    manifest = output_dir / "keyframes_manifest.csv"
    with manifest.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(records[0].keys()) if records else [])
        if records:
            writer.writeheader()
            writer.writerows(records)

    summary = output_dir / "RESUMEN.txt"
    summary.write_text(
        "\n".join(
            [
                "KEYFRAMES AUTOMÁTICOS PARA EBSYNTH",
                "===================================",
                f"Video: {input_path}",
                f"Duración: {duration:.3f} segundos",
                f"FPS: {fps:.6f}",
                f"Fotogramas analizados: {frame_number}",
                f"Keyframes generados: {len(records)}",
                f"Intervalo máximo: {args.interval:.2f} segundos",
                "",
                "01_ORIGINALES contiene los cuadros exactos del video.",
                "02_CARTOON_VIBRANTE contiene los cuadros ya estilizados.",
                "Usá los archivos con el mismo nombre para mantener tiempo y pose.",
            ]
        ),
        encoding="utf-8",
    )
    write_status(status_file, "DONE", 100, str(output_dir))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
