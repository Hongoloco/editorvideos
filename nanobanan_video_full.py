"""Procesa un video completo fotograma por fotograma con una API de imagen.

Requiere variables de entorno:
- NANO_BANAN_API_KEY: token Bearer
Opcionales:
- NANO_BANAN_BASE_URL (default: https://api.openai.com/v1)
- NANO_BANAN_MODEL (default: gpt-image-1)
- NANO_BANAN_PROMPT
- NANO_BANAN_NEGATIVE_PROMPT
- NANO_BANAN_MAX_RETRIES (default: 3)
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


def write_status(path: Path, stage: str, percent: int, message: str) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(f"{stage}|{percent}|{message}", encoding="utf-8")
    tmp.replace(path)


def run_command(command: list[str], error_message: str) -> None:
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        details = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"{error_message}: {details}")


def ffprobe_stream(ffprobe: Path, input_video: Path) -> dict[str, object]:
    result = subprocess.run(
        [
            str(ffprobe),
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height,r_frame_rate",
            "-of",
            "json",
            str(input_video),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"No se pudo leer metadata del video: {result.stderr.strip()}")
    data = json.loads(result.stdout)
    streams = data.get("streams") or []
    if not streams:
        raise RuntimeError("El video no contiene stream de video.")
    return streams[0]


def decode_image_payload(payload: dict[str, object]) -> bytes:
    data = payload.get("data")
    if isinstance(data, list) and data:
        first = data[0]
        if isinstance(first, dict):
            b64_json = first.get("b64_json")
            if isinstance(b64_json, str) and b64_json:
                return base64.b64decode(b64_json)
            url = first.get("url")
            if isinstance(url, str) and url:
                with urllib.request.urlopen(url, timeout=120) as response:
                    return response.read()
    raise RuntimeError("La API no devolvio imagen utilizable (ni b64_json ni url).")


def transform_one_frame(
    input_frame: Path,
    output_frame: Path,
    ffmpeg: Path,
    width: int,
    height: int,
    api_key: str,
    base_url: str,
    model: str,
    prompt: str,
    negative_prompt: str,
    retries: int,
) -> None:
    tmp_dir = output_frame.parent / ".tmp"
    tmp_dir.mkdir(parents=True, exist_ok=True)
    raw_response = tmp_dir / f"{input_frame.stem}_raw.json"
    generated_png = tmp_dir / f"{input_frame.stem}_generated.png"

    endpoint = base_url.rstrip("/") + "/images/edits"
    effective_prompt = prompt
    if negative_prompt.strip():
        effective_prompt = f"{prompt.strip()}\n\nAvoid: {negative_prompt.strip()}"

    for attempt in range(1, retries + 1):
        curl_command = [
            "curl.exe",
            "-sS",
            "-X",
            "POST",
            endpoint,
            "-H",
            f"Authorization: Bearer {api_key}",
            "-F",
            f"model={model}",
            "-F",
            f"prompt={effective_prompt}",
            "-F",
            "response_format=b64_json",
            "-F",
            f"image=@{input_frame}",
        ]
        result = subprocess.run(curl_command, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            if attempt == retries:
                raise RuntimeError(f"curl fallo en {input_frame.name}: {result.stderr.strip()}")
            time.sleep(min(4 * attempt, 12))
            continue

        raw_text = result.stdout.strip()
        if not raw_text:
            if attempt == retries:
                raise RuntimeError(f"Respuesta vacia de API para {input_frame.name}.")
            time.sleep(min(4 * attempt, 12))
            continue

        raw_response.write_text(raw_text, encoding="utf-8")
        try:
            payload = json.loads(raw_text)
            image_bytes = decode_image_payload(payload)
            generated_png.write_bytes(image_bytes)
        except Exception as exc:  # noqa: BLE001
            if attempt == retries:
                raise RuntimeError(f"Respuesta invalida para {input_frame.name}: {exc}") from exc
            time.sleep(min(4 * attempt, 12))
            continue

        run_command(
            [
                str(ffmpeg),
                "-hide_banner",
                "-loglevel",
                "error",
                "-i",
                str(generated_png),
                "-vf",
                f"scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:black,setsar=1",
                "-frames:v",
                "1",
                str(output_frame),
                "-y",
            ],
            f"No se pudo adaptar el frame {input_frame.name}",
        )
        return


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-video", required=True)
    parser.add_argument("--output-video", required=True)
    parser.add_argument("--status-file", required=True)
    parser.add_argument("--work-dir", required=True)
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--ffprobe", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    input_video = Path(args.input_video)
    output_video = Path(args.output_video)
    status_file = Path(args.status_file)
    work_dir = Path(args.work_dir)
    ffmpeg = Path(args.ffmpeg)
    ffprobe = Path(args.ffprobe)

    if not input_video.exists():
        raise RuntimeError(f"No existe el video de entrada: {input_video}")
    if not ffmpeg.exists():
        raise RuntimeError(f"No existe ffmpeg: {ffmpeg}")
    if not ffprobe.exists():
        raise RuntimeError(f"No existe ffprobe: {ffprobe}")

    api_key = os.getenv("NANO_BANAN_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("Falta NANO_BANAN_API_KEY en variables de entorno.")

    base_url = os.getenv("NANO_BANAN_BASE_URL", "https://api.openai.com/v1").strip()
    model = os.getenv("NANO_BANAN_MODEL", "gpt-image-1").strip()
    prompt = os.getenv(
        "NANO_BANAN_PROMPT",
        "hand-drawn 2D anime film frame, clean ink lines, cel shading, consistent character design, preserve original composition and motion",
    ).strip()
    negative_prompt = os.getenv(
        "NANO_BANAN_NEGATIVE_PROMPT",
        "photorealistic, 3d render, watermark, logo, text, extra fingers, deformed face, blurry",
    ).strip()
    retries_raw = os.getenv("NANO_BANAN_MAX_RETRIES", "3").strip()
    try:
        retries = max(1, min(8, int(retries_raw)))
    except ValueError:
        retries = 3

    metadata = ffprobe_stream(ffprobe, input_video)
    width = int(metadata.get("width", 0) or 0)
    height = int(metadata.get("height", 0) or 0)
    fps_expr = str(metadata.get("r_frame_rate", "24/1"))
    if width <= 0 or height <= 0:
        raise RuntimeError("Resolucion invalida en el video de entrada.")

    input_frames_dir = work_dir / "frames_in"
    output_frames_dir = work_dir / "frames_out"
    input_frames_dir.mkdir(parents=True, exist_ok=True)
    output_frames_dir.mkdir(parents=True, exist_ok=True)

    write_status(status_file, "NANOBANAN", 1, "Extrayendo fotogramas")
    run_command(
        [
            str(ffmpeg),
            "-hide_banner",
            "-loglevel",
            "warning",
            "-i",
            str(input_video),
            str(input_frames_dir / "%08d.png"),
            "-y",
        ],
        "Fallo la extraccion de fotogramas",
    )

    input_frames = sorted(input_frames_dir.glob("*.png"))
    if not input_frames:
        raise RuntimeError("No se extrajeron fotogramas del video.")

    total = len(input_frames)
    generated = 0
    resumed = 0

    write_status(status_file, "NANOBANAN", 5, f"Procesando {total} fotogramas con IA")
    for index, frame_path in enumerate(input_frames, start=1):
        out_path = output_frames_dir / frame_path.name
        if out_path.exists() and out_path.stat().st_size > 10_000:
            resumed += 1
        else:
            transform_one_frame(
                input_frame=frame_path,
                output_frame=out_path,
                ffmpeg=ffmpeg,
                width=width,
                height=height,
                api_key=api_key,
                base_url=base_url,
                model=model,
                prompt=prompt,
                negative_prompt=negative_prompt,
                retries=retries,
            )
            generated += 1

        if index == 1 or index % 8 == 0 or index == total:
            percent = min(95, 5 + int(round(index * 90.0 / total)))
            write_status(
                status_file,
                "NANOBANAN",
                percent,
                f"Fotograma {index}/{total} | nuevos: {generated} | reanudados: {resumed}",
            )
            print(f"PROGRESS|{index}|{total}|{percent}", file=sys.stderr, flush=True)

    write_status(status_file, "NANOBANAN", 96, "Armando video sin audio")
    run_command(
        [
            str(ffmpeg),
            "-hide_banner",
            "-loglevel",
            "warning",
            "-framerate",
            fps_expr,
            "-i",
            str(output_frames_dir / "%08d.png"),
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            str(output_video),
            "-y",
        ],
        "Fallo el ensamblado final de video",
    )

    summary = work_dir / "NANOBANAN_RESUMEN.txt"
    summary.write_text(
        "\n".join(
            [
                "NANOBANAN PRO - VIDEO COMPLETO",
                "===============================",
                f"Entrada: {input_video}",
                f"Salida: {output_video}",
                f"Fotogramas totales: {total}",
                f"Generados en esta corrida: {generated}",
                f"Reanudados: {resumed}",
                f"Modelo API: {model}",
                f"Endpoint: {base_url.rstrip('/')}/images/edits",
            ]
        ),
        encoding="utf-8",
    )

    if (work_dir / ".tmp").exists():
        shutil.rmtree(work_dir / ".tmp", ignore_errors=True)

    write_status(status_file, "NANOBANAN", 98, "Video IA generado; preparando conformado final")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
