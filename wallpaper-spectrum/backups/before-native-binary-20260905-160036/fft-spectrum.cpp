// stdin: interleaved float32le stereo, 48000 Hz. stdout: 640 CSV values/hop.
// Build: g++ -std=c++17 -O3 -Wall -Wextra -Wpedantic fft-spectrum.cpp -o <temporary> $(pkg-config --cflags --libs fftw3f)
// Rename the successfully built temporary executable to fft-spectrum atomically.
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fftw3.h>

namespace {
constexpr int N = 1280;
constexpr int MAX_HOP = 2000;
constexpr int BINS = 640; // k * 48000/1280 Hz; k=0..639 (0..23962.5 Hz).
constexpr float PI = 3.14159265358979323846f;

int configuredFrameRate() {
    const char *text = std::getenv("SPECTRUM_FRAME_RATE");
    if (!text || !*text) return 24;
    char *end = nullptr;
    const long value = std::strtol(text, &end, 10);
    return end != text && *end == '\0' ? std::clamp<long>(value, 1, 120) : 24;
}

class Analyzer {
    std::array<float, N> samples{};
    std::array<float, N> window{};
    std::array<float, N> fftInput{};
    std::array<fftwf_complex, N / 2 + 1> spectrum{};
    std::array<float, BINS> previous{};
    fftwf_plan plan = nullptr;
    const int frameRate = configuredFrameRate();
    const int hopSamples = std::clamp(48000 / frameRate, 1, MAX_HOP);
    // 20 ms attack, 140 ms release, calculated once for the configured cadence.
    const float attack = 1 - std::exp(-1.0f / (frameRate * 0.020f));
    const float release = 1 - std::exp(-1.0f / (frameRate * 0.140f));
    float windowSum = 0;
    unsigned cursor = 0;

public:
    Analyzer() {
        for (int i = 0; i < N; ++i) {
            window[i] = 0.5f - 0.5f * std::cos(2 * PI * i / (N - 1));
            windowSum += window[i];
        }
        plan = fftwf_plan_dft_r2c_1d(N, fftInput.data(), spectrum.data(), FFTW_ESTIMATE);
    }

    ~Analyzer() {
        if (plan) fftwf_destroy_plan(plan);
    }

    bool valid() const { return plan != nullptr; }
    int hop() const { return hopSamples; }

    bool frame(const float *input) {
        for (int i = 0; i < hopSamples; ++i) {
            const float left = std::isfinite(input[i * 2]) ? std::clamp(input[i * 2], -1.0f, 1.0f) : 0;
            const float right = std::isfinite(input[i * 2 + 1]) ? std::clamp(input[i * 2 + 1], -1.0f, 1.0f) : 0;
            samples[cursor] = 0.5f * left + 0.5f * right;
            if (++cursor == N) cursor = 0;
        }

        // The initial window is zero-padded: emit from the first 800 samples.
        for (unsigned i = 0; i < N; ++i)
            fftInput[i] = samples[(cursor + i) % N] * window[i];
        fftwf_execute(plan);

        // A 1280-point real FFT has 641 unique bins including Nyquist.
        // Emit bins 0..639; the Nyquist bin 640 is deliberately omitted.
        for (int bin = 0; bin < BINS; ++bin) {
            const float real = spectrum[bin][0];
            const float imaginary = spectrum[bin][1];
            const float amplitude = std::hypot(real, imaginary) * (bin == 0 ? 1 : 2) / windowSum;
            // Fixed full-scale reference; subtract -80 dBFS amplitude floor.
            // No per-frame normalization: louder input always yields taller bars.
            const float gated = std::max(0.0f, amplitude - 0.0001f);
            const float target = std::clamp(std::log1p(80 * gated) / std::log(81.0f), 0.0f, 1.0f);
            const float coefficient = target > previous[bin] ? attack : release;
            const float value = previous[bin] + coefficient * (target - previous[bin]);
            previous[bin] = value;
            std::printf(bin ? ",%.6f" : "%.6f", static_cast<double>(value));
        }
        std::putchar('\n');
        return std::fflush(stdout) == 0;
    }
};
}

int main() {
    Analyzer analyzer;
    if (!analyzer.valid()) {
        std::fprintf(stderr, "fft-spectrum: failed to create 1280-point FFTW plan\n");
        return 1;
    }
    std::array<float, MAX_HOP * 2> input{};
    while (std::fread(input.data(), sizeof(float), analyzer.hop() * 2, stdin) == static_cast<size_t>(analyzer.hop() * 2)) {
        if (!analyzer.frame(input.data())) {
            std::fprintf(stderr, "fft-spectrum: stdout write failed\n");
            return 1;
        }
    }
    if (std::ferror(stdin)) {
        std::perror("fft-spectrum: stdin read");
        return 1;
    }
    return 0;
}
