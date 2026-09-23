#pragma once
#include <math.h>
#include <samplerate.h>
#include <stdbool.h>
#include <stdint.h>

/* Keep one input block so end_of_input accompanies the real final samples. */
#define AUDIO_BLOCK 8192u
struct audio_converter {
    SRC_STATE *state;
    unsigned rate, channels, pending;
    float mono[AUDIO_BLOCK], output[AUDIO_BLOCK * 2 + 256];
    bool (*emit)(void *, unsigned, const void *, unsigned);
    void *context;
};
static bool audio_flush(struct audio_converter *a, bool end) {
    SRC_DATA d = { .data_in = a->mono, .data_out = a->output,
        .input_frames = a->pending, .output_frames = AUDIO_BLOCK * 2 + 256,
        .src_ratio = 16000.0 / a->rate, .end_of_input = end };
    if (src_process(a->state, &d) || d.input_frames_used != a->pending) return false;
    a->pending = 0;
    return !d.output_frames_gen || a->emit(a->context, 2, a->output, d.output_frames_gen * 4);
}
static bool audio_push(struct audio_converter *a, const float *samples, unsigned frames, bool retain) {
    if (frames == 0 || frames > AUDIO_BLOCK || !audio_flush(a, false)) return false;
    for (unsigned i = 0; i < frames; i++) {
        double sum = 0;
        for (unsigned c = 0; c < a->channels; c++) {
            float value = samples[i * a->channels + c];
            if (!isfinite(value)) return false;
            sum += value;
        }
        a->mono[i] = sum / a->channels;
        if (!isfinite(a->mono[i])) return false;
    }
    a->pending = frames;
    return !retain || a->emit(a->context, 1, samples, frames * a->channels * 4);
}
