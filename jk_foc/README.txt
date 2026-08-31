Fleet Operations Command - Build 020 / version 119

Status: IMPLEMENTED; RUNTIME ACCEPTANCE REQUIRED.

Build 020 preserves the predecessor's governed recruitment, training, safety, and native
readback systems while replacing the multi-page patrol setup with one primary
Fleets-page action. Configure Home, patrol range, response classes, urgency, hull
thresholds, and return behavior, then press SEND THIS FLEET ON PATROL. That one
action saves and unlocks only the selected fleet, replaces only its eligible
orders, starts its native Patrol or Protect Position default, and arms bounded
distress response. FOC reports PATROL ACTIVE only after X4 confirms the intended
default order is also the fleet's current order.

Implemented systems

- Eight-tab Fleet Operations Command interface with bounded fleet/readiness
  sampling and a restrained EOC-derived color palette.
- The normal reaction-force list shows native `purpose.fight` commanders only.
  A separate scope control reveals non-combat fleets with a supply/logistics
  warning and a persistent per-fleet `OVERRIDE - DO THIS ANYWAY` decision.
  Trade ships remain covered by readiness and eligible captain staffing.
- Mission/quest commanders and every mission/quest subordinate are absolutely
  protected at the UI and native mutation boundary; no override bypasses them.
  The official Terran story's persistent Geometric Owl object is explicitly
  protected even after its active mission phase.
- Persistent per-fleet Drafts stored as MD native-object records.
- Exact map-selected Home sector and position, patrol/defence role, coverage,
  distress, damage, return, manual-order, and lock settings.
- The primary Fleets-page send action creates a native Patrol or ProtectPosition
  default for only the selected fleet without requiring Draft, lock, Settings, or
  Command steps. The older advanced controls remain optional.
- Apply Approved Plan remains available as an advanced global control and creates native Patrol or ProtectPosition default orders
  and reports applied, truly blocked, and deliberately locked-skipped fleets from
  default-order readback. A genuine mixed result is shown as PLAN_PARTIAL and
  never claims that nothing changed.
- The visible header derives Build 020 from the MD-supplied menu identity instead
  of a Lua literal. Activity pages render at most eight wrapped records with a
  conservative height budget proven against the Build 016 Widget-system failure.
- Save As Draft becomes inactive while that fleet key awaits persistent readback,
  and the dispatch function independently rejects a repeated pending request.
- Recall creates a native ProtectPosition return-to-post order and confirms its
  default-order identity.
- Captain evidence uses X4's native Lua `assignedpilot` to
  `tostring` to `ConvertStringToLuaID` route. Proven vacancies and unknown
  records have separate bounded lists and totals, so unknown evidence cannot
  hide a vacancy. The Academy destination collection is MD-authoritative and
  applies ownership, AI-pilot control-post, vacancy, player-control, mission,
  protected-id, and Geometric Owl guards before a ship is displayed.
- Training Academy holds at most 25 persistent trainee templates distributed
  across operational player-owned, non-mission stations. It creates no field-
  ship donor pool and never selects marines, service crew aboard ships,
  managers, existing captains, or mission/story personnel.
- Existing Academy records are migrated to schema 2 whenever state is opened or
  used. Missing or duplicate legacy ids are deterministically rebuilt without
  creating or deleting personnel, and the roster is serialized before the UI
  reports success.
- Academy training uses X4's exact seminar ladder, verifies the applicable
  piloting seminar in player inventory, consumes exactly one, applies the
  native skill increase, and requires inventory plus skill readback.
- `PROMOTE AND ASSIGN NEXT 25 CAPTAINS` is a player-triggered approval, not a
  scheduler. It builds a fresh valid local pool, sorts highest current piloting
  skill first, pairs at most 25 entries with current proven vacancies, and blocks
  the complete batch before mutation unless every required seminar tier is in
  inventory. Each training step and each ship assignment requires native readback.
- The bulk route never recruits automatically, never uses shipboard service crew
  or marines, never replaces an existing captain, never changes ship orders, and
  never processes more than 25 trainee/ship pairs per invocation.
- Academy assignment instantiates the selected persistent trainee at the
  selected FOC-proven vacancy, transfers that actor to `controlpost.aipilot`,
  requires exact `assignedpilot` readback, and retires only that Academy record.
- Academy and mission-protection refreshes replace the Lua cache only after a
  complete bounded scalar snapshot. Incomplete snapshots preserve the prior
  authoritative cache and visibly block refresh instead of clearing safety.
- Captain assignment uses two independent selectors: destination ship first,
  trainee crew second. The crew row shows current piloting rating and offers a
  one-session Train button. Preview names the exact pair before
  `TRANSFER SELECTED CREW TO SELECTED SHIP` can run.
- The destination selector retains the MD-supplied native ship component. Lua
  uses X4's documented component-to-64-bit conversion on arrival and 64-bit-to-
  LuaID conversion on return; MD revalidates that exact component and records
  each assignment guard in the debug log before any native mutation.
- Academy vacancy discovery sorts the complete local MD player-ship result with
  exact eligible components first, then examines at most 500 ranked ships. Its
  bounded guard-funnel log records total, examined, each cumulative predicate,
  and final rows so a legitimate zero-vacancy result is directly explainable.
  Build 016 splits guard diagnostics into records with at most nine substitutions,
  correcting Build 015's `%10`/`%11` rendering defect.
- Every Academy callback re-resolves current stable selections. Missing, stale,
  inactive, or changed selections block locally without sending a mutation.
- Distress intake records attacks on player ships, including victim, attacker,
  sector, age, and claimed state.
- Manual dispatch requires a fresh unclaimed incident and an eligible selected
  fleet, then creates a native immediate Attack order with the required
  `primarytarget` parameter.
- Full Automation uses the same incident evidence and fleet safeguards on a
  30-second MD scheduler, with at most one dispatch per scheduler cycle.
- Preview Plan, Apply Approved Plan, Full Automation, and emergency Stop are
  explicit persistent authority modes. Preview actions do not mutate.
- All native requests return visible state/result callbacks and are recorded in
  bounded Activity history and the X4 debug log.

Safety boundaries

- Player ownership, stable identity, captain presence, Home resolution, fleet
  lock, mode authority, fresh incident age, and native readback are checked at
  the mutation boundary.
- Locked fleets cannot be applied, recalled, or automatically dispatched.
- Fleet sampling and ranked Academy vacancy output are capped at 500 ships, with
  100 displayed fleets and 100 direct members per fleet. Saved-plan application
  is capped at 100 Draft records. Bulk Academy mutation is separately capped at
  25 exact trainee/ship pairs per explicit player approval.
- No purchase, construction, or credit/cargo movement is implemented.
- No live installation, promotion, publication, or push is performed by this
  build workflow.

The source and TEST package may pass static and regression review, but behavior
inside X4 remains RUNTIME ACCEPTANCE REQUIRED until RazorEQX tests this exact
Build 020 artifact. Passing that test does not itself authorize GA promotion,
Steam publication, GitHub publication, or push.
