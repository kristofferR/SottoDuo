#include <assert.h>
#include <stdio.h>
#include "audio.h"

struct totals { unsigned original, inference, channels; double energy; };
static bool collect(void *context, unsigned type, const void *data, unsigned size) {
    struct totals *t = context;
    const float *samples = data;
    if (type == 1) t->original += size / (t->channels * 4);
    else {
        for (unsigned i = 0; i < size / 4; i++) {
            assert(isfinite(samples[i]));
            t->energy += samples[i] * samples[i];
        }
        t->inference += size / 4;
    }
    return true;
}
static void check(unsigned rate, unsigned channels, unsigned chunk, bool retain, unsigned tone, bool invert) {
    struct totals t = { .channels = channels };
    struct audio_converter a = { .rate = rate, .channels = channels, .emit = collect, .context = &t };
    int error;
    a.state = src_new(SRC_SINC_FASTEST, 1, &error);
    assert(a.state);
    float samples[AUDIO_BLOCK * 2];
    for (unsigned i = 0; i < rate;) {
        unsigned n = chunk < rate - i ? chunk : rate - i;
        for (unsigned f = 0; f < n; f++) for (unsigned c = 0; c < channels; c++)
            samples[f * channels + c] = sin(2 * M_PI * tone * (i + f) / rate) * (c && invert ? -0.5 : 0.5);
        assert(audio_push(&a, samples, n, retain));
        i += n;
    }
    assert(audio_flush(&a, true));
    assert(t.original == (retain ? rate : 0));
    assert(t.inference >= 15999 && t.inference <= 16001);
    double rms = sqrt(t.energy / t.inference);
    if (invert || tone > 8000) assert(rms < 0.005);
    else assert(rms > 0.34 && rms < 0.36);
    src_delete(a.state);
}
int main(void) {
    unsigned rates[] = {8000, 16000, 44100, 48000, 192000};
    unsigned chunks[] = {1, 127, 480, 8192};
    for (unsigned r = 0; r < 5; r++) for (unsigned c = 0; c < 4; c++) {
        check(rates[r], 1, chunks[c], false, 1000, false);
        check(rates[r], 2, chunks[c], true, 1000, false);
        check(rates[r], 2, chunks[c], true, 1000, true);
    }
    check(48000, 2, 480, false, 12000, false);
    puts("61 native resampling/interval/channel/anti-alias checks passed.");
}
