"""Crea una imagen Canny 16:9 para guiar ControlNet."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--height", type=int, default=288)
    args = parser.parse_args()

    image = cv2.imread(args.input, cv2.IMREAD_COLOR)
    if image is None:
        raise RuntimeError(f"No se pudo leer {args.input}")
    source_height, source_width = image.shape[:2]
    scale = min(args.width / source_width, args.height / source_height)
    resized = cv2.resize(
        image,
        (max(1, round(source_width * scale)), max(1, round(source_height * scale))),
        interpolation=cv2.INTER_AREA,
    )
    canvas = np.zeros((args.height, args.width, 3), dtype=np.uint8)
    y = (args.height - resized.shape[0]) // 2
    x = (args.width - resized.shape[1]) // 2
    canvas[y : y + resized.shape[0], x : x + resized.shape[1]] = resized
    gray = cv2.cvtColor(canvas, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (3, 3), 0)
    edges = cv2.Canny(gray, 80, 180)
    control = cv2.cvtColor(edges, cv2.COLOR_GRAY2BGR)
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(args.output, control, [cv2.IMWRITE_PNG_COMPRESSION, 5]):
        raise RuntimeError(f"No se pudo guardar {args.output}")
    print(
        json.dumps(
            {
                "mean_brightness": float(gray.mean()),
                "edge_density": float(np.count_nonzero(edges)) / float(edges.size),
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
