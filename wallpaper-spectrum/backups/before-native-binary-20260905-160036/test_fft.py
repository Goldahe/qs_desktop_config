#!/usr/bin/env python3
"""Dependency-free stdin/CSV contract tests. Run: python3 test_fft.py."""
import array
import math
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parent
BINARY = ROOT / 'fft-spectrum'
RATE = 48000
HOP = 2000
BINS = 640
FFT_SIZE = 1280
BIN_HZ = RATE / FFT_SIZE


def pcm(count, frequency=0, amplitude=0):
    samples = array.array('f')
    for i in range(count):
        value = amplitude * math.sin(2 * math.pi * frequency * i / RATE)
        samples.extend((value, value))
    if sys.byteorder != 'little':
        samples.byteswap()
    return samples.tobytes()


class SpectrumTests(unittest.TestCase):
    def analyze(self, data):
        self.assertTrue(BINARY.is_file(), 'stdin analyzer executable is missing')
        try:
            result = subprocess.run([str(BINARY)], input=data, capture_output=True, timeout=5)
        except subprocess.TimeoutExpired:
            self.fail('analyzer did not consume stdin and exit at EOF within 5 seconds')
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        frames = [[float(v) for v in line.split(',')] for line in result.stdout.decode().splitlines()]
        for frame in frames:
            self.assertEqual(len(frame), BINS)
            self.assertTrue(all(math.isfinite(v) and 0 <= v <= 1 for v in frame))
        return frames

    def test_silence_outputs_exactly_24_frames_per_second(self):
        frames = self.analyze(pcm(RATE))
        self.assertEqual(len(frames), 24)
        self.assertTrue(all(v == 0 for frame in frames for v in frame))

    def test_low_and_high_tone_peaks_match_fft_frequency_bins(self):
        for frequency in (220, 440, 6000, 18000):
            with self.subTest(frequency=frequency):
                frames = self.analyze(pcm(RATE, frequency, 0.5))
                peak = max(range(BINS), key=frames[-1].__getitem__)
                self.assertEqual(peak, round(frequency / BIN_HZ))
                self.assertGreater(frames[-1][peak], 0.5)


    def test_smooth_attack_and_release_to_silence(self):
        frames = self.analyze(pcm(RATE, 220, 0.5) + pcm(RATE))
        peak = round(220 / BIN_HZ)
        values = [frame[peak] for frame in frames]
        self.assertGreater(values[4], values[0])
        self.assertLess(max(b - a for a, b in zip(values, values[1:])), 0.35)
        self.assertGreater(values[30], 0.05, 'release should continue after FFT window empties')
        self.assertTrue(all(b <= a + 1e-5 for a, b in zip(values[30:], values[31:])))
        self.assertLess(values[-1], 0.005)


    def test_noise_floor(self):
        frames = self.analyze(pcm(RATE, 220, 1e-5))
        self.assertTrue(all(v == 0 for frame in frames for v in frame))


    def test_invalid_channel_does_not_poison_valid_channel(self):
        import struct
        data = bytearray(pcm(RATE, 220, 0.5))
        for index in range(RATE):
            struct.pack_into('<f', data, index * 8, float('nan') if index % 2 else float('inf'))
        frames = self.analyze(data)
        self.assertGreater(frames[-1][round(220 / BIN_HZ)], 0.4)


    def test_louder_input_has_taller_bars(self):
        peak = round(220 / BIN_HZ)
        quiet = self.analyze(pcm(RATE, 220, 0.02))[-1][peak]
        loud = self.analyze(pcm(RATE, 220, 0.5))[-1][peak]
        self.assertGreater(quiet, 0.1)
        self.assertGreater(loud, quiet + 0.3)

    def test_partial_hops_are_not_emitted(self):
        for count in (0, 799, 800, 1599, 1600, 48017):
            with self.subTest(count=count):
                self.assertEqual(len(self.analyze(pcm(count))), count // HOP)

    def test_first_hop_is_flushed_without_eof(self):
        import select
        with subprocess.Popen([str(BINARY)], stdin=subprocess.PIPE, stdout=subprocess.PIPE) as process:
            try:
                process.stdin.write(pcm(HOP, 220, 0.5))
                process.stdin.flush()
                self.assertTrue(select.select([process.stdout], [], [], 1)[0], 'first hop was buffered')
                self.assertEqual(len(process.stdout.readline().split(b',')), BINS)
            finally:
                process.stdin.close()
                process.wait(timeout=2)

    def test_dc_and_top_bin(self):
        data = array.array('f', [0.25, 0.25] * RATE)
        if sys.byteorder != 'little':
            data.byteswap()
        self.assertEqual((BINS - 1) * BIN_HZ, 23962.5)
        for samples, expected in ((data.tobytes(), 0), (pcm(RATE, (BINS - 1) * BIN_HZ, 0.5), BINS - 1)):
            frame = self.analyze(samples)[-1]
            if expected == 0:
                # Hann DC leaks into bin 1; one-sided scaling makes them equal.
                self.assertGreater(frame[0], 0.5)
                self.assertLessEqual(max(frame) - frame[0], 0.001)
            else:
                self.assertEqual(max(range(BINS), key=frame.__getitem__), expected)

    def test_capture_wrapper_routes_and_cleans_up(self):
        import os
        import select
        import shutil
        import tempfile
        import time
        capture = ROOT / 'capture.sh'
        self.assertTrue(capture.exists(), 'separate capture wrapper is missing')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copy2(capture, root / 'capture.sh')
            (root / 'fft-spectrum').symlink_to(BINARY)
            fake = root / 'parec'
            fake.write_text('#!/usr/bin/env python3\nimport os,sys,time\nfrom pathlib import Path\nPath(os.environ["ARGS_FILE"]).write_text("\\n".join(sys.argv[1:]))\nPath(os.environ["PID_FILE"]).write_text(str(os.getpid()))\nwhile True:\n os.write(1, bytes(6400))\n time.sleep(1/60)\n')
            fake.chmod(0o755)
            pactl = root / 'pactl'
            pactl.write_text('#!/bin/sh\nprintf "%s\\n" exact.default.sink\n')
            pactl.chmod(0o755)
            for override in ('isolated.test.sink', ''):
                environment = dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'],
                                   SPECTRUM_SINK=override, ARGS_FILE=str(root / 'args'), PID_FILE=str(root / 'pid'))
                process = subprocess.Popen(['bash', str(root / 'capture.sh')], env=environment,
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                try:
                    self.assertTrue(select.select([process.stdout], [], [], 3)[0])
                    self.assertEqual(len(process.stdout.readline().split(b',')), BINS)
                    args = (root / 'args').read_text().splitlines()
                    self.assertIn('--device=' + (override or 'exact.default.sink') + '.monitor', args)
                    for argument in ('--latency-msec=16', '--rate=48000', '--channels=2', '--format=float32le', '--raw'):
                        self.assertIn(argument, args)
                    child = int((root / 'pid').read_text())
                    process.terminate()
                    process.wait(timeout=3)
                    self.assertFalse(Path('/proc', str(child)).exists(), 'parec leaked after wrapper termination')
                finally:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=3)
                    process.stdout.close()
                    process.stderr.close()


if __name__ == '__main__':
    unittest.main(verbosity=2)
