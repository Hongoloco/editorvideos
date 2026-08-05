"""Conversor local y gratuito de video a dibujo anime estable.

No usa servicios externos ni modelos generativos. Cada fotograma atraviesa la
misma cadena determinista para evitar cambios aleatorios entre cuadros.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np


def fit_width(frame: np.ndarray, max_width: int) -> np.ndarray:
    height, width = frame.shape[:2]
    if width <= max_width:
        return frame
    scale = max_width / float(width)
    target_height = max(2, int(round(height * scale / 2.0) * 2))
    return cv2.resize(frame, (max_width, target_height), interpolation=cv2.INTER_AREA)


def quantize_luminance(image: np.ndarray, levels: int) -> np.ndarray:
    """Simplifica luz y sombra sin reemplazar los colores de la fuente."""
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    light, chroma_a, chroma_b = cv2.split(lab)

    step = 256.0 / float(levels)
    quantized_light = np.clip(
        np.floor(light.astype(np.float32) / step) * step + step * 0.5,
        0,
        255,
    ).astype(np.uint8)

    # En áreas lisas (cielo, piel, paredes) se conserva más degradado; cerca de
    # formas y texturas se usa más sombreado cel. Esto evita bandas gigantes.
    light_f = light.astype(np.float32)
    grad_x = cv2.Sobel(light_f, cv2.CV_32F, 1, 0, ksize=3)
    grad_y = cv2.Sobel(light_f, cv2.CV_32F, 0, 1, ksize=3)
    detail = np.clip(cv2.magnitude(grad_x, grad_y) / 72.0, 0.0, 1.0)
    detail = cv2.GaussianBlur(detail, (0, 0), 1.2)
    mix = 0.24 + detail * 0.56
    adaptive_light = (
        quantized_light.astype(np.float32) * mix + light_f * (1.0 - mix)
    ).astype(np.uint8)
    return cv2.cvtColor(cv2.merge((adaptive_light, chroma_a, chroma_b)), cv2.COLOR_LAB2BGR)


def draw_ink_lines(
    source: np.ndarray,
    painted: np.ndarray,
    boldness: float = 0.88,
    thickness: int = 1,
) -> np.ndarray:
    """Extrae contornos oscuros y los integra como tinta azul-negra."""
    gray = cv2.cvtColor(source, cv2.COLOR_BGR2GRAY)
    gray = cv2.bilateralFilter(gray, 7, 35, 35)
    median = float(np.median(gray))
    lower = int(max(22, 0.58 * median))
    upper = int(min(220, max(lower + 28, 1.28 * median)))

    natural_edges = cv2.Canny(gray, lower, upper, L2gradient=True)
    # Usar la fuente evita dibujar falsos contornos en cielos o paredes lisas
    # cuando el sombreado cel divide un degradado en varias bandas.
    edges = natural_edges

    # Cierra pequeños huecos sin crear bordes verdes ni halos blancos.
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2, 2))
    edges = cv2.dilate(edges, kernel, iterations=max(1, thickness))
    edges = cv2.GaussianBlur(edges, (3, 3), 0.45)

    alpha = (edges.astype(np.float32) / 255.0 * boldness)[..., None]
    ink = np.empty_like(painted, dtype=np.float32)
    ink[:] = (24, 20, 18)  # BGR: tinta casi negra, ligeramente cálida.
    result = painted.astype(np.float32) * (1.0 - alpha) + ink * alpha
    return np.clip(result, 0, 255).astype(np.uint8)


def anime_frame(frame: np.ndarray, levels: int, strength: float) -> np.ndarray:
    # Dos pasadas suaves eliminan textura fotográfica manteniendo los límites.
    smooth = cv2.bilateralFilter(frame, 9, 58, 58)
    smooth = cv2.bilateralFilter(smooth, 7, 42, 42)
    cel = quantize_luminance(smooth, levels)

    hsv = cv2.cvtColor(cel, cv2.COLOR_BGR2HSV).astype(np.float32)
    hsv[..., 1] = np.clip(hsv[..., 1] * 1.08 + 2.0, 0, 255)
    cel = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR)

    # Mezclar parte de la fuente mantiene la paleta exacta y los detalles finos.
    painted = cv2.addWeighted(cel, strength, frame, 1.0 - strength, 0)
    return draw_ink_lines(frame, painted)


def posterize_colors(image: np.ndarray, color_step: int = 24) -> np.ndarray:
    """Reduce la paleta sin cambiarla aleatoriamente entre fotogramas."""
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB).astype(np.float32)
    light = lab[..., 0]
    chroma_a = lab[..., 1]
    chroma_b = lab[..., 2]
    light = np.floor(light / 32.0) * 32.0 + 16.0
    chroma_a = np.floor(chroma_a / color_step) * color_step + color_step / 2.0
    chroma_b = np.floor(chroma_b / color_step) * color_step + color_step / 2.0
    poster = np.clip(np.dstack((light, chroma_a, chroma_b)), 0, 255).astype(np.uint8)
    return cv2.cvtColor(poster, cv2.COLOR_LAB2BGR)


def cartoon_frame(frame: np.ndarray) -> np.ndarray:
    """Caricatura más intensa: paleta corta, color vivo y tinta gruesa."""
    smooth = cv2.bilateralFilter(frame, 11, 72, 72)
    smooth = cv2.bilateralFilter(smooth, 9, 54, 54)
    poster = posterize_colors(smooth)
    cel = quantize_luminance(poster, 5)

    hsv = cv2.cvtColor(cel, cv2.COLOR_BGR2HSV).astype(np.float32)
    hsv[..., 1] = np.clip(hsv[..., 1] * 1.28 + 5.0, 0, 255)
    value = hsv[..., 2] / 255.0
    hsv[..., 2] = np.clip(np.power(value, 0.90) * 255.0 + 3.0, 0, 255)
    vivid = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR)

    # Una fracción del suavizado evita bloques demasiado rígidos en piel/cielo.
    painted = cv2.addWeighted(vivid, 0.82, smooth, 0.18, 0)
    return draw_ink_lines(frame, painted, boldness=0.98, thickness=2)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--max-width", type=int, default=960)
    parser.add_argument("--levels", type=int, default=7)
    parser.add_argument("--strength", type=float, default=0.84)
    parser.add_argument("--style", choices=("anime", "cartoon"), default="anime")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    capture = cv2.VideoCapture(str(input_path))
    if not capture.isOpened():
        raise RuntimeError(f"No se pudo abrir el video: {input_path}")

    fps = capture.get(cv2.CAP_PROP_FPS) or 24.0
    total = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    ok, first = capture.read()
    if not ok:
        raise RuntimeError("El video no contiene fotogramas legibles.")
    first = fit_width(first, args.max_width)
    height, width = first.shape[:2]

    writer = cv2.VideoWriter(
        str(output_path),
        cv2.VideoWriter_fourcc(*"mp4v"),
        fps,
        (width, height),
    )
    if not writer.isOpened():
        raise RuntimeError(f"No se pudo crear el video: {output_path}")

    frame_index = 0
    current = first
    try:
        while True:
            current = fit_width(current, args.max_width)
            if args.style == "cartoon":
                result = cartoon_frame(current)
            else:
                result = anime_frame(
                    current,
                    levels=max(4, min(12, args.levels)),
                    strength=max(0.0, min(1.0, args.strength)),
                )
            writer.write(result)
            frame_index += 1

            if frame_index == 1 or frame_index % 12 == 0 or frame_index == total:
                percent = min(100, int(round(frame_index * 100.0 / max(total, 1))))
                print(
                    f"PROGRESS|{frame_index}|{total}|{percent}",
                    file=sys.stderr,
                    flush=True,
                )

            ok, current = capture.read()
            if not ok:
                break
    finally:
        writer.release()
        capture.release()

    print(f"DONE|{frame_index}|{output_path}", file=sys.stderr, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
