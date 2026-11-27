#include "CAtomicBridge.h"
#include <stdatomic.h>
#include <stdlib.h>

struct PliwMixTapAudioState {
    _Atomic float target_gain;
    _Atomic bool is_muted;
    _Atomic float peak_level;
    float current_gain; // Accessed only on the single real-time Core Audio IOProc thread
};

PliwMixTapAudioState * _Nonnull pm_audio_state_create(float initial_gain, bool initial_muted) {
    PliwMixTapAudioState *state = (PliwMixTapAudioState *)calloc(1, sizeof(PliwMixTapAudioState));
    atomic_init(&state->target_gain, initial_gain);
    atomic_init(&state->is_muted, initial_muted);
    atomic_init(&state->peak_level, 0.0f);
    state->current_gain = initial_muted ? 0.0f : initial_gain;
    return state;
}

void pm_audio_state_destroy(PliwMixTapAudioState * _Nonnull state) {
    free(state);
}

void pm_audio_state_set_params(PliwMixTapAudioState * _Nonnull state, float target_gain, bool is_muted) {
    atomic_store_explicit(&state->target_gain, target_gain, memory_order_relaxed);
    atomic_store_explicit(&state->is_muted, is_muted, memory_order_relaxed);
}

float pm_audio_state_load_target_gain(const PliwMixTapAudioState * _Nonnull state) {
    if (atomic_load_explicit(&state->is_muted, memory_order_relaxed)) {
        return 0.0f;
    }
    return atomic_load_explicit(&state->target_gain, memory_order_relaxed);
}

void pm_audio_state_store_level(PliwMixTapAudioState * _Nonnull state, float level) {
    atomic_store_explicit(&state->peak_level, level, memory_order_relaxed);
}

float pm_audio_state_load_level(const PliwMixTapAudioState * _Nonnull state) {
    return atomic_load_explicit(&state->peak_level, memory_order_relaxed);
}

float pm_audio_state_get_current_gain(const PliwMixTapAudioState * _Nonnull state) {
    return state->current_gain;
}

void pm_audio_state_set_current_gain(PliwMixTapAudioState * _Nonnull state, float gain) {
    state->current_gain = gain;
}
