# Changelog

## v1.19 — Build 020 — 2026-08-31

Initial public GA release.

### Fleet command

- Added the focused one-button Patrol workflow on the Fleets page.
- Preserved per-fleet Home, patrol coverage, pattern, distress rules, thresholds, and return behavior.
- Confirmed Patrol or Protect Position as the intended native default before reporting `PATROL ACTIVE`.
- Added bounded player-asset distress intake and safeguarded native Attack dispatch.

### Readiness and staffing

- Added fleet readiness and captain-coverage reporting with separate proven-vacancy and unknown states.
- Added the bounded Training Academy roster and native seminar ladder.
- Added approved exact trainee-to-vacant-ship assignments with native pilot readback.

### Safety and evidence

- Protected mission/story ships, player-piloted ships, protected manual orders, ownership boundaries, locks, and critical orders.
- Added conservative handling for malformed or ambiguous third-party ship state.
- Added bounded Activity history and visible native-result callbacks.
- Added large-empire sampling and mutation limits, duplicate suppression, and a single 30-second automation scheduler.

### Build 020 correction

- Preserved Build/version/status identity across Home-map return while retaining the newly selected unsaved Home point.
