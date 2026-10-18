#!/usr/bin/env python3
"""Render every spoken line in assets/voice/lines.json with Piper, then post-process with sox
and encode to Ogg Vorbis under assets/voice/<voice>/.

    python3 tools/voices/render.py --voices <dir with piper .onnx models> [--out assets/voice]

Needs: piper-tts (pip), sox, ffmpeg. Models (download with `python -m piper.download_voices`):
    en_US-joe-medium, en_GB-northern_english_male-medium, en_US-arctic-medium,
    en_GB-alan-medium (HQ), en_US-ryan-high (security).

Files: <kind>_<n>.ogg is the clean take (heard in person), <kind>_<n>.r.ogg is the same line
through a handheld radio. Lines with a %s slot get one file per callsign or device label:
<kind>_<n>_<slug>.ogg.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

from piper import PiperVoice, SynthesisConfig

# voice id -> (model file, speaker, length_scale, pitch cents, noise)
GUARD_VOICES = {
    "g0": ("en_US-joe-medium", None, 0.92, 0, 0.6),
    "g1": ("en_GB-northern_english_male-medium", None, 0.9, -40, 0.6),
    "g2": ("en_US-arctic-medium", 1, 0.9, 0, 0.5),      # rms
    "g3": ("en_US-arctic-medium", 7, 0.92, -60, 0.5),   # bdl
    "g4": ("en_US-arctic-medium", 8, 0.9, 40, 0.5),     # jmk
    "g5": ("en_US-joe-medium", None, 0.88, 90, 0.7),
}
HQ_VOICE = ("en_GB-alan-medium", None, 1.0, -30, 0.4)
SEC_VOICE = ("en_US-ryan-high", None, 0.98, 0, 0.4)

SPOKEN = {"CAM": "camera", "DRONE-": "drone "}


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def spoken(label: str) -> str:
    for k, v in SPOKEN.items():
        label = label.replace(k, v)
    label = re.sub(r"\b0+(\d)", r"\1", label)
    return label


class Renderer:
    def __init__(self, model_dir: Path, out: Path):
        self.model_dir = model_dir
        self.out = out
        self.models = {}
        self.tmp = Path(tempfile.mkdtemp(prefix="voices_"))
        self.count = 0

    def model(self, name: str) -> PiperVoice:
        if name not in self.models:
            self.models[name] = PiperVoice.load(self.model_dir / f"{name}.onnx")
        return self.models[name]

    def render(self, voice_id: str, voice: tuple, text: str, rel: str, radio: bool, clean: bool, urgent: bool) -> None:
        model_name, speaker, length, pitch, noise = voice
        dest_clean = self.out / voice_id / f"{rel}.ogg"
        dest_radio = self.out / voice_id / f"{rel}.r.ogg"
        if (not clean or dest_clean.exists()) and (not radio or dest_radio.exists()):
            return
        dest_clean.parent.mkdir(parents=True, exist_ok=True)
        raw = self.tmp / "raw.wav"
        cfg = SynthesisConfig(speaker_id=speaker, length_scale=length * (0.9 if urgent else 1.0),
                              noise_scale=noise, noise_w_scale=0.8, normalize_audio=True)
        with wave.open(str(raw), "wb") as wf:
            self.model(model_name).synthesize_wav(text, wf, syn_config=cfg)
        # tighten the ends, correct pitch, then a touch of compression so barks have bite
        base = self.tmp / "base.wav"
        chain = ["silence", "1", "0.02", "0.4%", "reverse", "silence", "1", "0.02", "0.4%", "reverse"]
        if pitch:
            chain += ["pitch", str(pitch)]
        chain += ["compand", "0.005,0.12", "-45,-35,-25,-14,0,-5", "-4", "gain", "-n", "-2"]
        subprocess.run(["sox", str(raw), str(base)] + chain, check=True, stderr=subprocess.DEVNULL)
        if clean:
            self.encode(base, dest_clean)
        if radio:
            dur = float(subprocess.check_output(["soxi", "-D", str(base)]).decode().strip())
            band = self.tmp / "band.wav"
            subprocess.run(["sox", str(base), str(band), "highpass", "420", "highpass", "420", "lowpass", "2600", "lowpass", "2600",
                            "overdrive", "9", "30", "compand", "0.003,0.06", "-45,-30,-25,-12,0,-7", "-5", "gain", "-n", "-3"],
                           check=True, stderr=subprocess.DEVNULL)
            hiss = self.tmp / "hiss.wav"
            subprocess.run(["sox", "-n", "-r", "22050", "-c", "1", str(hiss), "synth", f"{dur + 0.08:.3f}", "pinknoise",
                            "bandpass", "1900", "1200", "vol", "0.035", "fade", "t", "0.03", "0", "0.05"],
                           check=True, stderr=subprocess.DEVNULL)
            mixed = self.tmp / "radio.wav"
            subprocess.run(["sox", "-m", str(band), str(hiss), str(mixed), "gain", "-n", "-2"], check=True, stderr=subprocess.DEVNULL)
            self.encode(mixed, dest_radio)
        self.count += 1
        if self.count % 25 == 0:
            print(f"  {self.count} lines", flush=True)

    def encode(self, wav: Path, dest: Path) -> None:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "2.5", "-ar", "22050", str(dest)], check=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--voices", required=True, help="directory holding the piper .onnx models")
    ap.add_argument("--out", default=str(Path(__file__).resolve().parents[2] / "assets" / "voice"))
    ap.add_argument("--lines", default=str(Path(__file__).resolve().parents[2] / "assets" / "voice" / "lines.json"))
    args = ap.parse_args()
    lines = json.load(open(args.lines))
    r = Renderer(Path(args.voices), Path(args.out))
    guards = lines["voices"]["guards"]
    urgent = {"contact", "heard", "nade", "nade_warn", "mandown", "hit", "supp", "push", "blind", "cover", "flank", "reload", "body", "smoke"}
    # guard lines, in every guard voice
    for vid in guards:
        voice = GUARD_VOICES[vid]
        print(f"voice {vid}", flush=True)
        for kind, texts in lines["guard"].items():
            for i, text in enumerate(texts):
                if "%s" in text:
                    continue
                r.render(vid, voice, text, f"{kind}_{i}", radio=True, clean=True, urgent=kind in urgent)
    # check-in answers: each callsign always has the same voice
    for ci, cs in enumerate(lines["callsigns"]):
        vid = guards[ci % len(guards)]
        for i, text in enumerate(lines["guard"]["check_in"]):
            r.render(vid, GUARD_VOICES[vid], text % cs, f"check_in_{i}_{slug(cs)}", radio=True, clean=True, urgent=False)
    # HQ
    print("voice hq", flush=True)
    for kind, texts in lines["hq"].items():
        for i, text in enumerate(texts):
            if "%s" in text:
                for cs in lines["callsigns"]:
                    r.render("hq", HQ_VOICE, text % cs, f"{kind}_{i}_{slug(cs)}", radio=True, clean=False, urgent=False)
            else:
                r.render("hq", HQ_VOICE, text, f"{kind}_{i}", radio=True, clean=False, urgent=kind == "alarm")
    # security desk
    print("voice sec", flush=True)
    for kind, texts in lines["security"].items():
        labels = lines["labels"]["drone"] if kind == "drone" else lines["labels"]["cam"]
        for i, text in enumerate(texts):
            for lab in labels:
                r.render("sec", SEC_VOICE, text % spoken(lab), f"{kind}_{i}_{slug(lab)}", radio=True, clean=False, urgent=False)
    print(f"done: {r.count} lines rendered into {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
