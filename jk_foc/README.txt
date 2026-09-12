Fleet Operations Command - Build 079 / version 178 TEST

Build 079: service-crew role correction
- Uses the native service-crew role; marine and captain handling remain separate.
- Repairs only unattempted missing service roles with exact saved-workup evidence.
- Pending transfers are never replayed by this correction.

Retained fleet orders, equipment and crew workup:
- Shipyard offers owned-yard, NPC or mixed sourcing under one order approval.
  Owned ships are spread across eligible player yards. Native resources, queues,
  blueprints and equipment availability still control construction time.
- Choose saved X4 loadouts or edit compatible equipment slots, ammunition,
  drones and software. Save equipment and crew with the reusable template.
  Equipment choices apply to every ship of that model in the template.
- Select marines and service crew separately, within each ship's native capacity.
  Existing Academy recruits are reserved before ordering and transferred after
  delivery. No free people are generated. The Academy pool supports100 recruits.
  Assembly waits for exact requested crew transfers to be verified.
- Settings offers Attempt Capture, initially OFF. Eligible combat fleets with
  sufficient available marines may attempt boarding hostile capital ships.
  Outmatched/unknown/conflicting cases continue normal combat. Capture is not
  guaranteed; the latest outcome is retained in Settings across reload.
- The completed fleet gathers and waits at its assembly sector, ready for the
  player to choose its mission in Fleets. Order submission is not arrival proof.
- Saving and reviewing spend nothing. Partial or uncertain orders/transfers are
  retained, never automatically purchased or dispatched again.
- TEST artifact: affected native execution, UI, reload, arrival, crew transfer
  and boarding behavior require in-game acceptance of this exact build.

Build 077: owned-yard construction review
- Check only requested hulls at eligible owned yards, without repeatedly scanning
  unrelated module catalogues. Blueprint and equipment checks remain in force.
- Construction review gives specific limits or unavailable-hull reasons.

Build 076: S/M combat escorts
- The Shipyard escort picker offers S- and M-class combat ships only.
- Flagship selection remains unchanged; auxiliary supply ships such as Nomad
  stay in their separate picker. Existing fleets, templates and jobs are retained.

Build 075: clearer Shipyard flow
- Follow the -> next-step pointer. Short pages use measured available space;
  paging remains only when the current viewport needs it.
- Choose SAVE AS TEMPLATE - NO PURCHASE to keep a reusable composition.
- NPC buying and player-yard construction have separate availability checks.
  An unavailable route names the hull/reason instead of opening a failed quote.
- Known unavailable auxiliary hulls remain visible with their supplier/blueprint
  or loadout reason. The exact historical missing-Nomad cause is not confirmed.
- Purchase approval, resources and delayed assembly safeguards remain unchanged.

Build 074: guided Home and Shipyard
- Home starts with questions. Choose "How do I build a new task force?" or open Shipyard.
- Start a composition or reuse a saved template. Choose a flagship, escort hulls/counts,
  optionally one auxiliary such as a Nomad, then an assembly sector.
- Review the NPC equipment and complete price, or the owned-yard construction plan.
  Saving the template and preparing the review spend nothing. Approve the order once.
- Native yard availability, blueprints, licences, equipment and resources still apply.
- Delivered ships are assembled under the selected flagship. Escorts defend it; an
  auxiliary receives Supply Fleet. Native follow/supply orders are checked explicitly.
- The leader gathers and waits at the assembly sector. READY FOR ASSIGNMENT means
  assembly/order readback, not physical arrival. Select the fleet in Fleets to choose
  Home and mission, then Send once. New fleets are locked against global FOC plans
  until explicitly sent/unlocked; older purchases retain their previous patrol policy.
- This construction action does not purchase supply cargo or promise repairs. Native
  auxiliary behavior may subsequently trade for resources under the game's rules.
- CHECK never buys again. Incomplete receipts or changed player orders can still
  require exceptional no-charge recovery; do not repeat an uncertain purchase.
- TEST only. Native UI, construction, delivery, supply behavior, assembly and save/reload
  require testing of this exact artifact. No live installation or publication included.

Retained Build 073: Academy snapshot safely handles actors without a current sector.

Historical Build 072 recovery order correction:
- Explicit recovery can reconcile missing order history with only an empty-queue default Hold Position, never queued work or another assignment.
- Review captures exact current orders; confirmation and delayed assembly preserve newer player changes. Historical order records remain intact.
- Recovery diagnostics identify ship and order-check results. No second purchase or charge; actual in-game assembly remains RUNTIME ACCEPTANCE REQUIRED.

Historical Build 071 purchase tracking and explicit recovery:
- Retained order status no longer requires expired native task objects to cross into Lua.
- New purchases retain an exact receipt/component link when native readback supplies it. Missing links never cause another payment or purchase.
- CHECK PREPARED FLEET ORDER shows retained ships. REVIEW RETAINED FLEET RECOVERY checks a complete delivered fleet, then offers one explicit no-charge confirmation.
- Recovery uses only exact ship references already retained by FOC, for any supported hull/count. It does not search for similar ships or reconstruct old individual receipt links by position.
- Incomplete records, unfinished ships, changed ownership/orders, protected ships and stale reviews block recovery. Older attempts without usable prepared-purchase records cannot be automatically recovered.
- Original receipts remain intact. Existing guarded assembly rechecks ships before acting; status, delivery, assembly and runtime acceptance are separate.
- B070 diagnostic native lookups of old receipt IDs are retired. Runtime acceptance is required.

Historical Build 070 diagnostics (superseded):
- Manual CHECK records saved MD task type/existence/string/ship and independent native receipt-ID lookups.
- At most two samples per Lua session; first eight rows/receipts per sample. No probe purchases, bindings or assignments.
- Failed status reports identify rejected fields/types/counts; acceptance and purchase logic are unchanged.
- Load the existing saved purchase and use CHECK PREPARED ORDER / DELIVERY once. Do not prepare or confirm another purchase.
- Send the result screenshot, then exit normally for debug-log review. No automatic purchase retry is added.
- Native runtime acceptance is required. B068 history follows unchanged.

Build 068 correction:
- Home and supplier lookup IDs now use validated native transport; textual quote/readback keys remain unchanged.
- Missing identities stop confirmation before a request is sent. All reservation safeguards remain active.
- Exact B067 failure and corrected serialized transport are covered by regression tests. Native runtime acceptance is required.

Retained Build 067 diagnostics:
- Reservation failures identify the first rejected check (R01-R26), with request/Home and supplier context when evaluated.
- Refusal remains on the error/report page after CHECK. Screenshot the entire page and report it to the developer; do not repeat an uncertain purchase.
- Bounded RESERVE_PACKET logging records the outgoing values/types.
- No purchase safeguard is bypassed; payment, capture locks, native orders, delivery and assembly are unchanged. No automatic retry.

Status: TEST candidate. RUNTIME ACCEPTANCE REQUIRED. No installation included.

Build 066 corrections:
- Resolve native UI shiptrader identities with the source-specific conversion.
- Retain original purchase errors in warning color with screenshot-report help.
- Guide NPC purchase paging, preparation and error recovery with next arrows.
- No retained order is not a zero-cost receipt. CHECK preserves failure evidence.
- Bounded purchase diagnostics aid reporting; no added background polling.

Retained Build 065 prepared purchasing:
- Save a fleet and Home, then PREPARE ENTIRE SAVED FLEET PURCHASE.
- Inspect every hull, NPC supplier, medium equipment, quantity and full price.
- Only CONFIRM PURCHASE spends credits and authorizes delivery-time assembly.
- Native orders can wait for materials. Exact task/payment verification precedes
  FOC adoption; captains, ownership and unchanged orders precede Home patrol.
- CHECK reads retained orders only. Partial or uncertain purchases are retained
  and must not be repeated; no automatic purchase replay or speculative refund.
- Native loadouts/payment, UI, delivery and reload require exact-artifact tests.

Retained Build 063 corrections:
- Resolve incoming Home and NPC supplier IDs before native object checks.
- Save refusals explain the failed requirement, retain the draft and unlock
  correction after the matching refusal. Timeouts still require reconciliation.
- Recovery return checks safely handle an absent docking-order record without
  changing repair/reload policy or overwriting newer manual work.

Retained Build 062 corrections:
- Regular proposals exclude native limited/research-restricted hulls and require
  known acquisition permissions. No display-name blacklist is used.
- Saved templates include Home. Older templates ask for Home before ordering.
- Saving advances to saved plans after complete readback. Reviewing an identical
  saved draft works; a different unsaved draft stays protected.
- NPC suppliers remain available even when an owned yard can build that hull.
- Construction reports the failed blueprint, yard, equipment or Home stage.

Retained Build 061 corrections:
- Back/navigation redraw waits for dropdown closure and cannot stay locked after deactivation.
- Buttons acknowledge a click; fleet order and repair refresh show their actual completed results.
- Repeated clicks on the same rendered button are suppressed until redraw.
- No installation or publication. Test dropdown selection/cancel, Saved Templates > Back,
  command results, repair refresh, other tabs and close/reopen in X4.

Retained Build 060 features:
- Command previews each saved FOC fleet's current order, proposed order and Home.
  Choose saved fleet orders, Patrol all fleet Home sectors, or Guard all fleet
  Home points. All Fleets means all saved FOC fleets, not every owned ship.
  Sending uses a single-use preview, rechecks fleet settings and membership,
  and leaves locked, busy, protected or recovery-engaged fleets alone.
- Task Force primary/backup roles and automatic swapping are retired. This does
  not remove carrier-wing or assault reserve roles, which are separate features.
- Fleet selection includes current assignment, command target and sector.
- Coverage, ship comparison, draft and saved plans have separate navigation steps.
- Map route overlays wait for camera movement to settle before resampling.
  Fixed red plus marks are removed. Exact hotspot cell-border recoloring is
  deferred by the player; route lines are not exact sector boundaries.

Create a fleet: Strategic Ops > Coverage and Fleet Templates.
1. Refresh coverage, select a hotspot, and read the fleet-needed recommendation.
   It uses retained attack samples and available fleet evidence, not a complete
   forecast of future traffic or guaranteed protection. Missing evidence is not NO.
2. Review the proposed combat hulls and quantities. Choose the suggested Home
   sector or another known sector. Save the composition before requesting ships.
3. With a compatible player yard and the required blueprints, prepare and confirm
   construction. Normal native construction resources are required; no free ships.
4. For NPC purchases, use the draft's purchase action. FOC arms exact task capture
   before opening X4's purchase menu. Confirm equipment, quantity and payment in
   that native menu. FOC does not silently spend money to repeat the purchase.
5. Return to NPC purchase review. Check progress, explicitly select only the
   purchases intended for this template, then approve that exact set. Matching
   hull/yard alone does not authorize adoption. The set must match all quantities.
6. Approved exact deliveries assemble automatically when ships and captains are
   available and safety checks pass. The first template entry leads the fleet.
   FOC saves its Home and orders a Home-sector patrol. Patrol ordered does not
   mean physically arrived. Inspect the fleet on X4's map for actual movement.

Delivery handling runs with FOC closed; CHECK reads retained progress and does
not buy ships or trigger assembly. Native queues may wait for resources. Inspect
the yard queue if delayed; do not buy again merely because delivery is pending.
NPC review lists retained QUEUED, DELIVERED, CANCELLED or DELIVERY UNCONFIRMED
records. Reported native task price is not a payment receipt. Approval is single
use; changed, missing or destroyed records block deployment. New manual orders
are protected. Unapproved tracking may be discarded without cancelling purchases.
Capture is bounded to one session, 30 minutes and 100 records, with explicit
expiry/overflow. Templates are limited to 20, with 8 hull entries and 100 ships.
Reload preserves records and approved delivery jobs, but closes capture. It never
reopens the purchase menu, repeats purchases or adopts unapproved candidates.

Dock selection now respects ship travel blacklists. Only completed cancellation
events end the recovery order. Prior-order readback is not proof of resumed trade
or delivery. The historical shelter cancellation cause and full repair/return
cycle still require exact-artifact runtime testing. Interrupted repairs retain
the separately authorized return/recheck policy, including a possible new fee;
that exception never applies to ship procurement or paid cargo transactions.

The following sections preserve prior-build history, not B060 completion claims.

Build 059: Strategic Ops usability cleanup. Task Force roles now say Primary
Response Fleet and Backup Fleet, with fleet names. Home defense priority is
explained and is not a Home location picker. Maintenance remains in Fleets.
Hotspot selection immediately shows area details before the longer template list.
Other Strategic Ops workspaces explain what their actions do. Map heading and
all current menu entry routes now identify Build 059 consistently.
This UI-only update does not add automatic buying, building or deployment.
Known runtime issue carried forward: B058 shelter orders were cancelled shortly
after being requested. This update does not fix that behavior or prove repairs.

Build 058: NEW Hotspots / Fleet Templates, available from the FOC Operations Map
and Strategic Ops > Coverage and Fleet Templates. Refresh reads retained civilian
attack samples from the last game hour. Select a hotspot to compare the nearest
unlocked enrolled fleet on default orders and its gate distance. Readiness and
dispatch eligibility still need checking. Suggested Home is a sector: choose a
safe exact point with the existing fleet Home picker, not an assumed safe berth.

Compare combat hulls to rank generated medium presets by speed or sustained
firepower. An owned hull blueprint plus a compatible owned yard gives a BUILD
route; otherwise an available NPC yard gives a BUY route. Unknown stats sort last.
The comparison is one-shot, one hull per visible menu update, paused off-page.
Build a composition manually or request a four-ship fast-response starter plan.
Save/load one of 20 numbered slots, up to 8 hull entries and 100 ships per template.
Save replaces the selected slot only after validation and exact complete readback.
Templates contain hull quantities, not exact equipment, software or modifications.
Confirm equipment, affordability, resources and purchase in X4's native menu.
The advisor never buys, builds, assigns ships, moves fleets or spends credits.

FIXED recovery cooldown storage: bounded MD records replace the invalid component
variable. Native DockAt children are recognized through their exact DockAndWait
reverse link before the parent's child link is populated. Release/end diagnostics
now include reasons. The prior log did not retain its early-exit reason; real
docking/repair/return still needs testing, and no prior success is inferred.

Build 057 adds independent OFF-default Settings switches
for combat repair/return and attacked-transport docking. NPC repairs may charge
player credits. No upgrades, ammunition or equipment replacements are requested.
Repair uses compatible fleet suppliers before player stations, then NPC stations.
Transport shelter is not released merely because a response fleet arrives.
Capital docks are exposed and do not guarantee invulnerability.
Interrupted repair jobs reset on reload; a new repair may charge again.
Jobs are event-driven, capped at 64, with no permanent empire damage scan.
Provider searches are bounded and use native distance ordering within each tier.
New manual orders take precedence. STOP disables both recovery options.
Quotes are rechecked before debit; actual payment and repairs have separate checks.
Equipment modification values are compared before/after repair without changing them.
Threat overflow holds conservatively until the player intervenes. Failed searches
wait for a later combat event after a cooldown; they do not continuously retry.
Exact game loading, orders, repairs, payment and save/reload need runtime testing.
No installation or publication is included in this TEST build.

Build 056 replaces diagnostic-only Session History with paged recorded activity.
Both views use the same save-persistent latest 50 events, including yellow distress
and red damage events. Refresh reloads a complete snapshot without duplicating IDs.
Detection, response, and resolution are separate events, not duplicate imports.
Older pages retain their window and show a newer-entry count; page 1 shows newest.
New distress detections record the exact subject and sector. Click its history
button to inspect the current subject in X4's live map without sending orders.
If the subject has disappeared, the button opens its recorded sector, not an
invented battle position. Legacy records without identity remain readable with
their map button disabled. Back restores the history view and scroll position.
Repair automation was deferred in B056; B057 introduces the opt-ins above.

Build 055 restores saved carrier wing settings by exact carrier ID and group.
The Saved wing row shows persistent readback separately from the editable draft.
Unsaved edits survive Refresh, group/carrier switches, and native-map Back.
Missing/invalid wing evidence is explicit and blocks Apply/Recall until valid.
New groups show an unsaved default draft, never a claimed saved 70-percent setting.
Reload testing must inspect the Saved wing row and CARRIER_SAVED_READBACK log
before pressing Apply. This build does not change automatic recall or orders.

Build 054 fixed the carrier result-message format and prevents the strategic
Refresh button from replacing the last saved action result. Carrier Air Wings
now has a bottom SHOW SELECTED FLEET / SHIP IN X4 MAP button. It opens X4's
live native map on the exact selected commander for inspection; opening it
does not apply settings or send orders. X4's normal map controls remain live.
Use Back to return to FOC with the selected fleet and unsaved wing draft.
FOC Home/rally/target marking still uses the dedicated FOC Operations Map.
Native-map focus/Back behavior and game save/reload require runtime acceptance.

Build 053 adds exact-carrier preflight before wing changes, direct native
identity for profile saves, correlated save replies, and conditional rollback
when persistence is rejected. Strategic refresh counts no longer replace the
last action result. Null-sector ships display UNKNOWN instead of a lookup error.
Rollback will not overwrite a group whose settings changed after the request.
Interrupted transactions and save/reload still require runtime acceptance.

Build 052 corrects the Build 051 strategic snapshot and carrier-automation
bridges by using the proven scalar-field-plus-commit event contract already
accepted elsewhere in FOC. It also guards commander identity reads and owns
the production-observation group before subscribing to its native event.

Build 051 completed the published strategic roadmap in one governed TEST
candidate. STRATEGIC OPS now includes the Carrier Air-Wing Manager, Sector
Defense Grid, Convoy Escort Operations, Mobile Logistics Fleet, and Coordinated
Assault Group. Carrier roles use X4's native group assignments and dock-at-
commander state with immediate readback and rollback. Defense and assault use
bounded named orders retained by FOC; return or abort only cancels the exact
current FOC order before restoring the fleet's saved Home order. Convoy escorts
use native Defence assignment without replacing the civilian's trade or mining
order. Proven auxiliary ships use native Supply Fleet assignment; FOC does not
buy cargo, spend credits, or invent resources.

The Historical Intelligence Map adds Combat Hotspots, Trade Route Risk,
Logistics Pressure, Economic Hotspots, Empire Trouble Spots, and Historical
Trends. Filter-colored route strokes and sector cross-markers are independent
of faction colors. All scores come from bounded player-observed attacks,
completed player trades, player-station production, pirate evidence, or enrolled
fleet traversal evidence. No observation is fabricated. Exact rally positions
and attackable assault targets are selected on the dedicated FOC map.

Build 050 keeps the Operations Map analysis dropdown open while it owns input.
Hover intelligence refreshes are deferred until the dropdown closes, preventing
the overlay rebuild from destroying the option list before a choice can be made.

Build 049 adds cell-hover intelligence, filter-driven FOC route analysis, and
a dedicated FOC location-marking mode. Fleet Home no longer opens X4's ordinary
map. Pirate colors use real pirate-tagged attacks; heavy patrol colors use only
observed adjacent-sector traversals by enrolled FOC fleets. Neutral native
connections remain visible when the selected filter has no report. Numeric
Helper state remains in positions 1 and 2, and all map evidence remains bounded.

Build 041 adds the first practical Interactive Executive Operations Map: a
clickable sector intelligence board built from current fleet/home evidence and
FOC's retained observations. Working filters select all sectors, threats, or
fleet homes across 15, 60, or 180-minute windows. Selecting a sector opens its
real readiness, coverage, and recent-event evidence, with working links to
Activity and Fleet Response. Unknown locations are counted but never invented.
This is an honest strategic board, not a clone of X4's private native 3D map.

Build 040 corrected the shared click acknowledgement so it never overwrites a
successful preview state before a guarded approval runs. This restores Marine
and Captain preview-to-transfer workflows while preserving immediate feedback.
The visible menu identity was also corrected to Build 040 / version 139.

Build 039 added a fixed, always-visible LAST ACTION line so operational buttons
immediately acknowledge a click and MD/native actions replace that message with
their proven success or failure readback. Template and preset actions explicitly
confirm that they changed only the visible draft and sent no order. The pointer
toggle now uses a unique purple background, and the fleet list adds an
alphabetical A-F/G-L/M-R/S-Z finder with deterministic name sorting.

Build 038 added contextual `->` next-step hints to enabled actions in every
multi-step workflow. More than one arrow means more than one valid choice.
CLEAR NEXT-STEP POINTERS hides the hints and SHOW NEXT-STEP POINTERS restores
them. Hints never enable a blocked action or change gameplay state. Build 038
also preserves the last complete Task Force display when an X4 native-screen
return does not repeat the authoritative Task Force payload.

Build 039 preserves accepted Build 036 and adds the complete experimental roadmap
as operational, bounded systems. There are no demonstration-only buttons.

The new TASK FORCES tab stores up to eight named groups without changing X4's
native fleet hierarchy. A fleet may belong to only one Task Force. Players can
save response priority, Home-sector zone, range, manual or full-automation
rotation, and distinct active/reserve fleets. Manual rotation revalidates both
fleets and Homes, returns the old active fleet to its post, activates the reserve
fleet's saved native order, verifies both orders, then swaps the saved roles.
Full automation uses the same 30-second one-mutation boundary and rotates only
when no distress dispatch occurred and the active fleet fails saved readiness.

Fleet Advanced Controls now expose X4's real subordinate-group switches for
docking with the commander, resupplying at fleet, responding to X4 distress
calls, and native fleet reinforcement. Every change is made for current direct
groups and read back immediately; a mismatch is BLOCKED. Reinforcement can use
X4's normal construction and resource rules. FOC never creates a free ship or
hides a cost.

Up to eight reusable fleet templates and six plain-language presets populate
visible draft settings only. They never send an order. Readiness policy stores
commander hull, fleet hull, captain coverage, and maximum fleet size gates.
Task Force Home sectors can be HIGH, NORMAL, or EXCLUDED response zones.
Threat response classifies the observed attacker as XS, S, M, L, XL, or UNKNOWN,
requires a matching minimum response tier (1, 1, 3, 6, or 10 ships), then selects
the smallest eligible ready fleet before distance and priority while retaining
the accepted exclusive incident locks.

Optional Emergency Retreat issues X4's native Flee order only for an enrolled
active fleet threatened by the exact observed attacker and below the saved hull
threshold. Story/mission ships, player control, critical orders, missing pilots,
and duplicate retreats remain blocked. Cargo dropping is disabled and return
behavior is explicit. Resolved response incidents create up to 50 persistent
after-action reports with victim, attacker, fleet, times, outcome, known losses,
and known damage; unavailable evidence is reported as UNKNOWN.

Build 035 repaired Build 032's exact Save 20 UI discovery failure by passing the
authoritative MD structural fleet registry directly to Lua instead of rebuilding
it from the first 500 faction ships. Recovery schema 4 discovers player-owned
top-level combat commanders structurally, requires at least one living combat
subordinate, and snapshots the commander plus every living non-unit ship in
allsubordinates. Fleet names and persisted Reaction Force markers never establish
eligibility or membership.

Build 035 also corrected completed-story false protection. FOC automatically
releases the player-owned Yaki cover ship when X4 reports Story_Yaki.Start
complete. When X4 still marks a ship as story- or mission-protected, the Fleets
page asks: "Is this ship still being used by a story or mission?" YES keeps it
protected; NO lets FOC control only that exact ship. The answer is saved by
stable ship ID. This FOC setting never changes X4's story state, and protection
remains the safe default. Build 035 separately remembers that the player has
answered, then removes the complete question, explanation, and button block.
Existing Build 034 NO answers and automatic completed-story releases migrate
as already answered. The buttons use plain ASCII text so X4 renders every
character correctly.
Station guards, station-commanded ships, non-combat/cargo/mining commanders,
and their subordinate escorts are excluded. Living records are deduplicated
only by stable non-null ship ID and retain immediate commander, group, and
assignment reconstruction data. Native fleetunits remain limited to X4's
missing/reconstitution-slot route. Valid LOST, NATIVE_LOST, and QUEUED records
are retained only as complete recovery-only orphan ledgers when their commander
is gone. Stale non-eligible ledgers are retired atomically, and every active
ledger reports expected versus distinct living records.

Build 039 is a TEST artifact. X4-dependent roadmap migration, native group-policy
readback, Task Force rotation, readiness and zone selection, native Flee behavior,
after-action persistence, schema-4 migration, structural
discovery, destruction
matching, construction completion/cancellation, hierarchy restoration, captain
recruitment/training/assignment, and save/reload behavior remain RUNTIME
ACCEPTANCE REQUIRED until RazorEQX tests this exact package.

Build 035 retains the separate Safety Thresholds button under Fleets. The page stores
independent manual-repair eligibility thresholds for enrolled reaction-force
ships and an all-player-owned default. The reaction value overrides that default
for enrolled ships. These settings only decide which
damaged ships FOC offers to the existing native repair handoff. X4 continues to
show the exact price/resources and requires player confirmation.

Distress response uses a persistent incident/fleet flood gate. Build 028 added a
new-save-load migration cue using X4's documented Setup.Start signal, creates
the lock list with the native list action, and guards every dispatch read. FOC
coalesces attacks from the same still-valid attacker into one bounded threat.
Detection/debug output for a locked threat is limited to one update per ten
seconds, with an immediate additional update when damage first turns red.
Player-owned attackers and friendly-fire/self events are rejected. FOC sorts
eligible reaction fleets by their current gated distance, sends exactly one
closest fleet one uniquely named native Attack order, and never retries that
threat merely because immediate readback failed or another fleet member is hit.
The responding fleet stays locked until the victim rises above its captured
distress threshold after a quiet period, or a full-hull/full-shield 100-percent
threshold victim is quiet, or the victim, attacker, or commander ceases to exist. FOC
cancels only its exact retained response order when that order is still current.
The configurable ship cap filters whole fleets; FOC never detaches ships or
issues subordinate orders.

What changed

- The top-level Doctrine tab and its non-operational page are removed.
- Fleet orders expose only implemented native orders: Patrol and Guard Home.
- Custom sector lists, custom routes, patrol-pattern controls, and misleading
  route-preview controls are removed. Saved legacy values are normalized safely.
- The former gate-count label is now Response range. It limits distress-response
  eligibility; it does not claim to define a patrol route or patrol area.
- Distress ownership remains player-only. The page no longer offers an
  unsupported "help anyone" scope.
- Live Activity stores an explicit severity on new rows. Ordinary distress calls
  are yellow. A ship attack is red only when the observed ship hull is below
  100 percent. Native rebuild requests for positively lost ship records are red.
  Older saved rows remain readable and are conservatively classified from their
  existing kind/detail data.
- Build 025 initialized the persistent pending Marine-transfer value to null,
  while its monitor admitted any existing value and dereferenced it as a table.
  Build 026 removes legacy null/incomplete state on load and starts the monitor
  only for a complete, non-null pending-transfer record. Valid pending transfers
  continue from their saved identity.

Repair / Replace / Rebuild

The new Fleets subpage is deliberately split into native, auditable operations:

1. Repair current ships
   FOC lists currently observed hull-damaged members, revalidates ownership,
   fleet membership, player control, mission/story protection, and critical
   non-cancelable orders, finds a known compatible non-enemy ship-trader
   facility, then opens X4's native Repair / Upgrade screen. X4 calculates and
   displays the price/resources and requires the player's confirmation. FOC does
   not create a free repair, accept a price, or report repair completion.

2. Lost-ship blueprint and loadout review
   FOC reads both a living selected commander's native fleet-unit records and
   the persistent exact recovery ledgers for every enrolled fleet. Recovery
   ledgers are refreshed when a draft is saved, a patrol is activated, and the
   menu opens while the fleet is still live. Each record retains exact macro,
   loadout, original fleet relationship, and mission/story protection state.
   Records are checked against ship-blueprint ownership, compatible player-yard
   hull capability, and saved-loadout equipment capability. FOC never guesses a
   replacement design or buys a blueprint.

3. Replace / rebuild lost ships
   Preview is required. Confirmation re-resolves the commander and every guard,
   then sends only exact lost records that have no current object or duplicate
   build, have the ship blueprint, and have a player-owned yard able to build the
   exact hull and saved loadout. A living commander retains X4's stock
   `reconstitute_fleet` route. A destroyed commander uses the documented generic
   player-yard construction action with the saved exact macro/loadout and the
   returned build-task identity. On native completion readback, FOC restores the
   original ship name and reattaches rebuilt/surviving members to the living or
   rebuilt commander with their saved subordinate group. X4 consumes normal yard
   resources. FOC sends no NPC-yard purchase and buys no blueprint.

   This workflow is explicit and manual. FOC does not interpret a destruction
   event as spending authority. A loss is rebuilt only after the player opens
   Repair / Replace / Rebuild, refreshes readback, previews, and confirms the
   rebuild request.

Captain auto-fill

The Academy captain auto-fill is a separate preview/approval transaction. The
preview revalidates up to 25 proven vacancies, retained Pilot trainees, Academy
capacity, eligible operational player stations, and a conservative complete
seminar inventory. Approval must follow a fresh preview. It recruits only the
missing Pilot trainees, trains every selected pilot to five stars with native
inventory readback after each lesson, then assigns each to one still-vacant ship
and requires native assigned-pilot readback. It reports requested, recruited,
assigned, and blocked counts; no existing captain or shipboard crew is taken.

Native evidence

- X4 `md/fleet_reconstitution.xml` owns `reconstitute_fleet`, rejects fleet-unit
  records that already have an object/build, finds compatible player-owned yards,
  tests exact macro and missing loadout equipment, queues the native rebuild, and
  rejoins the completed ship to its commander.
- X4's preserved `common.xsd` contract defines generic player-yard construction
  with explicit object, macro, loadout, faction, and returned build-task identity.
- X4's object-command contract defines assigning a ship to a commander with an
  explicit subordinate group, which is used only after native build completion.
- X4 `aiscripts/order.repair.xml` defines the native Repair order parameters.
- X4 `aiscripts/interrupt.restock.xml` provides the native compatible
  repair-facility filtering used by Build 026's non-mutating handoff.
- X4 `ui/addons/ego_detailmonitor/menu_ship_configuration.lua` owns repair price,
  resource, payment, confirmation, Repair-order, and `upgradefleetunit` flows.
- The permanent research record is
  `Evidence/FOC_B026_NATIVE_REPAIR_REPLACEMENT_REBUILD_RESEARCH_20260901.md` in
  the governed FOC repository and includes source hashes and official Egosoft
  blueprint / ship-upgrade documentation links.

Preserved safety boundaries

- Player ownership, stable identity, captain presence, Home resolution, locks,
  authority mode, incident age, mission/story protection, and native readback are
  checked at the mutation boundary.
- The exact completed Yaki reward-ship adapter and Geometric Owl protection remain
  unchanged. No name, ID, macro, ownership alone, or cached UI state releases a
  protected object.
- Fleet sampling is capped at 500 ships; 100 fleets and 100 direct members per
  fleet are displayed. Saved-plan application is capped at 100 Draft records;
  Academy bulk assignment remains capped at 25 exact pairs per approval.
- Live Activity remains save-persistent with 50 retained and 12 displayed rows.
  Session History now pages that same retained operational event archive.
- Repair handoff itself mutates nothing. Rebuild confirmation is a native async
  request and does not claim queued/building/completed state without refresh.
- No live installation, promotion, publication, or push is performed by this
  build workflow.

Static validation and regression review cannot establish behavior inside X4.
Every affected Build 039 behavior remains RUNTIME ACCEPTANCE REQUIRED until
RazorEQX tests the exact staged TEST artifact. That acceptance does not authorize
GA promotion, Steam publication, GitHub publication, push, or live installation.
