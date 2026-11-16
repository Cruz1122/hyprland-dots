#!/usr/bin/env python3
"""One dictation: record the microphone, transcribe it, print the text.

Talks to the shell (services/Dictation.qml) through JSON lines on stdout:
  {"level": 0.42}            microphone level, 0..1, ~20 per second
  {"paused": true}           recording paused or resumed (SIGUSR2)
  {"state": "transcribing"}  recording ended, waiting for the model
  {"text": "..."}            final text (may be empty: nothing was said)
  {"error": "..."}           something failed; the message is user-facing

Signals: SIGUSR1 ends the recording and transcribes; SIGUSR2 pauses or
resumes it (audio heard while paused is dropped); SIGTERM/SIGINT cancel.
The recording also ends by itself after a pause, see --silence.

Standard library only, so it runs with the system Python and needs no setup.
"""

import argparse
import array
import io
import json
import math
import re
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
import wave

SAMPLE_RATE = 16000  # what Whisper consumes; recording at it avoids resampling
CHUNK_SECONDS = 0.05
CHUNK_BYTES = int(SAMPLE_RATE * CHUNK_SECONDS) * 2  # 16-bit mono
# Ceiling for the measured room noise (0..1 RMS). Someone who starts talking
# at once would otherwise be taken for the room and never clear the threshold.
MAX_NOISE_FLOOR = 0.05

# Whisper invents these when handed silence or noise (subtitle credits it was
# trained on). A result that is only one of them means nothing was said.
HALLUCINATIONS = re.compile(
    r"^\W*(subt[ií]tulos? (realizados? |creados? |hechos? )?por .*|"
    r"gracias por ver( el video)?|¡?gracias!?|thanks? for watching!?|thank you\.?|"
    r"\[.*\]|\(.*\)|♪.*|you)\W*$",
    re.IGNORECASE,
)


def emit(**message):
    print(json.dumps(message, ensure_ascii=False), flush=True)


class Stop(Exception):
    """SIGUSR1: finish recording and transcribe."""


class Cancel(Exception):
    """SIGTERM/SIGINT: drop everything."""


class Pause:
    """SIGUSR2 flips this; the recording loop reads it."""
    active = False


def toggle_pause(*_):
    Pause.active = not Pause.active


def raise_stop(*_):
    raise Stop()


def raise_cancel(*_):
    raise Cancel()


def rms(chunk):
    samples = array.array("h")
    samples.frombytes(chunk[: len(chunk) // 2 * 2])
    if not samples:
        return 0.0
    # Around the chunk's mean: built-in microphones often carry a DC offset
    # that would otherwise read as constant sound.
    mean = sum(samples) / len(samples)
    return math.sqrt(sum((sample - mean) ** 2 for sample in samples) / len(samples)) / 32768


def record(args):
    """Returns the recorded PCM, or b"" when no speech was heard."""
    # stdbuf: pw-record otherwise hands its output over in 4096-byte blocks,
    # one every 128 ms, and the level meter stutters to that rhythm.
    recorder = subprocess.Popen(
        ["stdbuf", "-o0", "pw-record", "--raw", "--rate", str(SAMPLE_RATE), "--channels", "1",
         "--format", "s16", "--latency", "20ms", "-"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    audio = bytearray()
    calibration = []
    noise_floor = 0.0
    loud_run = 0  # consecutive chunks above the threshold
    speech_seconds = 0.0
    silence_seconds = 0.0
    paused = False
    try:
        while True:
            chunk = recorder.stdout.read(CHUNK_BYTES)
            if not chunk:
                raise RuntimeError("El micrófono dejó de entregar audio.")
            if paused != Pause.active:
                paused = Pause.active
                emit(paused=paused)
                # The pause itself must not count as the silence that ends it.
                silence_seconds = 0.0
                loud_run = 0
            if paused:
                emit(level=0.0)
                continue
            audio += chunk
            level = rms(chunk)
            elapsed = len(audio) / 2 / SAMPLE_RATE
            # The first 0.3 s measure the room (fans, hiss): its typical level
            # is the noise floor that speech must clear.
            if elapsed <= 0.3:
                calibration.append(level)
                noise_floor = min(MAX_NOISE_FLOOR, sorted(calibration)[len(calibration) // 2])
                emit(level=0.0)
                continue
            # Meter above the floor, perceptual-ish: quiet speech already moves it.
            emit(level=round(min(1.0, math.sqrt(max(0.0, level - noise_floor)) * 2.2), 3))

            # Two thresholds: clearly above the room to count as speech at
            # all, but only slightly above it to keep the dictation open.
            # Word endings and quiet syllables sit close to the noise; with a
            # single threshold they read as pauses and cut the speaker off.
            speech_threshold = max(args.threshold, noise_floor * 2.0)
            keep_threshold = max(args.threshold * 0.7, noise_floor * 1.4)
            if level >= keep_threshold:
                loud_run += 1
                # A lone loud chunk is a click or a key press, not speech.
                if loud_run >= 2:
                    silence_seconds = 0.0
                    if level >= speech_threshold:
                        speech_seconds += CHUNK_SECONDS
                else:
                    silence_seconds += CHUNK_SECONDS
            else:
                loud_run = 0
                silence_seconds += CHUNK_SECONDS
                # Follow slow changes in the room while nobody speaks.
                noise_floor = min(MAX_NOISE_FLOOR, noise_floor + (level - noise_floor) * 0.02)

            spoke = speech_seconds >= 0.25
            if spoke and args.silence > 0 and silence_seconds >= args.silence:
                break
            if not spoke and elapsed >= args.no_speech_timeout:
                return b""
            if elapsed >= args.max_seconds:
                break
    except Stop:
        pass
    finally:
        recorder.terminate()
        try:
            recorder.wait(timeout=1)
        except subprocess.TimeoutExpired:
            recorder.kill()
    if speech_seconds < 0.15:
        return b""
    return bytes(audio)


def wav_bytes(pcm):
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm)
    return buffer.getvalue()


def wait_for_server(url, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            urllib.request.urlopen(url, timeout=1).close()
            return
        except urllib.error.HTTPError:
            return  # it answered; any status means it is up
        except (urllib.error.URLError, OSError):
            time.sleep(0.15)
    raise RuntimeError("El modelo de voz no respondió a tiempo.")


def transcribe(args, pcm, prompt):
    fields = {
        "temperature": "0.0",
        "response_format": "json",
        "language": args.language,
        "prompt": prompt,
    }
    boundary = uuid.uuid4().hex
    body = bytearray()
    for name, value in fields.items():
        body += f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
    body += (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="dictation.wav"\r\n'
             "Content-Type: audio/wav\r\n\r\n").encode()
    body += wav_bytes(pcm) + f"\r\n--{boundary}--\r\n".encode()
    request = urllib.request.Request(
        f"{args.server}/inference", data=bytes(body),
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.loads(response.read().decode("utf-8")).get("text", "")


def read_glossary(path):
    """Terms the model should recognise, joined into Whisper's prompt."""
    try:
        with open(path, encoding="utf-8") as source:
            terms = [line.strip() for line in source if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return ""
    return ", ".join(terms)


def read_replacements(path):
    """Lines of `heard<TAB>meant`; matched as whole words, ignoring case."""
    rules = []
    try:
        with open(path, encoding="utf-8") as source:
            for line in source:
                if line.startswith("#") or "\t" not in line:
                    continue
                heard, meant = line.rstrip("\n").split("\t", 1)
                if heard.strip():
                    rules.append((re.compile(rf"(?<!\w){re.escape(heard.strip())}(?!\w)", re.IGNORECASE), meant.strip()))
    except FileNotFoundError:
        pass
    return rules


def clean(text, rules):
    text = re.sub(r"\s+", " ", text).strip()
    if HALLUCINATIONS.match(text):
        return ""
    for pattern, meant in rules:
        text = pattern.sub(lambda _match, meant=meant: meant, text)
    return text


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", default="http://127.0.0.1:8177")
    parser.add_argument("--language", default="auto")
    parser.add_argument("--glossary", default="")
    parser.add_argument("--replacements", default="")
    parser.add_argument("--silence", type=float, default=2.5,
                        help="seconds of pause that end the dictation; 0 disables")
    parser.add_argument("--threshold", type=float, default=0.012,
                        help="minimum level (0..1 RMS) that counts as speech")
    parser.add_argument("--no-speech-timeout", type=float, default=8.0)
    parser.add_argument("--max-seconds", type=float, default=180.0)
    args = parser.parse_args()

    signal.signal(signal.SIGUSR1, raise_stop)
    signal.signal(signal.SIGUSR2, toggle_pause)
    signal.signal(signal.SIGTERM, raise_cancel)
    signal.signal(signal.SIGINT, raise_cancel)

    try:
        pcm = record(args)
        # From here on a second press must not abort the transcription.
        signal.signal(signal.SIGUSR1, signal.SIG_IGN)
        if not pcm:
            emit(text="")
            return 0
        emit(state="transcribing")
        wait_for_server(args.server, 30)
        text = transcribe(args, pcm, read_glossary(args.glossary))
        emit(text=clean(text, read_replacements(args.replacements)))
        return 0
    except Cancel:
        return 130
    except Stop:  # raced the handler swap; nothing useful to transcribe
        emit(text="")
        return 0
    except Exception as error:  # reported to the shell, which shows it
        emit(error=str(error))
        return 1


if __name__ == "__main__":
    sys.exit(main())
