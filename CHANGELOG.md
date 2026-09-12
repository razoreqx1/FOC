# Changelog

## v1.78 — Build 079

- Added question-led Home and Shipyard task-force creation, reusable templates, S/M escorts and optional auxiliary support.
- Added own-yard distribution and combined NPC/owned-yard orders. Select owned-yard construction to use only your stations; combined orders prefer NPC suppliers where available.
- Added compatible saved loadouts, equipment-slot editing and service-crew/marine workup; Academy recruitment supports 100 personnel.
- Added optional guarded capture attempts; success is not guaranteed.
- Corrected the native service-crew role and guarded repair of exactly matched, unattempted saved requests.
- Improved workflow pointers, visible template saving and own-yard messaging.


## v1.72 — Build 073

- Fixed Academy list errors when a ship's sector is unavailable.
- Marine and vacant-captain lists safely display UNKNOWN SECTOR without changing their ship identities or eligibility.
- No changes to crew assignments, fleet orders, or purchasing.

## v1.71 — Build 072

- Added Coverage and Fleet Templates: save fleet composition and Home, review NPC suppliers and equipment, and confirm the whole-fleet purchase price once.
- Added separate player-yard construction preview and retained NPC purchase/delivery review.
- Improved existing-purchase readback across reload and no-charge recovery of already purchased ships into their fleet.
- Recovery can reconcile missing order history for explicitly reviewed idle Hold Position ships with empty queues. Both recovery and delayed assembly preserve changed player orders and assignments.
- Delivery, recovery approval, assembly, patrol submission, and arrival are distinct reported stages; status checks do not repeat purchases.
- Includes independent, default-off combat repair/return and transport emergency docking settings. NPC repair can spend credits; interrupted repair reload behavior is documented separately from purchase recovery.
- Updated the complete browser player guide with B072 recovery, native hierarchy, patrol, and reload screenshots. Updated installation, quick start, and archive checksums; older releases and PDF guides remain available.

## v1.55 — Build 056

- NEW: Session History pages the retained operational archive, including yellow distress and red damage events.
- NEW: Native X4 map inspection for new distress records with stored subject identity; recorded-sector fallback when the subject is gone.
- NEW: Refresh-aware event deduplication and stable older-page browsing.
- FIXED: Session History displaying diagnostic refresh summaries instead of operational alerts.
- Updated the browser-readable player guide. Existing v1.54 PDF remains available.
- Automatic Repair and Return remains outside this update.

## v1.54 — Build 055

- Added Strategic Ops workspaces for Carrier Air Wings, Sector Defense Grid, Convoy Escort, Mobile Logistics, and Coordinated Assault.
- Added carrier role/profile controls with exact native group assignment and correlated save readback.
- Added a direct live X4 map inspection button for the selected carrier or fleet, separate from FOC location marking.
- Restored saved carrier/group role and recall thresholds into the editor; displayed Saved wing separately from unsaved edits.
- Preserved keyed carrier drafts through Refresh and navigation.
- Corrected carrier confirmation formatting and preserved Last Action during strategic refresh.
- Updated player documentation with the new workspaces, consequential-action boundaries, and menu screenshots.


## v1.49 — Build 050 — 2026-09-03

### Historical Intelligence Map

- Added a dedicated full-screen FOC Historical Intelligence Map instead of handing location work to the ordinary X4 map.
- Added native holomap pan, right-drag rotation, wheel zoom, reset, Back, Escape, hover, and sector-selection behavior.
- Added hover intelligence for retained risk, enrolled-fleet presence, saved Fleet Homes, readiness, recent observations, and honestly unlocated threats.

### Exact FOC location marking

- Added request-scoped left-click location marking for exact Fleet Home coordinates and future FOC workflows that request a map point.
- Preserved the selected fleet and unsaved draft across the map handoff and return.
- Kept selection non-mutating: cancelling returns no location, and choosing a point sends no order.

### Evidence-based route analysis

- Added Pirate Activity and Heavy Patrol Routes filters over a bounded historical observation window.
- Added yellow, amber, and red route strokes based on retained FOC evidence rather than faction ownership.
- Retained neutral native gate lines when no qualifying report exists and explicitly avoided treating missing evidence as safety.

### Stability

- Stabilized the analysis dropdown so hover redraws do not close it before selection.
- Preserved bounded observation retention and one 30-second enrolled-fleet traversal sampler.
- Corrected the visible and packaged release identity to Build 050 / extension version 149.

## v1.39 — Build 040 — 2026-09-02

### Fleet planning and task forces

- Added up to eight save-backed named task forces with active/reserve fleet rotation while leaving X4's native fleet hierarchy unchanged.
- Added reusable fleet drafts, templates, and plain-language presets with preview-before-send safeguards.
- Added an alphabetical fleet finder for large empires and persistent draft recovery across save/load.
- Added direct-subordinate group policies for docking, resupply, distress response, and native fleet reinforcement.

### Workflow clarity and feedback

- Added optional next-step arrows to real workflow actions and a prominent pinned control to clear or restore them.
- Added a pinned, color-coded Last Action readback so button results remain visible while scrolling.
- Improved exact feedback for drafts, templates, subordinate-policy changes, task-force operations, and Academy assignments.

### Academy and recovery

- Added exact Marine assignment preview and verified transfer readback, including crew and Marine count changes.
- Hardened preview identity so a changed trainee/destination pair must pass a fresh preview before transfer.
- Expanded repair, replacement, and rebuild guidance while preserving native X4 pricing, resources, and completion authority.

### Release identity

- Corrected the visible and packaged release identity to Build 040 / extension version 139.
- Updated the complete player guide with the current workflows and runtime screenshots.

## v1.34 — Build 035 — 2026-09-02

### Fleet discovery and persistence

- Replaced partial faction-ship sampling with structural discovery from X4's live commander-and-subordinate hierarchy.
- Restored valid fleet drafts and recovery ledgers from saves while retiring stale records conservatively.
- Kept fleet eligibility and membership independent of names and old Reaction Force markers.

### Repair, replacement, and rebuilding

- Added a native Repair / Upgrade handoff for eligible damaged fleet ships.
- Added exact lost-ship blueprint and saved-loadout review.
- Added guarded, player-approved replacement and player-yard rebuild requests with native completion readback and fleet reattachment.

### Academy and staffing

- Expanded the Academy to a shared, bounded Pilot and Marine trainee roster.
- Added native seminar training, exact assignments, captain auto-fill preview/approval, and verified results.
- Added a dedicated Academy Store for explicit training-supply purchases.

### Distress response and safety

- Added a persistent incident/fleet flood gate that groups repeated attacks, selects one closest eligible fleet, and sends one named native Attack order.
- Added response locks and guarded release/return behavior to prevent duplicate order floods.
- Added a clear, saved Yes-or-No decision for an exact ship that remains marked as story- or mission-protected after its story is finished. The choice affects FOC only and never changes X4's story state.
- Automatically releases the exact player-owned Yaki cover ship when X4 positively reports its owning story complete.

### Interface and evidence

- Removed the non-operational Doctrine page and controls that did not map to implemented native orders.
- Improved Activity severity and result reporting.
- Dismisses the complete story-status question block after the player answers and uses plain ASCII button text for reliable X4 rendering.

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
