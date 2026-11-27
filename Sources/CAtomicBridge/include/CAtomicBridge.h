#ifndef CATOMIC_BRIDGE_H
#define CATOMIC_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PliwMixTapAudioState PliwMixTapAudioState;

/// Allocates a real-time-safe atomic audio parameter & metering block.
PliwMixTapAudioState * _Nonnull pm_audio_state_create(float initial_gain, bool initial_muted);

/// Frees the atomic state block. Must only be called after AudioDeviceStop & DestroyIOProc.
void pm_audio_state_destroy(PliwMixTapAudioState * _Nonnull state);

/// Updates target linear gain and mute flag from any control thread (lock-free).
void pm_audio_state_set_params(PliwMixTapAudioState * _Nonnull state, float target_gain, bool is_muted);

/// Reads target effective gain (0 when muted) on the real-time audio thread (lock-free).
float pm_audio_state_load_target_gain(const PliwMixTapAudioState * _Nonnull state);

/// Stores latest RMS/peak level from the real-time audio thread (lock-free).
void pm_audio_state_store_level(PliwMixTapAudioState * _Nonnull state, float level);

/// Reads latest level from UI thread (lock-free).
float pm_audio_state_load_level(const PliwMixTapAudioState * _Nonnull state);

/// Updates smoothed current gain owned exclusively by the real-time audio thread.
float pm_audio_state_get_current_gain(const PliwMixTapAudioState * _Nonnull state);
void pm_audio_state_set_current_gain(PliwMixTapAudioState * _Nonnull state, float gain);

#ifdef __cplusplus
}
#endif

#endif /* CATOMIC_BRIDGE_H */
