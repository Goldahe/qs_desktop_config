#include <algorithm>
#include <cmath>
#include <complex>
#include <cstdio>
#include <iostream>
#include <vector>

namespace {
constexpr int N = 4096;
constexpr int HOP = 800;
constexpr int BINS = 44; // 4096-point FFT bins from 0 Hz through 512 Hz
constexpr int RATE = 48000;

void fft(std::vector<std::complex<float>>& a) {
    for (int i = 1, j = 0; i < N; ++i) {
        int bit = N >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) std::swap(a[i], a[j]);
    }
    for (int len = 2; len <= N; len <<= 1) {
        const float angle = -2.0f * static_cast<float>(M_PI) / len;
        const std::complex<float> wlen(std::cos(angle), std::sin(angle));
        for (int i = 0; i < N; i += len) {
            std::complex<float> w(1.0f, 0.0f);
            for (int j = 0; j < len / 2; ++j) {
                auto u = a[i + j];
                auto v = a[i + j + len / 2] * w;
                a[i + j] = u + v;
                a[i + j + len / 2] = u - v;
                w *= wlen;
            }
        }
    }
}
}

int main() {
    // Capture the current PipeWire default sink monitor. The helper emits one
    // newline-delimited normalized spectrum at approximately 60 Hz.
    FILE* pipe = popen("pactl get-default-sink | while IFS= read -r sink; do exec parec --device=\"$sink.monitor\" --format=float32le --rate=48000 --channels=2 --raw 2>/dev/null; done", "r");
    if (!pipe) return 2;

    std::vector<float> samples(N, 0.0f);
    std::vector<float> window(N);
    for (int i = 0; i < N; ++i)
        window[i] = 0.5f - 0.5f * std::cos(2.0f * static_cast<float>(M_PI) * i / (N - 1));
    std::vector<std::complex<float>> spectrum(N);
    std::vector<float> magnitudes(BINS);
    std::vector<float> interleaved(HOP * 2);
    size_t got = fread(samples.data(), sizeof(float), N, pipe);
    if (got != N) { pclose(pipe); return 3; }

    std::vector<float> previous(BINS, 0.0f);
    while (true) {
        for (int i = 0; i < N; ++i) {
            spectrum[i] = std::complex<float>(samples[i] * window[i], 0.0f);
        }
        fft(spectrum);

        float peak = 1e-6f;
        for (int i = 0; i < BINS; ++i) {
            // Log compression makes quiet frequencies visible without making
            // the effect explode on a single loud transient.
            const float raw = std::abs(spectrum[i]) / N;
            magnitudes[i] = std::log1p(raw * 80.0f);
            peak = std::max(peak, magnitudes[i]);
        }
        for (int i = 0; i < BINS; ++i) {
            float value = std::clamp(magnitudes[i] / peak, 0.0f, 1.0f);
            value = std::max(value, previous[i] * 0.68f);
            previous[i] = value;
            if (i) std::cout << ',';
            std::cout << value;
        }
        std::cout << '\n' << std::flush;

        std::copy(samples.begin() + HOP, samples.end(), samples.begin());
        got = fread(interleaved.data(), sizeof(float), interleaved.size(), pipe);
        if (got != interleaved.size()) break;
        for (int i = 0; i < HOP; ++i)
            samples[N - HOP + i] = (interleaved[i * 2] + interleaved[i * 2 + 1]) * 0.5f;
    }

    pclose(pipe);
    return 0;
}
