#ifndef MAJORDOMO_BUILD_WHISPER_DICTATE
int main() { return 0; }
#else
#include "whisper.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <iterator>
#include <string>
#include <thread>
#include <vector>

namespace {
struct Params {
    std::string model;
    std::string language = "auto";
    int threads = std::max(1u, std::thread::hardware_concurrency());
    bool no_gpu = false;
    bool no_flash_attn = false;
};

void usage(const char * program) {
    std::fprintf(stderr, "usage: %s --model <path> [--language <lang|auto>] [--threads N] [--no-gpu] [--no-flash-attn]\n", program);
    std::fprintf(stderr, "reads mono 16kHz float32 PCM from stdin and writes transcript text to stdout\n");
}

bool parse_args(int argc, char ** argv, Params & params) {
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--model" && i + 1 < argc) {
            params.model = argv[++i];
        } else if (arg == "--language" && i + 1 < argc) {
            params.language = argv[++i];
        } else if (arg == "--threads" && i + 1 < argc) {
            params.threads = std::max(1, std::atoi(argv[++i]));
        } else if (arg == "--no-gpu") {
            params.no_gpu = true;
        } else if (arg == "--no-flash-attn") {
            params.no_flash_attn = true;
        } else if (arg == "-h" || arg == "--help") {
            usage(argv[0]);
            std::exit(0);
        } else {
            std::fprintf(stderr, "unknown argument: %s\n", arg.c_str());
            return false;
        }
    }

    return !params.model.empty();
}

void whisper_log_callback(enum ggml_log_level level, const char * text, void * /* user_data */) {
    switch (level) {
        case GGML_LOG_LEVEL_WARN:
        case GGML_LOG_LEVEL_ERROR:
        case GGML_LOG_LEVEL_INFO:
            std::fputs(text, stderr);
            break;
        default:
            break;
    }
}

std::vector<float> read_pcm_from_stdin() {
    std::ios::sync_with_stdio(false);
    std::vector<char> bytes((std::istreambuf_iterator<char>(std::cin)), std::istreambuf_iterator<char>());
    if (bytes.empty()) {
        return {};
    }

    if (bytes.size() % sizeof(float) != 0) {
        std::fprintf(stderr, "stdin size %zu is not aligned to float32 samples\n", bytes.size());
        return {};
    }

    std::vector<float> pcm(bytes.size() / sizeof(float));
    std::memcpy(pcm.data(), bytes.data(), bytes.size());
    return pcm;
}
} // namespace

int main(int argc, char ** argv) {
    Params params;
    if (!parse_args(argc, argv, params)) {
        usage(argv[0]);
        return 2;
    }

    auto pcm = read_pcm_from_stdin();
    if (pcm.empty()) {
        std::fprintf(stderr, "no microphone PCM received on stdin\n");
        return 3;
    }

    whisper_log_set(whisper_log_callback, nullptr);

    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = !params.no_gpu;
    cparams.flash_attn = !params.no_flash_attn;

    whisper_context * ctx = whisper_init_from_file_with_params(params.model.c_str(), cparams);
    if (ctx == nullptr) {
        std::fprintf(stderr, "failed to load model: %s\n", params.model.c_str());
        return 4;
    }

    whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.print_progress = false;
    wparams.print_special = false;
    wparams.print_realtime = false;
    wparams.print_timestamps = false;
    wparams.translate = false;
    wparams.no_context = true;
    wparams.no_timestamps = true;
    wparams.single_segment = false;
    wparams.language = params.language.c_str();
    wparams.n_threads = params.threads;
    wparams.greedy.best_of = 1;
    wparams.temperature_inc = 0.0f;

    const int rc = whisper_full(ctx, wparams, pcm.data(), static_cast<int>(pcm.size()));
    if (rc != 0) {
        whisper_free(ctx);
        std::fprintf(stderr, "whisper_full failed: %d\n", rc);
        return 5;
    }

    const int segment_count = whisper_full_n_segments(ctx);
    for (int i = 0; i < segment_count; ++i) {
        const char * text = whisper_full_get_segment_text(ctx, i);
        if (text != nullptr) {
            std::fputs(text, stdout);
        }
    }
    std::fputc('\n', stdout);
    std::fflush(stdout);

    whisper_print_timings(ctx);
    whisper_free(ctx);
    return 0;
}
#endif
