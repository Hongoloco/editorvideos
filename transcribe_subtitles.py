"""Genera subtítulos SRT y ASS con Whisper ejecutado completamente en local."""

from __future__ import annotations

import argparse
import re
import sys
import textwrap
from dataclasses import dataclass
from pathlib import Path

from faster_whisper import WhisperModel


@dataclass
class Caption:
    start: float
    end: float
    text: str


def srt_time(seconds: float) -> str:
    milliseconds = max(0, int(round(seconds * 1000)))
    hours, milliseconds = divmod(milliseconds, 3_600_000)
    minutes, milliseconds = divmod(milliseconds, 60_000)
    secs, milliseconds = divmod(milliseconds, 1000)
    return f"{hours:02}:{minutes:02}:{secs:02},{milliseconds:03}"


def ass_time(seconds: float) -> str:
    centiseconds = max(0, int(round(seconds * 100)))
    hours, centiseconds = divmod(centiseconds, 360_000)
    minutes, centiseconds = divmod(centiseconds, 6_000)
    secs, centiseconds = divmod(centiseconds, 100)
    return f"{hours}:{minutes:02}:{secs:02}.{centiseconds:02}"


def clean_word(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def build_captions(segments, duration: float) -> list[Caption]:
    captions: list[Caption] = []
    words: list[tuple[float, float, str]] = []

    def flush() -> None:
        nonlocal words
        if not words:
            return
        text = " ".join(item[2] for item in words)
        text = re.sub(r"\s+([,.;:!?])", r"\1", text).strip()
        if text:
            captions.append(Caption(words[0][0], max(words[-1][1], words[0][0] + 0.45), text))
        words = []

    for segment in segments:
        segment_words = segment.words or []
        if not segment_words and clean_word(segment.text):
            captions.append(Caption(segment.start, segment.end, clean_word(segment.text)))
        for word in segment_words:
            token = clean_word(word.word)
            if not token:
                continue
            proposed = " ".join([item[2] for item in words] + [token])
            proposed_duration = (word.end or word.start) - (words[0][0] if words else word.start)
            should_break = bool(words) and (
                len(proposed) > 54 or len(words) >= 9 or proposed_duration > 3.6
            )
            if should_break:
                flush()
            words.append((float(word.start), float(word.end), token))
            if token.endswith((".", "?", "!")) and len(words) >= 3:
                flush()

        processed = min(duration, float(segment.end))
        percent = min(100, int(round(processed * 100 / max(duration, 0.1))))
        print(f"TRANSCRIBE|{processed:.1f}|{duration:.1f}|{percent}", file=sys.stderr, flush=True)

    flush()

    # Evita tarjetas huérfanas de una o dos palabras cuando una frase larga
    # cruza el límite interno de Whisper (por ejemplo, "...kicking" / "it.").
    merged: list[Caption] = []
    for caption in captions:
        word_count = len(caption.text.split())
        if (
            word_count <= 2
            and merged
            and caption.start - merged[-1].end <= 0.35
            and len(merged[-1].text) + len(caption.text) + 1 <= 72
        ):
            merged[-1].text = f"{merged[-1].text} {caption.text}"
            merged[-1].end = caption.end
        else:
            merged.append(caption)
    return merged


def two_lines(text: str) -> str:
    lines = textwrap.wrap(text, width=29, break_long_words=False, break_on_hyphens=False)
    if len(lines) <= 2:
        return "\n".join(lines)
    midpoint = max(1, len(text) // 2)
    spaces = [m.start() for m in re.finditer(" ", text)]
    split_at = min(spaces, key=lambda x: abs(x - midpoint)) if spaces else midpoint
    return text[:split_at].strip() + "\n" + text[split_at:].strip()


def write_srt(path: Path, captions: list[Caption]) -> None:
    blocks = []
    for index, caption in enumerate(captions, 1):
        blocks.append(
            f"{index}\n{srt_time(caption.start)} --> {srt_time(caption.end)}\n{two_lines(caption.text)}"
        )
    path.write_text("\n\n".join(blocks) + "\n", encoding="utf-8")


def write_ass(path: Path, captions: list[Caption]) -> None:
    header = """[Script Info]
Title: Anime vertical subtitles
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Vertical,Arial,64,&H00FFFFFF,&H000000FF,&H00101010,&H78000000,-1,0,0,0,100,100,0,0,1,5,2,2,75,75,205,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    events = []
    for caption in captions:
        text = two_lines(caption.text).replace("\\", r"\\").replace("{", r"\{").replace("}", r"\}")
        text = text.replace("\n", r"\N")
        events.append(
            f"Dialogue: 0,{ass_time(caption.start)},{ass_time(caption.end)},Vertical,,0,0,0,,{text}"
        )
    path.write_text(header + "\n".join(events) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--srt", required=True)
    parser.add_argument("--ass", required=True)
    parser.add_argument("--model", default="small.en")
    args = parser.parse_args()

    model = WhisperModel(args.model, device="cpu", compute_type="int8", cpu_threads=4)
    segments, info = model.transcribe(
        args.input,
        language="en",
        beam_size=5,
        vad_filter=True,
        vad_parameters={"min_silence_duration_ms": 450},
        word_timestamps=True,
        condition_on_previous_text=True,
    )
    captions = build_captions(segments, float(info.duration))
    if not captions:
        raise RuntimeError("No se detectó diálogo para subtitular.")

    srt_path = Path(args.srt)
    ass_path = Path(args.ass)
    srt_path.parent.mkdir(parents=True, exist_ok=True)
    write_srt(srt_path, captions)
    write_ass(ass_path, captions)
    print(f"SUBTITLES|{len(captions)}|{info.language}", file=sys.stderr, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
