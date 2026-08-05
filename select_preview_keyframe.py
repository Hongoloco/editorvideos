"""Selecciona un keyframe informativo, evitando fundidos negros o blancos."""

from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import numpy as np


def image_score(path: Path) -> float:
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        return -1.0
    image = cv2.resize(image, (256, 144), interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    mean = float(gray.mean())
    deviation = float(gray.std())
    if mean < 18.0 or mean > 238.0:
        return -1.0
    edges = cv2.Canny(gray, 55, 145)
    edge_density = float(np.count_nonzero(edges)) / float(edges.size)
    clipped = float(np.count_nonzero((gray < 8) | (gray > 247))) / float(gray.size)
    if clipped >= 0.45:
        return -1.0
    middle_brightness = max(0.0, 1.0 - abs(mean - 115.0) / 115.0)
    face_cascade = cv2.CascadeClassifier(
        str(Path(cv2.data.haarcascades) / "haarcascade_frontalface_default.xml")
    )
    faces = face_cascade.detectMultiScale(gray, scaleFactor=1.12, minNeighbors=4, minSize=(18, 18))
    valid_faces = []
    for x, y, width, height in faces:
        face = gray[y : y + height, x : x + width]
        face_clipped = float(np.count_nonzero((face < 8) | (face > 247))) / float(face.size)
        relative_area = (width * height) / float(gray.size)
        if face_clipped < 0.35 and float(face.std()) > 20.0 and relative_area <= 0.15:
            valid_faces.append((x, y, width, height))
    face_area = max((w * h for _, _, w, h in valid_faces), default=0) / float(gray.size)
    return deviation + edge_density * 150.0 + middle_brightness * 35.0 - clipped * 300.0 + len(valid_faces) * 60.0 + face_area * 400.0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", required=True)
    args = parser.parse_args()
    images = sorted(Path(args.input_dir).glob("*.png"))
    if not images:
        raise RuntimeError("No hay PNG para seleccionar")
    selected = max(images, key=image_score)
    print(selected.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
