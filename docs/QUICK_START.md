# Fleet Operations Command quick start

## Open FOC

Load a save, open the in-game Fleet Operations Command entry, and wait for its bounded inventory snapshot to complete.

FOC contains ten focused pages:

1. **Command** — global authority modes and emergency controls.
2. **Fleets** — Home, patrol, distress, and selected-fleet deployment.
3. **Strategic Ops** — Coverage and Fleet Templates, Task Forces, Carrier Air Wings, Sector Defense Grid, Convoy Escort, Mobile Logistics, and Coordinated Assault.
4. **Readiness** — captain coverage, proven vacancies, and staffing previews.
5. **Training Academy** — trainees, seminars, and exact assignments.
6. **Academy Store** — approved training-supply purchases and verified inventory results.
7. **Fleet Response** — distress incidents and eligible dispatch.
8. **Activity** — requests, blockers, and native readback.
9. **Operations Map** — historical sector intelligence, saved Homes, fleet presence, readiness, and evidence-based route filters.
10. **Settings** — persistent authority and safety behavior.

## Send a fleet on patrol

1. Open **Fleets**.
2. Select a player-owned combat fleet.
   Use the alphabetical **Fleet finder** when the list is long.
3. Confirm its commander and captain evidence.
4. Select **Choose Home Point on Map**, then short-left-click the exact point on a player-known sector in FOC's dedicated map. Dragging pans; Escape cancels.
5. Configure distress-response range.
6. Configure ship/station response, distress scope, urgency, hull thresholds, and return behavior.
7. Review the summary at the bottom of the page.
8. Select **Send This Fleet on Patrol — Replaces Current Orders**.

FOC can mark real next steps with `->`. Use the pinned **Clear Next-Step Pointers** button to hide them and **Show Next-Step Pointers** to restore them. The pinned **Last Action** line remains visible while you scroll and reports whether the last button succeeded or was blocked.

FOC saves and unlocks only that fleet, replaces only eligible current orders, starts a native Patrol or Protect Position default, and arms the configured distress response. It reports active only after X4 returns the intended native order identity.

If FOC identifies a possible story or mission ship, read the exact-ship question carefully. Choose **Yes** while the ship is still part of a story or mission. Choose **No** only after that story or mission is finished. The answer changes FOC's protection for that ship; it never changes the game's story.

## Inspect historical intelligence

1. Open **Operations Map**.
2. Hover a player-known sector cell to read retained risk, fleet presence, saved Homes, readiness, and recent observations.
3. Use left-drag to pan, right-drag to rotate, and the mouse wheel to zoom.
4. Select **Pirate Activity** to show routes adjacent to retained positively identified pirate attacks on player-owned assets.
5. Select **Heavy Patrol Routes** to show observed adjacent-gate crossings by enrolled FOC fleet commanders.
6. Read yellow, amber, and red as increasing retained evidence, not faction ownership or predicted danger.
7. Select **Back to FOC** or press Escape when finished.

No colored route means no qualifying observation inside the active window. It never means the route is proven safe.

## Understand results

- **Unknown** — the required evidence is absent or incomplete.
- **Blocked / Action Required** — a safety guard stopped the requested step; earlier orders or completed parts may still exist. Read the retained result.
- **Pending** — FOC submitted a request and is waiting for native readback.
- **Active / Confirmed** — X4 returned the expected native state.

If an action is blocked, read the orange result text before changing settings. FOC deliberately stops when identity, ownership, captain state, Home, mission safety, manual-order safety, or another required fact cannot be proven.

## Distress response

FOC records fresh attacks on player ships and stations. Repeated attacks from the same current threat are grouped. A response must pass the saved class, hull, urgency, range, freshness, ownership, captain, player-control, story, lock, and critical-order safeguards. One closest eligible fleet receives one response order.

Full Automation is optional. It uses the same gates and attempts at most one dispatch per 30-second scheduler cycle.

## Captain vacancies

Open **Readiness** to distinguish proven captain vacancies from unknown records. Ships without captains cannot execute normal orders. Use **Training Academy** to review Pilots and Marines, train with native seminars, approve an exact assignment, or preview captain auto-fill. Use **Academy Store** for approved training-supply purchases. FOC never replaces an existing captain without approval.


## Configure a carrier wing

Select the carrier on **Fleets**, then **Strategic Ops -> Carrier Air Wings**. Choose the direct group, role, and damage-recall threshold. **Saved wing** is the stored profile; dropdown changes remain drafts until **Apply to this exact X4 group and save profile** succeeds. Save your game normally afterward.

Use **Show selected fleet / ship in X4 map** to inspect the commander without applying the draft. Home, rally-point, and target selection still use the separate FOC Operations Map.

## Purchase or recover a fleet

Open **Strategic Ops -> Coverage and Fleet Templates**. Save a Home and composition, open the saved fleet's **Review / Buy**, and prepare its whole-fleet quote. Inspect hulls, equipment, suppliers, quantities, and total before confirming purchase once. Saving or preparing alone does not buy ships.

For ships already purchased, choose **Open Saved Fleet Templates -> Check Prepared Fleet Order -> Review Retained Fleet Recovery - No Charge**. Inspect the exact retained ships, then confirm recovery once if eligible. Use **View Verified Purchases / Fleet Delivery** to read assembly status. Do not buy again because delivery or readback is pending.

See the [illustrated purchase and recovery walkthrough](PLAYER_GUIDE.md#8f-coverage-and-fleet-templates---plan-buy-and-recover).

## Other Strategic Ops workspaces

- **Sector Defense Grid:** save Task Force coverage and reserve escalation; dispatch and return have separate buttons.
- **Convoy Escort:** attach an exact escort to a civilian miner/trader, then release and restore its prior hierarchy.
- **Mobile Logistics:** assign an auxiliary to native Supply Fleet; no supply purchase or cargo transfer is performed by this page.
- **Coordinated Assault:** select rally and target on the FOC map, save roles, then explicitly Rally or Launch. Reserve-role fleets rally without launching.

See the [complete player guide](PLAYER_GUIDE.md#8a-carrier-air-wings---configure-the-selected-carrier) for actions and safeguards.
