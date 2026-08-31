# Fleet Operations Command quick start

## Open FOC

Load a save, open the in-game Fleet Operations Command entry, and wait for its bounded inventory snapshot to complete.

FOC contains eight focused pages:

1. **Command** — global authority modes and emergency controls.
2. **Fleets** — Home, patrol, distress, and selected-fleet deployment.
3. **Readiness** — captain coverage, proven vacancies, and staffing previews.
4. **Training Academy** — trainees, seminars, and exact assignments.
5. **Doctrine** — effective patrol-plan preview and protections.
6. **Fleet Response** — distress incidents and eligible dispatch.
7. **Activity** — requests, blockers, and native readback.
8. **Settings** — persistent authority and safety behavior.

## Send a fleet on patrol

1. Open **Fleets**.
2. Select a player-owned combat fleet.
3. Confirm its commander and captain evidence.
4. Choose its Home sector and exact Home point.
5. Configure patrol range, sector scope, and pattern.
6. Configure ship/station response, distress scope, urgency, hull thresholds, and return behavior.
7. Review the summary at the bottom of the page.
8. Select **Send This Fleet on Patrol — Replaces Current Orders**.

FOC saves and unlocks only that fleet, replaces only eligible current orders, starts a native Patrol or Protect Position default, and arms the configured distress response. It reports active only after X4 returns the intended native order identity.

## Understand results

- **Unknown** — the required evidence is absent or incomplete.
- **Blocked / Action Required** — a safety guard stopped the action; nothing changed.
- **Pending** — FOC submitted a request and is waiting for native readback.
- **Active / Confirmed** — X4 returned the expected native state.

If an action is blocked, read the orange result text before changing settings. FOC deliberately stops when identity, ownership, captain state, Home, mission safety, manual-order safety, or another required fact cannot be proven.

## Distress response

FOC records fresh attacks on player ships and stations. A response must pass the saved class, hull, urgency, range, freshness, ownership, captain, player-control, story, lock, and critical-order safeguards.

Full Automation is optional. It uses the same gates and attempts at most one dispatch per 30-second scheduler cycle.

## Captain vacancies

Open **Readiness** to distinguish proven captain vacancies from unknown records. Ships without captains cannot execute normal orders. Use **Training Academy** to review available trainees and seminars, then approve an exact trainee-to-ship transfer. FOC never replaces an existing captain automatically.
