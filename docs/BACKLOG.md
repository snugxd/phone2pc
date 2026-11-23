# Backlog

## Feel improvements (after clamp fix and settings)

All improvements in this section depend on first fixing the PC scroll clamp so that movement beyond the per-packet limit is retained and injected later instead of being discarded. They should also follow the settings work so experimental feel changes can be exposed as explicit, reversible options rather than silently changing established behavior.

### Optional mild scroll velocity acceleration

Add an optional, mild acceleration curve that increases scroll output only for fast two-finger movement, while leaving slow and normal movement close to linear for precision. Velocity must be calculated from phone pointer-event timestamps, not PC packet-arrival timing, and the resulting multiplier must be applied before movement enters the cumulative scroll accumulators. This should be off by default. Risks include unpredictable distance, overshoot during quick direction reversals, sensitivity to noisy event timing, and making packet-loss or clamp problems harder to diagnose if the curve is too aggressive.

### Scroll momentum after finger lift

Allow an optional inertial continuation based on recent two-finger velocity, decelerating smoothly after both fingers lift so long pages can be traversed without repeatedly repositioning the hand. Momentum must stop immediately on any new touch, app pause, or network disconnect, and should remain independently configurable. Risks include runaway or surprising scrolling, stale velocity producing motion in the wrong direction, lifecycle events leaving a timer active, and queued or lost UDP packets making the visible deceleration differ from the phone's intended motion.

### Cursor acceleration curve

Add a configurable cursor acceleration curve so slow single-finger movement remains precise while fast movement covers more screen distance, compensating for the phone's smaller physical touch area. The curve should be based on phone event velocity and designed to preserve predictable behavior around low speeds and direction changes. Risks include cursor overshoot, inconsistent feel when event timing varies, amplification of noisy deltas, and interaction with the PC's existing per-packet movement clamp.

### Edge auto-scroll for drag and selection only

Support optional edge-triggered scrolling only while dragging or selecting, not during ordinary two-finger scrolling. Activation should require a dwell near the edge, speed should increase gradually as the pointer approaches the edge, and scrolling must stop safely when the pointer leaves the edge, the touch lifts or is cancelled, the app pauses, or the connection is lost. This should be off by default. Risks include accidental or runaway scrolling, difficulty recovering when the user reaches an edge unintentionally, timers surviving cancellation paths, and network interruption delaying the stop signal.
