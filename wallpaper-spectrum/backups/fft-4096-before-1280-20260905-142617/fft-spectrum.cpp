// stdin: interleaved float32le stereo, 48000 Hz. stdout: 640 CSV values/hop.
// Build: g++ -std=c++17 -O3 -Wall -Wextra -Wpedantic fft-spectrum.cpp -o <temporary>
// Rename the successfully built temporary executable to fft-spectrum atomically.
#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <cstdio>

namespace {
constexpr int N = 4096;
constexpr int HOP = 800;
constexpr int BINS = 640; // k * 48000/4096 Hz; k=0..639 (0..7488.28125 Hz).
constexpr float PI = 3.14159265358979323846f;

class Analyzer {
    std::array<float, N> samples{};
    std::array<float, N> window{};
    std::array<unsigned, N> reverse{};
    std::array<std::complex<float>, N / 2> twiddles{};
    std::array<std::complex<float>, N> spectrum{};
    std::array<float, BINS> previous{};
    // 20 ms attack, 140 ms release, calculated once for a 1/60 s hop.
    const float attack = 1 - std::exp(-1.0f / (60 * 0.020f));
    const float release = 1 - std::exp(-1.0f / (60 * 0.140f));
    float windowSum = 0;
    unsigned cursor = 0;
public:
    Analyzer() {
        for (unsigned i = 0; i < N; ++i) {
            window[i] = 0.5f - 0.5f * std::cos(2 * PI * i / (N - 1));
            windowSum += window[i];
            unsigned source = i, destination = 0;
            for (int bit = 0; bit < 12; ++bit) {
                destination = (destination << 1) | (source & 1);
                source >>= 1;
            }
            reverse[i] = destination;
        }
        for (int i = 0; i < N / 2; ++i) {
            const float angle = -2 * PI * i / N;
            twiddles[i] = {std::cos(angle), std::sin(angle)};
        }
    }

    bool frame(const std::array<float, HOP * 2>& input) {
        for (int i = 0; i < HOP; ++i) {
            const float left = std::isfinite(input[i * 2]) ? std::clamp(input[i * 2], -1.0f, 1.0f) : 0;
            const float right = std::isfinite(input[i * 2 + 1]) ? std::clamp(input[i * 2 + 1], -1.0f, 1.0f) : 0;
            samples[cursor] = 0.5f * left + 0.5f * right;
            cursor = (cursor + 1) & (N - 1);
        }
        // The initial window is zero-padded: emit from the first 800 samples.
        for (unsigned i = 0; i < N; ++i)
            spectrum[reverse[i]] = {samples[(cursor + i) & (N - 1)] * window[i], 0};
        for (int length = 2; length <= N; length <<= 1) {
            const int half = length / 2;
            const int step = N / length;
            for (int start = 0; start < N; start += length) {
                for (int j = 0; j < half; ++j) {
                    const auto u = spectrum[start + j];
                    const auto v = spectrum[start + j + half] * twiddles[j * step];
                    spectrum[start + j] = u + v;
                    spectrum[start + j + half] = u - v;
                }
            }
        }
        for (int bin = 0; bin < BINS; ++bin) {
            const float amplitude = std::abs(spectrum[bin]) * (bin == 0 ? 1 : 2) / windowSum;
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
    std::array<float, HOP * 2> input{};
    while (std::fread(input.data(), sizeof(float), input.size(), stdin) == input.size()) {
        if (!analyzer.frame(input)) {
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
