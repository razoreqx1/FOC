local ffi = require("ffi")

ffi.cdef[[
typedef uint64_t UniverseID;
typedef struct { float x; float y; float z; float yaw; float pitch; float roll; } UIPosRot;
typedef struct { const char* ware; int total; int current; const char* supplytypes; } SupplyResourceInfo;
UniverseID GetPlayerOccupiedShipID(void);
bool IsComponentOperational(UniverseID componentid);
float GetTextHeight(const char*const text, const char*const fontname, const float fontsize, const float wordwrapwidth);
bool CanContainerEquipShip(UniverseID containerid, UniverseID shipid);
bool CanContainerSupplyShip(UniverseID containerid, UniverseID shipid);
const char* GetSubordinateGroupAssignment(UniverseID controllableid, int group);
void SetSubordinateGroupAssignment(UniverseID controllableid, int group, const char* assignment);
UniverseID GetSubordinateGroupProtectedSector(UniverseID controllableid, int group);
UIPosRot GetSubordinateGroupProtectedPosition(UniverseID controllableid, int group);
void SetSubordinateGroupProtectedLocation(UniverseID controllableid, int group, UniverseID sectorid, UIPosRot offset);
uint32_t GetNumSupplyOrderResources(UniverseID containerid);
uint32_t GetSupplyOrderResources(SupplyResourceInfo* result, uint32_t resultlen, UniverseID containerid);
int64_t GetSupplyBudget(UniverseID containerid);
void SetSubordinateGroupDockAtCommander(UniverseID controllableid, int group, bool value);
bool ShouldSubordinateGroupDockAtCommander(UniverseID controllableid, int group);
void SetSubordinateGroupReinforceFleet(UniverseID controllableid, int group, bool value);
bool ShouldSubordinateGroupReinforceFleet(UniverseID controllableid, int group);
void SetSubordinateGroupRespondToDistressCalls(UniverseID controllableid, int group, bool value);
bool ShouldSubordinateGroupRespondToDistressCalls(UniverseID controllableid, int group);
void SetSubordinateGroupResupplyAtFleet(UniverseID controllableid, int group, bool value);
bool ShouldSubordinateGroupResupplyAtFleet(UniverseID controllableid, int group);
]]

local C = ffi.C
local HISTORY_LIMIT = 64
local LIVE_ACTIVITY_LIMIT = 50
local LIVE_ACTIVITY_VISIBLE = 12
local ROW_POOL_LIMIT = 170
local ROW_POOL_RESERVE = 5
local FIRST_DRAW_LIMBO_ROWS = 1

local menu = {
    name = "FOC_Menu",
    page = "command",
    activeTab = "command",
    frame = nil,
    mainTable = nil,
    fleetTable = nil,
    sample = nil,
    history = {},
    liveActivity = {},
    liveActivityIncoming = nil,
    activityView = "live",
    gameTime = 0,
    operationsMap = { filter = "OVERVIEW", window = 60, selected = nil },
    mapPirateObservations = {},
    mapPatrolTraversals = {},
    mapGateEdges = {},
    strategicObservations = {},
    strategicAssets = {},
    strategicRecords = { carriers = {}, carrierwings = {}, grids = {}, convoys = {}, logistics = {}, assaults = {} },
    carrierDrafts = {},
    strategicIncoming = nil,
    strategic = {
        view = "TASK FORCES", assetChoice = 1, secondaryChoice = 1, group = 1,
        wingRole = "INTERCEPTOR", reserve = "NO", damageHull = 70,
        defenseRange = "ONE GATE", reserveThreshold = 7,
        minimumReadiness = 80, selectedRecord = 1,
        assaultMemberChoice = 1, assaultRole = "CAPITAL ASSAULT",
        rally = nil, target = nil, pendingMap = nil,
    },
    homeSectorByFleet = {},
    ordersByFleet = {},
    draftsByFleet = {},
    pendingDraftSaves = {},
    draftReadback = { key = nil, result = nil, state = nil },
    notice = nil,
    previews = { dispatch = nil, personnel = nil, global = nil, patrol = nil },
    academy = { rows = {}, vacancies = {}, marineTargets = {}, recruitTrack = "PILOT", selectedRecruitID = nil, selectedVacancyID = nil, selectedMarineTargetID = nil, previewRecruitTrack = nil, previewPair = nil, previewBulkFill = false },
    store = { balance = 0, pilot = { 0, 0, 0, 0, 0 }, marine = { 0, 0, 0, 0, 0 } },
    academyIncoming = nil,
    vacancyIncoming = nil,
    marineTargetIncoming = nil,
    protectedIncoming = nil,
    protectedShipIDs = {},
    protectedShipCount = 0,
    storyOverrideIncoming = nil,
    storyOverrideIDs = {},
    storyAnsweredIncoming = nil,
    storyAnsweredIDs = {},
    structuralFleetRows = {},
    structuralIncoming = nil,
    taskForces = {},
    templates = {},
    afterActionReports = {},
    roadmapIncoming = nil,
    operations = { retreat = "OFF", retreatHull = 30, retreatReturn = "YES", commanderHull = 50, fleetHull = 50, captainCoverage = 100, maxFleetSize = 100, preset = "MANUAL ORDERS ONLY" },
    taskForce = { selected = 1, fleetChoice = 1, memberChoice = 1, name = "TASK FORCE ALPHA", priority = "NORMAL", zone = "NORMAL", coverage = "HOME SECTOR ONLY", rotation = "MANUAL" },
    templateChoice = 1,
    pendingActionKind = nil,
    pendingHomeSelection = nil,
    homeReturnMetadata = nil,
    restoreFleetKey = nil,
    selectedFleet = 1,
    showNonCombat = false,
    showFleetAdvanced = false,
    fleetMode = "orders",
    maintenance = { pending = false, commanderID = nil, fleetName = nil, repairRows = {}, lostRows = {}, selectedRepair = 1, selectedLost = 1, previewCommanderID = nil, status = "NOT SCANNED" },
    safety = { reactionRepair = 100, playerRepair = 100, responseCap = 100, dirty = false },
    lastActivePatrolFleet = nil,
    renderedPage = nil,
    restoreTopRow = nil,
    closeInProgress = false,
    workflowPointersVisible = true,
    fleetFinder = "ALL FLEETS",
    listPages = {},
    listContentHeight = nil,
    phase = { readiness = "overview", fleets = "registry", response = "rules", settings = "automation" },
    plan = {
        authority = "PREVIEW PLAN", fleetRole = "PATROL", naming = "FOC | ROLE | HOME | 01",
        coverage = "HOME SECTOR ONLY", distress = "PLAYER OWNED ONLY",
        patrolPattern = "LOOP", distressUrgency = 5, shipDamage = 70, stationDamage = 70,
        respondShips = "YES", respondStations = "YES", returnHome = "YES", sectorChoice = "ALL SAFE SECTORS IN RANGE",
        manualOverride = true, locked = true, nonCombatOverride = false, status = "DRAFT", lastResult = "NO PLAN APPLIED", lastState = "NONE", routePreview = nil,
    },
}

local config = {
    layer = 5,
    widthRatio = 0.88,
    heightRatio = 0.86,
    minWidth = 900,
    minHeight = 560,
    maxWidth = 2100,
    maxHeight = 1300,
}

local frameBackground = { r = 0, g = 0, b = 0, a = 96 }
local activeTabBackground = { r = 24, g = 115, b = 145, a = 100 }
local headingColor = { r = 110, g = 205, b = 235, a = 100 }
local passColor = { r = 100, g = 220, b = 130, a = 100 }
local warningColor = { r = 255, g = 190, b = 72, a = 100 }
local criticalColor = { r = 255, g = 92, b = 92, a = 100 }
local neutralColor = { r = 185, g = 195, b = 205, a = 100 }
-- EOC-proven restrained backgrounds: readable without the neon full-bright fill.
local normalActionBackground = { r = 0, g = 116, b = 153, a = 100 }
local availableActionBackground = { r = 49, g = 69, b = 83, a = 60 }
local confirmedActionBackground = { r = 20, g = 92, b = 48, a = 100 }
local requiredActionBackground = { r = 125, g = 82, b = 12, a = 100 }
local failedActionBackground = { r = 105, g = 32, b = 32, a = 100 }
local pointerActionBackground = { r = 92, g = 48, b = 145, a = 100 }
local rebuild
local buildOperationsIntel
local bridgeComponent64

local tabs = {
    { id = "command", label = "HOME" },
    { id = "shipyard", label = "SHIPYARD" },
    { id = "fleets", label = "FLEETS" },
    { id = "taskforces", label = "STRATEGIC OPS" },
    { id = "readiness", label = "READINESS" },
    { id = "academy", label = "TRAINING ACADEMY" },
    { id = "store", label = "ACADEMY STORE" },
    { id = "response", label = "FLEET RESPONSE" },
    { id = "activity", label = "ACTIVITY" },
    { id = "operationsmap", label = "OPERATIONS MAP" },
    { id = "settings", label = "SETTINGS" },
}

local guides = {
    command = "Preview, approve, or stop bounded FOC planning. Unknown evidence always blocks mutation.",
    fleets = "Choose one fleet, configure its proven orders and response rules, or open Repair / Replace / Rebuild for native maintenance.",
    taskforces = "Manage Task Forces, carrier wings, defense grids, convoy escorts, mobile logistics, and coordinated assaults through native X4 assignments and exact readback.",
    readiness = "Missing and unknown evidence are blockers. No unknown value is counted as ready.",
    academy = "Recruit up to 100 combined Pilot and Marine trainees, train them, then assign them to proven destinations.",
    store = "Buy Pilot Lessons or Marine Credits with credits. Every purchase is verified before FOC reports success.",
    response = "Configure FOC Fleet Response scope, safeguards, dispatch limits, and return behavior.",
    activity = "Watch proven FOC actions as they happen, or review this session's bounded history.",
    operationsmap = "Open the dedicated discovered-space Operations Map with native navigation and bounded FOC sector intelligence.",
    settings = "Configure global planning mode and review hard scan, mutation, cooldown, and audit bounds.",
}

local automationModes = { "PREVIEW PLAN", "APPLY APPROVED PLAN", "FULL AUTOMATION" }
local fleetRoles = { "PATROL", "GUARD HOME" }
local coverageRanges = { "OFF", "HOME SECTOR ONLY", "ONE GATE", "TWO GATES", "THREE GATES", "FOUR GATES", "FIVE GATES" }
local yesNoOptions = { "YES", "NO" }
local urgencyOptions = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
local damageOptions = { 100, 90, 80, 70, 60, 50, 40, 30, 20, 10 }
local repairThresholdOptions = { 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 }
local responseFleetCapOptions = { 1, 5, 10, 20, 50, 100 }
local taskForceNames = { "TASK FORCE ALPHA", "TASK FORCE BRAVO", "TASK FORCE CHARLIE", "TASK FORCE DELTA", "TASK FORCE ECHO", "TASK FORCE FOXTROT", "TASK FORCE GUARDIAN", "TASK FORCE SENTINEL" }
local taskForcePriorities = { "HIGH", "NORMAL", "EXCLUDED" }
local rotationModes = { "MANUAL", "FULL AUTOMATION" }
local automationPresets = { "PROTECT HOME", "GUARD TRADERS", "DEFEND STATIONS", "HUNT PIRATES", "STAY SAFE", "MANUAL ORDERS ONLY" }
local fleetFinderOptions = { "ALL FLEETS", "A-F", "G-L", "M-R", "S-Z" }
local operationsMapFilters = { "OVERVIEW", "PIRATE ACTIVITY", "HEAVY PATROL ROUTES", "FLEET HOMES" }
local operationsMapWindows = { 15, 60, 180 }
menu.strategicViews = { "COVERAGE AND FLEET TEMPLATES", "TASK FORCES", "CARRIER AIR WINGS", "SECTOR DEFENSE GRID", "CONVOY ESCORT", "MOBILE LOGISTICS", "COORDINATED ASSAULT" }
local wingRoles = { "INTERCEPTOR", "BOMBER", "ESCORT", "RESERVE" }
local wingAssignments = { INTERCEPTOR = "interception", BOMBER = "bombardment", ESCORT = "defence", RESERVE = "defence" }

local function normalizeFleetRole(value)
    local text = tostring(value or "")
    return (text == "PATROL GROUP" or text == "PATROL") and "PATROL" or "GUARD HOME"
end

local function normalizeCoverage(value)
    local text = tostring(value or "")
    for _, option in ipairs(coverageRanges) do if text == option then return text end end
    return "OFF"
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function safeText(value, fallback)
    if value == nil or tostring(value) == "" then return fallback or "UNKNOWN" end
    return tostring(value)
end

local function formatGameTime(value)
    local seconds = math.max(0, math.floor(tonumber(value) or 0))
    local day = math.floor(seconds / 86400) + 1
    local remainder = seconds % 86400
    local hours = math.floor(remainder / 3600)
    local minutes = math.floor((remainder % 3600) / 60)
    local displaySeconds = remainder % 60
    return string.format("SAVE DAY %d, %02d:%02d:%02d", day, hours, minutes, displaySeconds)
end

local function activitySeverity(kind, detail, supplied)
    if supplied == "RED_DAMAGE" or supplied == "YELLOW_DISTRESS" or supplied == "NORMAL" then return supplied end
    local activityKind = tostring(kind or "")
    local activityDetail = tostring(detail or "")
    if activityKind == "SHIP_DESTROYED" or activityKind == "FLEET_REBUILD" then return "RED_DAMAGE" end
    if activityKind == "DISTRESS" then
        local hull = tonumber(activityDetail:match("|%s*SHIP%s*|%s*hull%s+(%d+)%s+percent"))
        return hull and hull < 100 and "RED_DAMAGE" or "YELLOW_DISTRESS"
    end
    return "NORMAL"
end

local function loadLiveActivityRows(rows)
    local restored = {}
    if type(rows) == "table" then
        for _, row in ipairs(rows) do
            if type(row) == "table" and (tonumber(row[1]) == 1 or tonumber(row[1]) == 2) and tonumber(row[2]) then
                restored[#restored + 1] = {
                    id = tonumber(row[2]), time = tonumber(row[3]) or 0,
                    kind = safeText(row[4], "ACTIVITY"), state = safeText(row[5], "RECORDED"),
                    subject = safeText(row[6], "FOC"), detail = safeText(row[7], "No detail recorded."),
                    severity = activitySeverity(row[4], row[7], row[8]),
                    target = row[9], targetid = tostring(row[10] or ""), sector = row[11],
                }
            end
        end
    end
    table.sort(restored, function(a, b) return a.id > b.id end)
    while #restored > LIVE_ACTIVITY_LIMIT do table.remove(restored) end
    menu.liveActivity = restored
    return #restored
end

local function loadMapPirateObservations(rows)
    local restored = {}
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        local sector64 = type(row) == "table" and tonumber(row[1]) == 1 and bridgeComponent64(row[3]) or nil
        if sector64 and tonumber(row[2]) then
            restored[#restored + 1] = {
                time = tonumber(row[2]), sector = tostring(sector64),
                sectorName = safeText(row[4], "UNKNOWN SECTOR"),
                faction = safeText(row[5], "UNKNOWN PIRATE FACTION"),
                attacker = safeText(row[6], "UNKNOWN ATTACKER"),
                severity = activitySeverity("PIRATE_ACTIVITY", "", row[7]),
            }
        end
        if #restored >= 200 then break end
    end
    menu.mapPirateObservations = restored
end

local function loadMapPatrolTraversals(rows)
    local restored = {}
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        local from64 = type(row) == "table" and tonumber(row[1]) == 1 and bridgeComponent64(row[5]) or nil
        local to64 = type(row) == "table" and bridgeComponent64(row[7]) or nil
        if from64 and to64 and tostring(from64) ~= tostring(to64) and tonumber(row[2]) then
            restored[#restored + 1] = {
                time = tonumber(row[2]), commanderID = safeText(row[3], "UNKNOWN"),
                commander = safeText(row[4], "UNKNOWN FLEET"),
                from = tostring(from64), fromName = safeText(row[6], "UNKNOWN SECTOR"),
                to = tostring(to64), toName = safeText(row[8], "UNKNOWN SECTOR"),
            }
        end
        if #restored >= 250 then break end
    end
    menu.mapPatrolTraversals = restored
end

local function loadMapGateEdges(rows)
    local restored, seen = {}, {}
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        local from64 = type(row) == "table" and bridgeComponent64(row[1]) or nil
        local to64 = type(row) == "table" and bridgeComponent64(row[3]) or nil
        if from64 and to64 and tostring(from64) ~= tostring(to64) then
            local a, b = tostring(from64), tostring(to64)
            local key = a < b and (a .. ":" .. b) or (b .. ":" .. a)
            if not seen[key] then
                seen[key] = true
                restored[#restored + 1] = { from = a, fromName = safeText(row[2], "UNKNOWN SECTOR"), to = b, toName = safeText(row[4], "UNKNOWN SECTOR") }
            end
        end
        if #restored >= 500 then break end
    end
    menu.mapGateEdges = restored
end

local function loadAcademyRows(rows)
    local restored = {}
    if type(rows) == "table" then
        for _, row in ipairs(rows) do
            if type(row) == "table" and tonumber(row[1]) == 1 then
                restored[#restored + 1] = {
                    id = tonumber(row[2]),
                    name = safeText(row[3], "Unnamed trainee"),
                    origin = safeText(row[4], "UNKNOWN STATION"),
                    originID = safeText(row[5], "UNKNOWN"),
                    piloting = tonumber(row[6]),
                    morale = tonumber(row[7]),
                    seminar = safeText(row[8], "MAXIMUM PILOTING RANK"),
                    seminarCount = tonumber(row[9]) or 0,
                    valid = row[10] == true or row[10] == 1,
                    track = safeText(row[11], "PILOT"),
                    boarding = tonumber(row[12]),
                }
            end
        end
    end
    table.sort(restored, function(a, b) return (a.id or 0) < (b.id or 0) end)
    menu.academy.rows = restored
    local selectedStillExists = false
    for _, recruit in ipairs(restored) do
        if tostring(recruit.id) == tostring(menu.academy.selectedRecruitID or "") then selectedStillExists = true; break end
    end
    if not selectedStillExists then menu.academy.selectedRecruitID = restored[1] and tostring(restored[1].id) or nil end
    return #restored
end

local function loadStoreData(data)
    if type(data) ~= "table" then return end
    menu.store.balance = tonumber(data[1]) or menu.store.balance or 0
    for tier = 1, 5 do
        menu.store.pilot[tier] = tonumber(type(data[2]) == "table" and data[2][tier]) or 0
        menu.store.marine[tier] = tonumber(type(data[3]) == "table" and data[3][tier]) or 0
    end
end

local function loadProtectedShipIDs(rows)
    local restored = {}
    if type(rows) == "table" then
        for _, idcode in ipairs(rows) do
            local key = tostring(idcode or "")
            if key ~= "" and key ~= "UNKNOWN" then restored[key] = true end
        end
    end
    menu.protectedShipIDs = restored
    local count = 0
    for _ in pairs(restored) do count = count + 1 end
    menu.protectedShipCount = count
end

local function isProtectedShipID(idcode)
    return menu.protectedShipIDs[tostring(idcode or "")] == true
end

local function loadStoryOverrideIDs(rows)
    local restored = {}
    if type(rows) == "table" then
        for _, idcode in ipairs(rows) do
            local key = tostring(idcode or "")
            if key ~= "" and key ~= "UNKNOWN" then restored[key] = true end
        end
    end
    menu.storyOverrideIDs = restored
end

local function isStoryOverrideID(idcode)
    return menu.storyOverrideIDs[tostring(idcode or "")] == true
end

local function loadStoryAnsweredIDs(rows)
    local restored = {}
    if type(rows) == "table" then
        for _, idcode in ipairs(rows) do
            local key = tostring(idcode or "")
            if key ~= "" and key ~= "UNKNOWN" then restored[key] = true end
        end
    end
    menu.storyAnsweredIDs = restored
end

local function isStoryAnsweredID(idcode)
    return menu.storyAnsweredIDs[tostring(idcode or "")] == true
end

local function selectedAcademyRecruit(track)
    local selectedID = tostring(menu.academy.selectedRecruitID or "")
    for _, recruit in ipairs(menu.academy.rows) do
        if tostring(recruit.id) == selectedID then return recruit end
    end
    return nil
end

local function academyRowsForTrack(track)
    local rows = {}
    for _, recruit in ipairs(menu.academy.rows) do
        rows[#rows + 1] = recruit
    end
    return rows
end

local function selectedAcademyVacancy(vacancies)
    local selectedID = tostring(menu.academy.selectedVacancyID or "")
    for _, vacancy in ipairs(vacancies or {}) do
        if tostring(vacancy.key or "") == selectedID then return vacancy end
    end
    return nil
end

local function selectedMarineTarget(targets)
    local selectedID = tostring(menu.academy.selectedMarineTargetID or "")
    for _, target in ipairs(targets or {}) do
        if tostring(target.key or "") == selectedID then return target end
    end
    return nil
end

local function needsAction(value)
    local text = string.upper(tostring(value or ""))
    -- A zero blocker count is not a blocked result. Match the complete successful
    -- preview shape, including captain evidence, rather than a broad substring.
    if text:match("^PLAN PREVIEW COMPLETE %- %d+ REACTION FLEETS IN SCOPE | %d+ READY | 0 BLOCKED OR NEED ATTENTION | 0 CAPTAIN RECORDS MISSING OR UNKNOWN | NO ORDERS SENT$") then return false end
    return text:find("BLOCKED", 1, true) ~= nil or text:find("ACTION REQUIRED", 1, true) ~= nil or
        text:find("NOT SENT", 1, true) ~= nil or text:find("NOT APPLIED", 1, true) ~= nil or
        text:find("NOT SAVED", 1, true) ~= nil or text:find("NEEDS ATTENTION", 1, true) ~= nil or
        text:find("PROCESSING", 1, true) ~= nil or text:find("PENDING", 1, true) ~= nil or
        text:find("WAITING", 1, true) ~= nil
end

local function toComponent64(value)
    if value == nil or value == 0 then return nil end
    local raw = tostring(value)
    if raw == "" or raw:match("^0+[uUlL]*$") or raw:match("^0[xX]0+[uUlL]*$") then return nil end
    local converted = nil
    if raw:match("^%d+[uUlL]*$") then
        local ok
        ok, converted = pcall(ConvertStringTo64Bit, raw)
        if not ok then converted = nil end
    elseif raw:match("^0[xX]%x+$") then
        local ok
        ok, converted = pcall(ConvertIDTo64Bit, raw)
        if not ok then converted = nil end
    else
        return nil
    end
    if converted == nil or converted == 0 then return nil end
    local valid, result = pcall(IsValidComponent, converted)
    if valid and result then return converted end
    return nil
end

bridgeComponent64 = function(value)
    if value == nil or value == 0 then return nil end
    local raw = tostring(value)
    if raw == "" or raw:match("^0+[uUlL]*$") or raw:match("^0[xX]0+[uUlL]*$") then return nil end
    local ok, converted = pcall(ConvertStringTo64Bit, raw)
    if not ok or converted == nil or converted == 0 then return nil end
    local valid, result = pcall(IsValidComponent, converted)
    if valid and result then return converted end
    return nil
end

local function componentLuaID(value)
    if value == nil or value == 0 then return nil end
    local valid, exists = pcall(IsValidComponent, value)
    if not valid or not exists then return nil end
    local ok, luaID = pcall(ConvertStringToLuaID, tostring(value))
    if not ok or luaID == nil or luaID == 0 or tostring(luaID) == "" then return nil end
    return luaID
end

local function loadVacancyRows(rows)
    local restored = {}
    if type(rows) == "table" then
        for _, row in ipairs(rows) do
            if type(row) == "table" and tonumber(row[1]) == 1 then
                local component64 = bridgeComponent64(row[2])
                if component64 then
                    restored[#restored + 1] = {
                        component = component64,
                        key = tostring(component64),
                        name = safeText(row[3], "Unnamed ship"),
                        idcode = safeText(row[4], "UNKNOWN"),
                        sector = safeText(row[5], "UNKNOWN SECTOR"),
                    }
                end
            end
        end
    end
    table.sort(restored, function(a, b)
        if a.name == b.name then return a.key < b.key end
        return a.name < b.name
    end)
    menu.academy.vacancies = restored
    local selectedStillExists = false
    for _, vacancy in ipairs(restored) do
        if vacancy.key == tostring(menu.academy.selectedVacancyID or "") then selectedStillExists = true; break end
    end
    if not selectedStillExists then menu.academy.selectedVacancyID = restored[1] and restored[1].key or nil end
    return #restored
end

local function loadMarineTargetRows(rows)
    local restored = {}
    if type(rows) == "table" then
        for _, row in ipairs(rows) do
            if type(row) == "table" and tonumber(row[1]) == 1 then
                local component64 = bridgeComponent64(row[2])
                if component64 then
                    restored[#restored + 1] = {
                        component = component64,
                        key = tostring(component64),
                        name = safeText(row[3], "Unnamed ship"),
                        idcode = safeText(row[4], "UNKNOWN"),
                        sector = safeText(row[5], "UNKNOWN SECTOR"),
                        relationship = safeText(row[6], "UNCLASSIFIED"),
                        people = tonumber(row[7]) or 0,
                        capacity = tonumber(row[8]) or 0,
                        marines = tonumber(row[9]) or 0,
                    }
                end
            end
        end
    end
    table.sort(restored, function(a, b)
        if a.relationship == b.relationship then
            if a.name == b.name then return a.key < b.key end
            return a.name < b.name
        end
        return a.relationship < b.relationship
    end)
    menu.academy.marineTargets = restored
    local selectedStillExists = false
    for _, target in ipairs(restored) do
        if target.key == tostring(menu.academy.selectedMarineTargetID or "") then selectedStillExists = true; break end
    end
    if not selectedStillExists then menu.academy.selectedMarineTargetID = restored[1] and restored[1].key or nil end
    return #restored
end

local function componentName(component, fallback)
    local component64 = toComponent64(component)
    if not component64 then return fallback or "UNKNOWN" end
    local ok, name = pcall(GetComponentData, component64, "name")
    if ok and name and name ~= "" then return tostring(name) end
    return fallback or "UNKNOWN"
end

local function componentIDCode(component)
    local component64 = toComponent64(component)
    if not component64 then return "UNKNOWN" end
    local ok, value = pcall(GetComponentData, component64, "idcode")
    if ok and value and value ~= "" then return tostring(value) end
    return "UNKNOWN"
end

local function fleetKey(selected)
    if not selected or not selected.commander then return nil end
    local idcode = tostring(selected.commander.idcode or "")
    if idcode == "" or idcode == "UNKNOWN" then return nil end
    return "COMMANDER_IDCODE:" .. string.upper(idcode)
end

local function fleetAuditSubject(selected, key)
    if not selected or not selected.commander then return key or "UNKNOWN FLEET" end
    return safeText(selected.commander.fleetname, "Unnamed fleet") .. " [" .. safeText(selected.commander.idcode, "UNKNOWN") .. "] key=" .. safeText(key, "UNKNOWN")
end

local function stableSectorKey(component, name)
    local component64 = toComponent64(component)
    if component64 then
        local ok, macro = pcall(GetComponentData, component64, "macro")
        if ok and macro and tostring(macro) ~= "" then return "SECTOR_MACRO:" .. tostring(macro) end
    end
    local sectorName = tostring(name or "")
    if sectorName ~= "" and sectorName ~= "UNKNOWN SECTOR" then return "SECTOR_NAME:" .. string.upper(sectorName) end
    return nil
end

local function newFleetOrders()
    return {
        fleetRole = "PATROL", coverage = "HOME SECTOR ONLY", sectorChoice = "PLAYER OWNED ONLY",
        patrolPattern = "LOOP", respondShips = "YES", respondStations = "YES", distress = "PLAYER OWNED ONLY",
        distressUrgency = 5, shipDamage = 70, stationDamage = 70, returnHome = "YES",
        manualOverride = true, locked = true, nonCombatOverride = false, routePreview = nil,
    }
end

local function ordersForFleet(selected)
    local key = type(selected) == "string" and selected or fleetKey(selected)
    if not key then return nil end
    if not menu.ordersByFleet[key] then menu.ordersByFleet[key] = newFleetOrders() end
    return menu.ordersByFleet[key]
end

local function markFleetOrdersChanged(key, orders)
    if not key or not orders then return end
    orders.routePreview = nil
    menu.draftsByFleet[key] = nil
    menu.plan.lastResult = "SETTINGS CHANGED - PRESS SAVE AS DRAFT - NO ORDERS SENT"
    menu.notice = menu.plan.lastResult
end

local function homeSectorForFleet(selected)
    local key = fleetKey(selected)
    if not key then return nil end
    return menu.homeSectorByFleet[key]
end

local function homePointText(home)
    if not home or type(home.position) ~= "table" then return "NOT CHOSEN" end
    local x = (tonumber(home.position[1]) or 0) / 1000
    local y = (tonumber(home.position[2]) or 0) / 1000
    local z = (tonumber(home.position[3]) or 0) / 1000
    return string.format("X %.0f km  |  Y %.0f km  |  Z %.0f km", x, y, z)
end

local function draftSnapshot(orders, home, savedAt)
    return {
        fleetRole = orders.fleetRole, coverage = orders.coverage, sectorChoice = orders.sectorChoice,
        patrolPattern = orders.patrolPattern, respondShips = orders.respondShips,
        respondStations = orders.respondStations, distress = orders.distress,
        distressUrgency = orders.distressUrgency, shipDamage = orders.shipDamage,
        stationDamage = orders.stationDamage, returnHome = orders.returnHome,
        manualOverride = orders.manualOverride, locked = orders.locked, nonCombatOverride = orders.nonCombatOverride,
        homeSectorID = home.id, homeSectorName = home.text,
        homePosition = { home.position[1], home.position[2], home.position[3] }, savedAt = savedAt or 0,
    }
end

local function restorePersistentDrafts(rows)
    if type(rows) ~= "table" then return 0 end
    local restored = 0
    for _, row in ipairs(rows) do
        if type(row) == "table" and (tonumber(row[1]) == 3 or tonumber(row[1]) == 4) and safeText(row[2], "") ~= "" then
            local key = "COMMANDER_IDCODE:" .. string.upper(tostring(row[2]))
            local orders = newFleetOrders()
            orders.fleetRole = normalizeFleetRole(row[9])
            orders.coverage = normalizeCoverage(row[10])
            orders.sectorChoice = safeText(row[11], orders.sectorChoice)
            orders.patrolPattern = safeText(row[12], orders.patrolPattern)
            orders.respondShips = safeText(row[13], orders.respondShips)
            orders.respondStations = safeText(row[14], orders.respondStations)
            orders.distress = safeText(row[15], orders.distress)
            orders.distressUrgency = tonumber(row[16]) or 5
            orders.shipDamage = tonumber(row[17]) or 70
            orders.stationDamage = tonumber(row[18]) or 70
            orders.returnHome = safeText(row[19], orders.returnHome)
            orders.manualOverride = row[20] == true or row[20] == 1 or row[20] == "1"
            orders.locked = row[21] == true or row[21] == 1 or row[21] == "1"
            orders.shipyardReady = row[24] == true or row[24] == 1 or row[24] == '1'
            orders.nonCombatOverride = tonumber(row[1]) == 4 and (row[22] == true or row[22] == 1 or row[22] == "1")
            local home = {
                id = safeText(row[4], "UNKNOWN"), text = safeText(row[5], "UNKNOWN SECTOR"),
                position = { tonumber(row[6]) or 0, tonumber(row[7]) or 0, tonumber(row[8]) or 0 },
            }
            menu.ordersByFleet[key] = orders
            menu.homeSectorByFleet[key] = home
            menu.draftsByFleet[key] = draftSnapshot(orders, home, tonumber(row[tonumber(row[1]) == 4 and 23 or 22]) or 0)
            restored = restored + 1
        end
    end
    return restored
end

-- One scalar, exact commander identity from completed MD assembly. Presentation only:
-- preserve dirty editors and never redraw a closed/successor menu from this event.
function menu.shipyardReady(_, id)
    if type(id)~='string' or id=='' or id=='UNKNOWN' or #id>128 then return end
    local key='COMMANDER_IDCODE:'..string.upper(id)
    local orders=menu.ordersByFleet[key] or newFleetOrders()
    orders.shipyardReady=true
    menu.ordersByFleet[key]=orders
end

function menu.operationsMapLocationSelected(childMenu, request, value)
    local pending = type(request) == "table" and request or menu.pendingHomeSelection
    local sector64 = type(value) == "table" and toComponent64(value[1]) or nil
    local position = type(value) == "table" and value[2] or nil
    if pending and pending.kind == "HOME" and pending.fleetKey and sector64 and type(position) == "table" then
        menu.restoreFleetKey = pending.fleetKey
        local sectorName = componentName(sector64, "UNKNOWN SECTOR")
        local sectorKey = stableSectorKey(sector64, sectorName)
        if not sectorKey then
            menu.pendingHomeSelection = nil
            menu.plan.lastResult = "HOME POINT NOT CHANGED - SECTOR IDENTITY IS UNKNOWN"
            DebugError("[FOC][B050][HOME_MAP_INVALID] reason=STABLE_SECTOR_IDENTITY_UNKNOWN mutation=NONE")
        else
            menu.homeSectorByFleet[pending.fleetKey] = {
                id = sectorKey,
                text = sectorName,
                position = { tonumber(position[1]) or 0, tonumber(position[2]) or 0, tonumber(position[3]) or 0 },
            }
            markFleetOrdersChanged(pending.fleetKey, ordersForFleet(pending.fleetKey))
            menu.plan.lastResult = "HOME POINT CHOSEN - DRAFT NOT YET SAVED - NO ORDERS SENT"
            DebugError(string.format("[FOC][B050][HOME_MAP_SELECTED] fleet=%s sector=%s sector_key=%s position=%.3f,%.3f,%.3f mutation=DRAFT_ONLY orders=NONE", pending.fleetAudit, sectorName, sectorKey, menu.homeSectorByFleet[pending.fleetKey].position[1], menu.homeSectorByFleet[pending.fleetKey].position[2], menu.homeSectorByFleet[pending.fleetKey].position[3]))
        end
    elseif pending and pending.kind == "ASSAULT_RALLY" and sector64 and type(position) == "table" then
        local sectorName = componentName(sector64, "UNKNOWN SECTOR")
        local sectorKey = stableSectorKey(sector64, sectorName)
        if sectorKey then
            menu.strategic.rally = { id = sectorKey, name = sectorName, position = { tonumber(position[1]) or 0, tonumber(position[2]) or 0, tonumber(position[3]) or 0 } }
            menu.plan.lastResult = "ASSAULT RALLY POINT MARKED IN DRAFT - NO ORDER SENT"
        else
            menu.plan.lastResult = "RALLY POINT NOT CHANGED - STABLE SECTOR IDENTITY UNKNOWN"
        end
    else
        menu.plan.lastResult = "HOME POINT NOT CHANGED - MAP RETURN WAS INVALID - NO ORDERS SENT"
        DebugError("[FOC][B050][HOME_MAP_INVALID] mutation=NONE")
    end
    menu.pendingHomeSelection = nil
    menu.homeReturnMetadata = nil
    if childMenu and childMenu.name == "FOC_OperationsMap" then
        Helper.closeMenuAndOpenNewMenu(childMenu, menu.name, { 0, 0, 171, "FOC Build 072", "RUNTIME ACCEPTANCE REQUIRED", menu.plan.authority, menu.plan.lastResult, nil, nil, menu.restoreFleetKey })
        if childMenu.cleanup then childMenu.cleanup() end
    end
end

function menu.operationsMapTargetSelected(childMenu, request, value)
    if type(request) == "table" and request.kind == "ASSAULT_TARGET" and type(value) == "table" and value[1] and value[2] then
        menu.strategic.target = { id = tostring(value[1]), name = tostring(value[2]) }
        menu.plan.lastResult = "ASSAULT TARGET MARKED IN DRAFT - NO ORDER SENT"
    else
        menu.plan.lastResult = "ASSAULT TARGET NOT CHANGED - EXACT ATTACKABLE COMPONENT WAS NOT PROVEN"
    end
    menu.pendingHomeSelection = nil
    if childMenu and childMenu.name == "FOC_OperationsMap" then
        Helper.closeMenuAndOpenNewMenu(childMenu, menu.name, { 0, 0, 171, "FOC Build 072", "RUNTIME ACCEPTANCE REQUIRED", menu.plan.authority, menu.plan.lastResult })
        if childMenu.cleanup then childMenu.cleanup() end
    end
end

function menu.openStrategicMap(kind)
    if menu.frame == nil then return end
    menu.pendingHomeSelection = { kind = kind, token = tostring(getElapsedTime()) }
    menu.plan.lastResult = kind == "ASSAULT_TARGET" and "FOC MAP OPEN - CLICK AN EXACT ATTACKABLE TARGET; ESCAPE CANCELS" or "FOC MAP OPEN - CLICK THE EXACT RALLY POINT; ESCAPE CANCELS"
    local intel, unlocated = buildOperationsIntel()
    Helper.closeMenuAndOpenNewMenu(menu, "FOC_OperationsMap", { 0, 0, intel, unlocated, menu.operationsMap.window, menu.pendingHomeSelection, menu.mapPirateObservations, menu.mapPatrolTraversals, menu.mapGateEdges, menu.gameTime, menu.strategicObservations })
    menu.frame = nil
    menu.mainTable = nil
end

local function chooseHomeOnMap(selected)
    local key = fleetKey(selected)
    if not key then
        menu.plan.lastResult = "HOME POINT NOT CHANGED - FLEET IDENTITY IS UNKNOWN"
        rebuild(false)
        return
    end
    menu.pendingHomeSelection = { kind = "HOME", fleetKey = key, fleetAudit = fleetAuditSubject(selected, key) }
    menu.plan.lastResult = "FOC MAP OPEN - CLICK THE EXACT HOME POINT; DRAG STILL PANS; ESCAPE CANCELS"
    menu.homeReturnMetadata = {
        menu.param and menu.param[3] or nil,
        menu.param and menu.param[4] or nil,
        menu.param and menu.param[5] or nil,
    }
    local intel, unlocated = buildOperationsIntel()
    Helper.closeMenuAndOpenNewMenu(menu, "FOC_OperationsMap", { 0, 0, intel, unlocated, menu.operationsMap.window, menu.pendingHomeSelection, menu.mapPirateObservations, menu.mapPatrolTraversals, menu.mapGateEdges, menu.gameTime, menu.strategicObservations })
    menu.frame = nil
    menu.mainTable = nil
end

local function percent(value)
    local number = tonumber(value)
    if not number then return "UNKNOWN" end
    return string.format("%.0f%%", number)
end

local function statusColor(status)
    if status == "READY" then return passColor end
    if status == "CRITICAL" then return criticalColor end
    if status == "DEGRADED" or status == "UNKNOWN" then return warningColor end
    return neutralColor
end

local function directSubordinates(ship)
    local ok, result = pcall(GetSubordinates, ship, nil, true)
    if not ok or type(result) ~= "table" then return {} end
    local converted = {}
    for _, subordinate in ipairs(result) do
        local convertOK, subordinate64 = pcall(ConvertIDTo64Bit, subordinate)
        if convertOK and subordinate64 and subordinate64 ~= 0 then
            local validOK, valid = pcall(IsValidComponent, subordinate64)
            if validOK and valid then converted[#converted + 1] = subordinate64 end
        end
    end
    return converted
end

local groupPolicyContracts = {
    dock = { label = "Dock with commander", set = C.SetSubordinateGroupDockAtCommander, get = C.ShouldSubordinateGroupDockAtCommander },
    reinforce = { label = "Replace losses using X4 fleet reinforcement", set = C.SetSubordinateGroupReinforceFleet, get = C.ShouldSubordinateGroupReinforceFleet },
    distress = { label = "Respond to X4 distress calls", set = C.SetSubordinateGroupRespondToDistressCalls, get = C.ShouldSubordinateGroupRespondToDistressCalls },
    resupply = { label = "Resupply at fleet", set = C.SetSubordinateGroupResupplyAtFleet, get = C.ShouldSubordinateGroupResupplyAtFleet },
}

local function fleetSubordinateGroups(selected)
    local groups, seen = {}, {}
    local commander = selected and selected.commander and bridgeComponent64(selected.commander.object)
    if not commander then return commander, groups end
    for _, subordinate in ipairs(directSubordinates(commander)) do
        local ok, group = pcall(GetComponentData, subordinate, "subordinategroup")
        group = ok and tonumber(group) or nil
        if group and group >= 1 and group <= 10 and not seen[group] then
            seen[group] = true
            groups[#groups + 1] = group
        end
    end
    table.sort(groups)
    return commander, groups
end

local function fleetGroupPolicyState(selected, policy)
    local contract = groupPolicyContracts[policy]
    local commander, groups = fleetSubordinateGroups(selected)
    if not contract or not commander or #groups == 0 then return "UNAVAILABLE", 0, 0 end
    local enabled = 0
    for _, group in ipairs(groups) do
        local ok, value = pcall(contract.get, commander, group)
        if not ok then return "UNKNOWN", enabled, #groups end
        if value == true then enabled = enabled + 1 end
    end
    if enabled == #groups then return "YES", enabled, #groups end
    if enabled == 0 then return "NO", enabled, #groups end
    return "MIXED", enabled, #groups
end

local function setFleetGroupPolicy(selected, policy, enabled)
    local contract = groupPolicyContracts[policy]
    local commander, groups = fleetSubordinateGroups(selected)
    if not contract or not commander or #groups == 0 or selected.missionProtected or selected.commander.playerOccupied then
        return false, "BLOCKED - NO SAFE CURRENT SUBORDINATE GROUPS WERE PROVEN"
    end
    local original = {}
    for _, group in ipairs(groups) do
        local ok, value = pcall(contract.get, commander, group)
        if not ok or type(value) ~= "boolean" then
            return false, "BLOCKED - NATIVE PRE-CHANGE STATE COULD NOT BE PROVEN"
        end
        original[group] = value
    end
    local function rollback()
        local restored = true
        for _, group in ipairs(groups) do
            local setOK = pcall(contract.set, commander, group, original[group])
            local getOK, value = pcall(contract.get, commander, group)
            if not setOK or not getOK or value ~= original[group] then restored = false end
        end
        return restored
    end
    for _, group in ipairs(groups) do
        local ok = pcall(contract.set, commander, group, enabled == true)
        if not ok then
            local restored = rollback()
            return false, "BLOCKED - X4 REJECTED THE NATIVE GROUP POLICY CHANGE | ROLLBACK " .. (restored and "CONFIRMED" or "UNKNOWN")
        end
    end
    local state, matched, total = fleetGroupPolicyState(selected, policy)
    local expected = enabled and "YES" or "NO"
    if state ~= expected then
        local restored = rollback()
        return false, "BLOCKED - NATIVE READBACK DID NOT MATCH | " .. tostring(matched) .. " OF " .. tostring(total) .. " GROUPS ENABLED | ROLLBACK " .. (restored and "CONFIRMED" or "UNKNOWN")
    end
    return true, string.upper(contract.label) .. " = " .. expected .. " | NATIVE READBACK MATCHED FOR " .. tostring(total) .. " GROUP(S)"
end

local function pilotEvidence(ship)
    -- Shipped X4 UI converts the GetComponentData assignedpilot value through
    -- tostring -> ConvertStringToLuaID. Generic UniverseID conversion rejects
    -- this Lua identity and previously caused false UNKNOWN records.
    local ok, pilot = pcall(GetComponentData, ship, "assignedpilot")
    if not ok then return nil, "UNKNOWN" end
    if pilot == nil or pilot == 0 or tostring(pilot) == "" then return nil, "MISSING" end
    local convertedOK, pilotID = pcall(ConvertStringToLuaID, tostring(pilot))
    if not convertedOK or pilotID == nil or pilotID == 0 or tostring(pilotID) == "" then return nil, "UNKNOWN" end
    return pilotID, "PRESENT"
end

local function shipEvidence(ship)
    local name, fleetname, sector, sectorID, hull, shield, assignment, primarypurpose, shiptype = GetComponentData(
        ship, "name", "fleetname", "sector", "sectorid", "hullpercent", "shieldpercent", "assignment", "primarypurpose", "shiptype"
    )
    local idcode = componentIDCode(ship)
    local pilot, captainState = pilotEvidence(ship)
    local order = "UNKNOWN"
    if pilot then
        local ok, command, target = pcall(GetComponentData, pilot, "aicommand", "aicommandparam")
        if ok and type(command) == "string" and command ~= "" then
            local target64 = toComponent64(target)
            local targetName = target64 and componentName(target64, "UNKNOWN TARGET") or "UNKNOWN TARGET"
            local formatted, label = pcall(string.format, command, targetName)
            order = formatted and label or command
        end
    end
    local operational = false
    pcall(function() operational = C.IsComponentOperational(ship) end)
    return {
        object = ship,
        name = safeText(name, "Unnamed ship"),
        idcode = idcode,
        fleetname = safeText(fleetname, "Unnamed fleet"),
        sector = safeText(sector, "UNKNOWN"),
        sectorID = sectorID,
        hull = tonumber(hull),
        shield = tonumber(shield),
        assignment = safeText(assignment, "UNASSIGNED"),
        primarypurpose = safeText(primarypurpose, "UNKNOWN"),
        shiptype = safeText(shiptype, "UNKNOWN"),
        isMission = isProtectedShipID(idcode),
        storyOverride = isStoryOverrideID(idcode),
        storyAnswered = isStoryAnsweredID(idcode),
        captainState = captainState,
        captain = pilot and componentName(pilot, "UNKNOWN") or (captainState == "MISSING" and "NO CAPTAIN" or "UNKNOWN"),
        order = order,
        operational = operational == true,
        playerOccupied = tostring(ship) == tostring(C.GetPlayerOccupiedShipID()),
    }
end

local function classifyFleet(fleet)
    if fleet.missionProtected then
        local protected = fleet.protectedObject or fleet.commander
        return "CRITICAL", "PROTECTED OBJECT " .. protected.name .. " [" .. protected.idcode .. "] | REASON: X4 REPORTS ACTIVE OR UNKNOWN MISSION/STORY PROTECTION | CONSEQUENCE: FOC WILL NOT REPLACE ANY ORDER IN THIS FLEET."
    end
    if fleet.commander.captainState == "MISSING" then return "CRITICAL", "Commander has no captain." end
    if fleet.commander.captainState == "UNKNOWN" then return "UNKNOWN", "Commander captain state is unavailable." end
    if not fleet.commander.operational then return "CRITICAL", "Commander is not operational." end
    if fleet.commander.hull and fleet.commander.hull < 50 then return "CRITICAL", "Commander hull is below 50%." end
    if fleet.damaged > 0 or fleet.missingCaptains > 0 then return "DEGRADED", "One or more fleet ships need attention." end
    if fleet.unknown > 0 then return "UNKNOWN", "One or more readiness values are unknown." end
    return "READY", "No first-rollout blocker was observed."
end

local function sampleFleets(reason)
    local fleets = {}
    local missingCaptainIssues = {}
    local unknownCaptainIssues = {}
    local counts = { ready = 0, degraded = 0, critical = 0, unknown = 0, missingCaptains = 0, unknownCaptains = 0, damaged = 0 }
    local shipsExamined = 0
    local function recordCaptainIssue(evidence)
        if evidence.isMission or evidence.captainState == "PRESENT" then return end
        if evidence.captainState == "MISSING" then counts.missingCaptains = counts.missingCaptains + 1
        else counts.unknownCaptains = counts.unknownCaptains + 1 end
        local issue = { state = evidence.captainState, name = evidence.name, idcode = evidence.idcode, sector = evidence.sector }
        if evidence.captainState == "MISSING" then table.insert(missingCaptainIssues, issue)
        else table.insert(unknownCaptainIssues, issue) end
    end
    for _, row in ipairs(menu.structuralFleetRows or {}) do
        local commander64 = bridgeComponent64(row[2])
        if commander64 then
            local commanderEvidence = shipEvidence(commander64)
            commanderEvidence.fleetname = safeText(row[4], commanderEvidence.fleetname)
            shipsExamined = shipsExamined + 1
            recordCaptainIssue(commanderEvidence)
            local record = {
                commander = commanderEvidence,
                members = {},
                shipCount = 1,
                missingCaptains = 0,
                damaged = 0,
                unknown = 0,
                missionProtected = commanderEvidence.isMission,
                protectedObject = commanderEvidence.isMission and commanderEvidence or nil,
                overrideObject = commanderEvidence.storyOverride and commanderEvidence or nil,
            }
            for _, rawMember in ipairs(type(row[5]) == "table" and row[5] or {}) do
                local member64 = bridgeComponent64(rawMember)
                local member = member64 and shipEvidence(member64) or nil
                if member then
                    shipsExamined = shipsExamined + 1
                    recordCaptainIssue(member)
                    table.insert(record.members, member)
                    record.shipCount = record.shipCount + 1
                    if member.captainState == "MISSING" then record.missingCaptains = record.missingCaptains + 1 end
                    if member.hull and member.hull < 80 then record.damaged = record.damaged + 1 end
                    if member.isMission then
                        record.missionProtected = true
                        if not record.protectedObject then record.protectedObject = member end
                    end
                    if member.storyOverride and not record.overrideObject then record.overrideObject = member end
                    if not member.hull or not member.shield or member.captainState == "UNKNOWN" then record.unknown = record.unknown + 1 end
                end
            end
            record.status, record.reason = classifyFleet(record)
            counts[string.lower(record.status)] = (counts[string.lower(record.status)] or 0) + 1
            counts.damaged = counts.damaged + record.damaged
            table.insert(fleets, record)
        end
    end
    table.sort(fleets, function(a, b)
        local priority = { CRITICAL = 1, DEGRADED = 2, UNKNOWN = 3, READY = 4 }
        local ap, bp = priority[a.status] or 9, priority[b.status] or 9
        if ap ~= bp then return ap < bp end
        return a.commander.fleetname < b.commander.fleetname
    end)
    local sample = {
        reason = reason or "OPEN",
        time = getElapsedTime(),
        shipsExamined = shipsExamined,
        capped = false,
        authoritative = true,
        fleets = fleets,
        captainIssues = missingCaptainIssues,
        unknownCaptainIssues = unknownCaptainIssues,
        counts = counts,
    }
    menu.sample = sample
    table.insert(menu.history, 1, {
        reason = sample.reason,
        time = sample.time,
        shipsExamined = sample.shipsExamined,
        fleetCount = #sample.fleets,
        missingCaptains = sample.counts.missingCaptains,
    })
    while #menu.history > HISTORY_LIMIT do table.remove(menu.history) end
    menu.selectedFleet = clamp(menu.selectedFleet, 1, math.max(1, #fleets))
    DebugError("[FOC][B048][SAMPLE] reason=" .. sample.reason .. " ships_examined=" .. tostring(shipsExamined) .. " fleets=" .. tostring(#fleets) .. " protected=" .. tostring(menu.protectedShipCount) .. " source=MD_STRUCTURAL_ALLSUBORDINATES authoritative=1 mutation=NONE")
end

local function loadStructuralFleetRows(rows)
    local restored = {}
    if type(rows) == "table" then
        for _, row in ipairs(rows) do
            if type(row) == "table" and tonumber(row[1]) == 1 and row[2] ~= nil and type(row[5]) == "table" then restored[#restored + 1] = row end
        end
    end
    menu.structuralFleetRows = restored
    return #restored
end

function menu.structuralSnapshotBegin(_, expected)
    menu.structuralIncoming = { expected = tonumber(expected) or 0, rows = {}, current = nil, failed = false }
end
function menu.structuralSnapshotRowBegin(_, expected)
    if not menu.structuralIncoming then return end
    menu.structuralIncoming.current = { 1, nil, nil, nil, {}, expected = tonumber(expected) or 0 }
end
function menu.structuralSnapshotCommander(_, value) if menu.structuralIncoming and menu.structuralIncoming.current then menu.structuralIncoming.current[2] = value end end
function menu.structuralSnapshotKey(_, value) if menu.structuralIncoming and menu.structuralIncoming.current then menu.structuralIncoming.current[3] = tostring(value or "") end end
function menu.structuralSnapshotLabel(_, value) if menu.structuralIncoming and menu.structuralIncoming.current then menu.structuralIncoming.current[4] = tostring(value or "") end end
function menu.structuralSnapshotMember(_, value) if menu.structuralIncoming and menu.structuralIncoming.current then table.insert(menu.structuralIncoming.current[5], value) end end
function menu.structuralSnapshotRowCommit()
    local incoming = menu.structuralIncoming
    local row = incoming and incoming.current
    if not row then return end
    if row[2] == nil or row[3] == "" or #row[5] ~= row.expected then incoming.failed = true else table.insert(incoming.rows, row) end
    incoming.current = nil
end

function menu.roadmapBegin() menu.roadmapIncoming = { forces = {}, templates = {}, current = nil, policy = nil } end
function menu.roadmapForceBegin() if menu.roadmapIncoming then menu.roadmapIncoming.current = { nil, nil, nil, nil, nil, nil, nil, nil, {} } end end
function menu.roadmapForceID(_, value) if menu.roadmapIncoming and menu.roadmapIncoming.current then menu.roadmapIncoming.current[1] = tostring(value) end end
function menu.roadmapForceName(_, value) if menu.roadmapIncoming and menu.roadmapIncoming.current then menu.roadmapIncoming.current[2] = tostring(value) end end
function menu.roadmapForcePriority(_, value) if menu.roadmapIncoming and menu.roadmapIncoming.current then menu.roadmapIncoming.current[3] = tostring(value) end end
function menu.roadmapForceZone(_, value) if menu.roadmapIncoming and menu.roadmapIncoming.current then menu.roadmapIncoming.current[4] = tostring(value) end end
function menu.roadmapForceCoverage(_, value) if menu.roadmapIncoming and menu.roadmapIncoming.current then menu.roadmapIncoming.current[5] = tostring(value) end end
function menu.roadmapForceRotation(_, value) if menu.roadmapIncoming and menu.roadmapIncoming.current then menu.roadmapIncoming.current[6] = tostring(value) end end
function menu.roadmapForceActive(_, value) if menu.roadmapIncoming and menu.roadmapIncoming.current and tostring(value or "") ~= "" then menu.roadmapIncoming.current[7] = tostring(value) end end
function menu.roadmapForceReserve(_, value) if menu.roadmapIncoming and menu.roadmapIncoming.current and tostring(value or "") ~= "" then menu.roadmapIncoming.current[8] = tostring(value) end end
function menu.roadmapForceMember(_, value) if menu.roadmapIncoming and menu.roadmapIncoming.current then table.insert(menu.roadmapIncoming.current[9], tostring(value)) end end
function menu.roadmapForceCommit() if menu.roadmapIncoming and menu.roadmapIncoming.current then table.insert(menu.roadmapIncoming.forces, menu.roadmapIncoming.current); menu.roadmapIncoming.current = nil end end
function menu.roadmapTemplateRow(_, value) if menu.roadmapIncoming and type(value) == "table" then table.insert(menu.roadmapIncoming.templates, value) end end
function menu.roadmapPolicy(_, value) if menu.roadmapIncoming and type(value) == "table" then menu.roadmapIncoming.policy = value end end
function menu.roadmapComplete()
    if not menu.roadmapIncoming then return end
    menu.taskForces = menu.roadmapIncoming.forces
    menu.templates = menu.roadmapIncoming.templates
    local policy = menu.roadmapIncoming.policy
    if policy then menu.operations.retreat = tostring(policy[2]); menu.operations.retreatHull = tonumber(policy[3]) or 30; menu.operations.retreatReturn = tostring(policy[4]); menu.operations.commanderHull = tonumber(policy[5]) or 50; menu.operations.fleetHull = tonumber(policy[6]) or 50; menu.operations.captainCoverage = tonumber(policy[7]) or 100; menu.operations.maxFleetSize = tonumber(policy[8]) or 100; menu.operations.preset = tostring(policy[9]) end
    menu.roadmapIncoming = nil
end
function menu.structuralSnapshotComplete()
    local incoming = menu.structuralIncoming
    menu.structuralIncoming = nil
    if not incoming or incoming.failed or incoming.current or #incoming.rows ~= incoming.expected then
        menu.notice = "FLEET REFRESH BLOCKED - INCOMPLETE AUTHORITATIVE STRUCTURAL SNAPSHOT; PREVIOUS FLEET LIST RETAINED"
        menu.plan.lastState = "BLOCKED"
    else
        loadStructuralFleetRows(incoming.rows)
        sampleFleets("MD_STRUCTURAL_REFRESH")
        menu.notice = "FLEET LIST REFRESHED FROM AUTHORITATIVE STRUCTURAL DISCOVERY"
    end
    if menu.frame then menu.refresh(true) end
end

local function section(tableWidget, label)
    local row = tableWidget:addRow(false)
    row[1]:setColSpan(4):createText(label, { font = Helper.headerFont, fontsize = Helper.standardFontSize + 2, color = headingColor })
end

local function textRow(tableWidget, label, value, color)
    local row = tableWidget:addRow(false)
    row[1]:createText(label, { color = neutralColor })
    row[2]:setColSpan(3):createText(safeText(value), { wordwrap = true, color = color })
end

local function workflowLabel(value, active)
    local text = safeText(value)
    if not menu.workflowPointersVisible or active ~= true then return text end
    local guided = text:find("^CREATE ") or text:find("^PREVIEW ") or text:find("^APPROVE ")
        or text:find("^ADD SELECTED ") or text:find("^MAKE ACTIVE ") or text:find("^MAKE RESERVE ")
        or text:find("^SAVE ") or text:find("^SEND THIS ") or text:find("^CONFIRM:")
        or text:find("^ROTATE ACTIVE ") or text == "OPEN X4 NATIVE REPAIR SCREEN"
    if FOC_Advisor and FOC_Advisor.step == 'PURCHASE' and text == 'PREVIEW BUILDING THIS FLEET AT MY YARDS' then guided=false end
    if text:find('^PREPARE ') or text:find('^CONFIRM PURCHASE:') then guided=true end
    if FOC_Advisor and FOC_Advisor.step == 'PROCUREMENT' and FOC_Procurement then
        if text=='BACK TO FLEET BUILD / BUY' and (FOC_Procurement.lastFailure or not FOC_Procurement.quote) then guided=true end
        if text=='CHECK PREPARED ORDER / DELIVERY' and FOC_Procurement.token and FOC_Procurement.token>0 then guided=true end
    end
    return guided and ("-> " .. text) or text
end

local function beginButtonFeedback(value)
    local label = safeText(value, "ACTION")
    menu.notice = "CLICK RECEIVED - " .. label .. " | SEE THE RESULT ON THIS PAGE"
    menu.plan.lastResult = menu.notice
    menu.feedbackRedraw = true
end

local function actionRow(tableWidget, label, value, handler, active, color, preserveResult)
    local row = tableWidget:addRow(true)
    row[1]:createText(label, { color = neutralColor })
    local properties = { active = active == true }
    if color == warningColor then properties.bgColor = requiredActionBackground
    elseif color == criticalColor then properties.bgColor = failedActionBackground
    elseif color == passColor then properties.bgColor = confirmedActionBackground
    elseif color == headingColor then properties.bgColor = normalActionBackground
    elseif color == activeTabBackground then properties.bgColor = activeTabBackground
    elseif color then properties.bgColor = availableActionBackground end
    row[2]:setColSpan(3):createButton(properties):setText(workflowLabel(value, active), { halign = "center" })
    if active == true then
        local owner, used = menu.frame, false
        row[2].handlers.onClick = function()
            if used or menu.frame ~= owner or menu.closeInProgress then return end
            used = true
            menu.feedbackRedraw = true
            if not preserveResult then beginButtonFeedback(value) end
            handler()
        end
    end
end

local function actionRequired(tableWidget, what, why, nextStep, targetPage, buttonText, safetyText)
    section(tableWidget, "ACTION REQUIRED")
    textRow(tableWidget, "What happened", what, warningColor)
    textRow(tableWidget, "Why", why, warningColor)
    textRow(tableWidget, "What to do next", nextStep, warningColor)
    textRow(tableWidget, "Safety", safetyText or "Nothing was changed. No orders, assignments, or fleet settings were sent to X4.", passColor)
    actionRow(tableWidget, "Take me there", buttonText, function()
        menu.page = targetPage
        menu.activeTab = targetPage
        rebuild(true)
    end, true, warningColor)
end

local function dropdownOptions(values, suffix)
    local options = {}
    for _, value in ipairs(values) do
        options[#options + 1] = { id = value, text = tostring(value) .. (suffix or ""), icon = "", displayremoveoption = false }
    end
    return options
end

local function dropdownRow(tableWidget, label, values, selected, confirmed, suffix)
    local row = tableWidget:addRow(true)
    row[1]:createText(label, { color = neutralColor })
    local dropdown = row[2]:setColSpan(3):createDropDown(dropdownOptions(values, suffix), {
        active = true, startOption = selected, height = Helper.standardButtonHeight,
    })
    dropdown:setTextProperties({ fontsize = Helper.standardFontSize })
    row[2].handlers.onDropDownConfirmed = function(_, value)
        local shouldRebuild = confirmed(value)
        if shouldRebuild ~= false then rebuild(false) end
    end
end

local function buttonPairRow(tableWidget, leftText, leftHandler, rightText, rightHandler, rightColor, leftActive, rightActive)
    if leftActive == nil then leftActive = true end
    if rightActive == nil then rightActive = true end
    local row = tableWidget:addRow(true)
    row[1]:setColSpan(2):createButton({ active = leftActive }):setText(workflowLabel(leftText, leftActive), { halign = "center" })
    if leftActive then
        local owner, used = menu.frame, false
        row[1].handlers.onClick = function()
            if used or menu.frame ~= owner or menu.closeInProgress then return end
            used = true
            beginButtonFeedback(leftText)
            leftHandler()
        end
    end
    local mapped = rightColor == warningColor and requiredActionBackground or rightColor == passColor and confirmedActionBackground or normalActionBackground
    row[3]:setColSpan(2):createButton({ active = rightActive, bgColor = mapped }):setText(workflowLabel(rightText, rightActive), { halign = "center" })
    if rightActive then
        local owner, used = menu.frame, false
        row[3].handlers.onClick = function()
            if used or menu.frame ~= owner or menu.closeInProgress then return end
            used = true
            beginButtonFeedback(rightText)
            rightHandler()
        end
    end
end

local function auditAction(kind, detail, result, state, persistentData)
    result = result or (kind .. " RECEIVED - PERSISTENT READBACK REQUIRED")
    state = state or "RECEIVED"
    local payload = { kind, safeText(detail, "NONE"), menu.plan.authority, getElapsedTime(), state, result, persistentData or "" }
    menu.pendingActionKind = kind
    AddUITriggeredEvent(menu.name, "plan_action", payload)
    local sample = menu.sample
    table.insert(menu.history, 1, {
        reason = kind,
        time = payload[4],
        shipsExamined = sample and sample.shipsExamined or 0,
        fleetCount = sample and #sample.fleets or 0,
        missingCaptains = sample and (sample.counts.missingCaptains + sample.counts.unknownCaptains) or 0,
        state = state,
        result = result,
    })
    menu.plan.lastResult = result
    menu.plan.lastState = state
    menu.notice = result
    rebuild(false)
end

function menu.maintenanceSnapshotBegin()
    menu.maintenance.pending = true
    menu.maintenance.commanderID = nil
    menu.maintenance.fleetName = nil
    menu.maintenance.lostRows = {}
    menu.maintenance.repairRows = {}
    menu.maintenance.incomingLost = {}
    menu.maintenance.incomingRepair = {}
    menu.maintenance.status = "SCANNING NATIVE FLEET RECORDS"
end

function menu.maintenanceRepairRowValue(field, value)
    local row = menu.maintenance.incomingRepair or {}
    menu.maintenance.incomingRepair = row
    if field == "idcode" then row.idcode = safeText(value, "UNKNOWN")
    elseif field == "name" then row.name = safeText(value, "UNKNOWN SHIP")
    elseif field == "hull" then row.hull = tonumber(value)
    elseif field == "scope" then row.scope = safeText(value, "PLAYER")
    elseif field == "fleet" then row.fleet = safeText(value, "ALL PLAYER-OWNED DEFAULT")
    elseif field == "threshold" then row.threshold = tonumber(value)
    elseif field == "protected" then row.protected = value == true or value == 1 or value == "1"
    elseif field == "playercontrolled" then row.playerOccupied = value == true or value == 1 or value == "1" end
end

function menu.maintenanceRepairRowCommit()
    local row = menu.maintenance.incomingRepair
    menu.maintenance.incomingRepair = {}
    if not row or not row.idcode or not row.name or not row.hull or not row.scope or not row.threshold then return end
    menu.maintenance.repairRows[#menu.maintenance.repairRows + 1] = row
end

function menu.maintenanceRepairRowID(_, value) menu.maintenanceRepairRowValue("idcode", value) end
function menu.maintenanceRepairRowName(_, value) menu.maintenanceRepairRowValue("name", value) end
function menu.maintenanceRepairRowHull(_, value) menu.maintenanceRepairRowValue("hull", value) end
function menu.maintenanceRepairRowScope(_, value) menu.maintenanceRepairRowValue("scope", value) end
function menu.maintenanceRepairRowFleet(_, value) menu.maintenanceRepairRowValue("fleet", value) end
function menu.maintenanceRepairRowThreshold(_, value) menu.maintenanceRepairRowValue("threshold", value) end
function menu.maintenanceRepairRowProtected(_, value) menu.maintenanceRepairRowValue("protected", value) end
function menu.maintenanceRepairRowPlayerControlled(_, value) menu.maintenanceRepairRowValue("playercontrolled", value) end

function menu.maintenanceMetaValue(field, value)
    if field == "commander" then menu.maintenance.commanderID = safeText(value, "UNKNOWN")
    elseif field == "fleet" then menu.maintenance.fleetName = safeText(value, "UNKNOWN FLEET")
    elseif field == "status" then menu.maintenance.status = safeText(value, "UNKNOWN") end
end

function menu.maintenanceLostValue(field, value)
    local row = menu.maintenance.incomingLost or {}
    menu.maintenance.incomingLost = row
    if field == "fleetunit" then row.fleetunit = value
    elseif field == "index" then row.index = value
    elseif field == "name" then row.name = safeText(value, "UNKNOWN LOST SHIP")
    elseif field == "state" then row.state = safeText(value, "UNKNOWN")
    elseif field == "signature" then row.signature = safeText(value, "UNKNOWN")
    elseif field == "detail" then row.detail = safeText(value, "No native readiness detail was returned.")
    elseif field == "ready" then row.ready = value == true or value == 1 or value == "1" end
end

function menu.maintenanceLostCommit()
    local row = menu.maintenance.incomingLost
    menu.maintenance.incomingLost = {}
    if not row or row.index == nil or not row.state or not row.signature then return end
    menu.maintenance.lostRows[#menu.maintenance.lostRows + 1] = row
end

function menu.maintenanceSnapshotComplete()
    menu.maintenance.pending = false
    menu.maintenance.incomingLost = nil
    menu.maintenance.incomingRepair = nil
    menu.maintenance.selectedRepair = clamp(menu.maintenance.selectedRepair, 1, math.max(1, #menu.maintenance.repairRows))
    menu.maintenance.selectedLost = clamp(menu.maintenance.selectedLost, 1, math.max(1, #menu.maintenance.lostRows))
    if menu.frame and menu.page == "fleets" and menu.fleetMode == "maintenance" then
        menu.notice = "REPAIR / REBUILD REFRESH COMPLETE - " .. safeText(menu.maintenance.status, "SEE RESULTS BELOW")
        menu.plan.lastResult = menu.notice
        rebuild(false)
    end
end

function menu.maintenanceRepairOpenValue(field, value)
    menu.maintenance.nativeOpen = menu.maintenance.nativeOpen or {}
    menu.maintenance.nativeOpen[field] = value
end

local function openNativeMenu(name, params)
    if not menu.frame or menu.closeInProgress then return end
    menu.closeInProgress = true
    AddUITriggeredEvent(menu.name, "closed", { reason = "native_handoff" })
    Helper.closeMenuAndOpenNewMenu(menu, name, params)
    menu.frame = nil
    menu.closeInProgress = false
end

function menu.openFleetInspection(expectedKey)
    if not menu.frame or menu.closeInProgress or menu.pendingActionKind or menu.carrierTransaction then return end
    local selected = menu.strategicFleet(menu.selectedFleet)
    local commander = selected and selected.commander and bridgeComponent64(selected.commander.object)
    if not commander or fleetKey(selected) ~= expectedKey or GetComponentData(commander, "isplayerowned") ~= true or GetComponentData(commander, "idcode") ~= selected.commander.idcode then
        menu.notice = "MAP INSPECTION BLOCKED - THE EXACT SELECTED SHIP IS NO LONGER AVAILABLE"
        rebuild(false)
        return
    end
    local luaid = componentLuaID(commander)
    if not luaid then menu.notice = "MAP INSPECTION BLOCKED - INVALID NATIVE SHIP ID"; rebuild(false); return end
    local top
    if menu.mainTable and menu.mainTable.id then
        local ok, value = pcall(GetTopRow, menu.mainTable.id)
        if ok then top = value end
    end
    menu.nativeMapReturn = { key = expectedKey, page = menu.page, activeTab = menu.activeTab,
        view = menu.strategic.view, group = menu.strategic.group, role = menu.strategic.wingRole,
        damage = menu.strategic.damageHull, notice = menu.notice, result = menu.plan.lastResult,
        state = menu.plan.lastState, top = top }
    DebugError("[FOC][B058][NATIVE_MAP] stage=REQUESTED subject=" .. selected.commander.idcode .. " orders_sent=0")
    openNativeMenu("MapMenu", { 0, 0, true, luaid, nil, "infomode", { "info", luaid } })
end

function menu.onSaveState()
    if menu.nativeMapReturn then return { nativeInspection = true } end
end

function menu.historyMapButton(row, entry, color, enabled, sectorOnly)
    local eventID = entry.id
    row[1]:createButton({ active = enabled }):setText("EVENT " .. tostring(eventID) .. (sectorOnly and " - SECTOR" or " - MAP"), { color = color })
    row[1].handlers.onClick = function() menu.openHistoryInspection(eventID) end
end

function menu.historyRows()
    -- Freeze older pages by stable event ID. Returning to page one admits new rows.
    if not menu.historyWindow or (tonumber(menu.listPages["activity.history"]) or 1) == 1 then
        menu.historyWindow = {}
        for _, entry in ipairs(menu.liveActivity) do menu.historyWindow[#menu.historyWindow + 1] = entry end
    end
    local retained, newer = {}, 0
    for _, entry in ipairs(menu.historyWindow) do retained[entry.id] = true end
    for _, entry in ipairs(menu.liveActivity) do if not retained[entry.id] then newer = newer + 1 end end
    return menu.historyWindow, newer
end

function menu.historyTarget(entry)
    local target = entry and bridgeComponent64(entry.target)
    if target and entry.targetid and entry.targetid ~= "" and GetComponentData(target, "idcode") == entry.targetid then
        return componentLuaID(target), false
    end
    local sector = entry and bridgeComponent64(entry.sector)
    if sector then return componentLuaID(sector), true end
end

function menu.openHistoryInspection(expectedID)
    if not menu.frame or menu.closeInProgress or menu.pendingActionKind or menu.carrierTransaction then return end
    local entry
    for _, candidate in ipairs(menu.historyWindow or {}) do if candidate.id == expectedID then entry = candidate; break end end
    local luaid, sectorOnly = menu.historyTarget(entry)
    if not luaid then menu.notice = "HISTORY MAP UNAVAILABLE - NO SURVIVING RECORDED SUBJECT OR SECTOR"; rebuild(false); return end
    local top
    if menu.mainTable and menu.mainTable.id then
        local ok, value = pcall(GetTopRow, menu.mainTable.id)
        if ok then top = value end
    end
    menu.nativeMapReturn = { history = true, page = menu.page, activeTab = menu.activeTab,
        activityView = menu.activityView, top = top, notice = menu.notice }
    DebugError("[FOC][B058][HISTORY_MAP] event=" .. tostring(expectedID) .. " sector_only=" .. tostring(sectorOnly) .. " orders_sent=0")
    if sectorOnly then openNativeMenu("MapMenu", { 0, 0, true, luaid })
    else openNativeMenu("MapMenu", { 0, 0, true, luaid, nil, "infomode", { "info", luaid } }) end
end

function menu.restoreFleetInspection(state)
    local saved = menu.nativeMapReturn
    menu.nativeMapReturn = nil
    if not saved or type(state) ~= "table" or state.nativeInspection ~= true then return false end
    if saved.advisor then
        menu.page, menu.activeTab = saved.page, saved.activeTab
        menu.strategic.view = "COVERAGE AND FLEET TEMPLATES"
        menu.restoreTopRow = saved.top
        menu.create()
        return true
    end
    if saved.history then
        menu.page, menu.activeTab, menu.activityView = saved.page, saved.activeTab, saved.activityView
        menu.notice, menu.restoreTopRow = saved.notice, saved.top
        menu.create()
        AddUITriggeredEvent(menu.name, "activity_snapshot", nil)
        return true
    end
    menu.page, menu.activeTab = saved.page, saved.activeTab
    menu.strategic.view, menu.strategic.group = saved.view, saved.group
    menu.strategic.wingRole, menu.strategic.damageHull = saved.role, saved.damage
    menu.plan.lastResult, menu.plan.lastState, menu.notice = saved.result, saved.state, saved.notice
    sampleFleets("NATIVE MAP RETURN")
    menu.selectedFleet = 0
    for index, fleet in ipairs(menu.sample.fleets) do
        if fleetKey(fleet) == saved.key then menu.selectedFleet = index; break end
    end
    if menu.selectedFleet == 0 then menu.notice = "MAP RETURN - ORIGINAL FLEET UNAVAILABLE; CHOOSE A FLEET" end
    menu.restoreTopRow = saved.top
    AddUITriggeredEvent(menu.name, "strategic_refresh", nil)
    DebugError("[FOC][B058][NATIVE_MAP] stage=RETURNED fleet_resolved=" .. tostring(menu.selectedFleet ~= 0) .. " draft_preserved=1 orders_sent=0")
    menu.create()
    return true
end

function menu.openAdvisorSector(id)
    if not menu.frame or menu.closeInProgress or menu.pendingActionKind then return end
    local component = FOC_Advisor.component(id)
    if not component then return end
    local ok, luaid = pcall(ConvertStringToLuaID, tostring(component))
    if not ok or not luaid then return end
    local top
    if menu.mainTable and menu.mainTable.id then local success,value=pcall(GetTopRow,menu.mainTable.id); if success then top=value end end
    menu.nativeMapReturn={advisor=true,page=menu.page,activeTab=menu.activeTab,top=top}
    openNativeMenu("MapMenu", {0,0,true,luaid})
end

function menu.openAdvisorFromMap(child)
    if not child or child.name ~= "FOC_OperationsMap" or child.request then return end
    menu.page, menu.activeTab = "taskforces", "taskforces"
    menu.strategic.view = "COVERAGE AND FLEET TEMPLATES"
    Helper.closeMenuAndOpenNewMenu(child,menu.name,{0,0,171,"FOC Build 072","RUNTIME ACCEPTANCE REQUIRED",menu.plan.authority,menu.plan.lastResult})
    if child.cleanup then child.cleanup() end
end

function menu.maintenanceRepairOpenComplete()
    local handoff = menu.maintenance.nativeOpen
    menu.maintenance.nativeOpen = nil
    local ship = handoff and bridgeComponent64(handoff.ship)
    local facility = handoff and bridgeComponent64(handoff.facility)
    if not ship or not facility then
        menu.maintenance.pending = false
        menu.notice = "REPAIR BLOCKED - NO CURRENT COMPATIBLE NATIVE REPAIR FACILITY WAS PROVEN"
        if menu.frame then rebuild(false) end
        return
    end
    menu.maintenance.pending = false
    openNativeMenu("ShipConfigurationMenu", { 0, 0, componentLuaID(facility), "upgrade", { tostring(ship) }, true })
end

function menu.maintenanceLostEditorValue(_, value)
    menu.maintenance.nativeLostOpen = value
end

function menu.maintenanceLostEditorComplete()
    local fleetunit = menu.maintenance.nativeLostOpen
    menu.maintenance.nativeLostOpen = nil
    menu.maintenance.pending = false
    if not fleetunit then
        menu.notice = "LOST-SHIP EDITOR BLOCKED - THE CURRENT NATIVE RECORD NO LONGER MATCHES THE SELECTED SNAPSHOT"
        if menu.frame then rebuild(false) end
        return
    end
    openNativeMenu("ShipConfigurationMenu", { 0, 0, nil, "upgradefleetunit", { fleetunit } })
end

local function requestMaintenanceSnapshot(selected)
    local commanderID = safeText(selected and selected.commander and selected.commander.idcode, "GLOBAL")
    if commanderID == "" or commanderID == "UNKNOWN" then commanderID = "GLOBAL" end
    menu.maintenance.pending = true
    menu.maintenance.status = commanderID == "GLOBAL" and "WAITING FOR GLOBAL ENROLLED-FLEET RECOVERY READBACK" or "WAITING FOR NATIVE AND GLOBAL RECOVERY READBACK"
    AddUITriggeredEvent(menu.name, "maintenance_snapshot", commanderID)
    rebuild(false)
end

local function requestNativeRepair(ship)
    if not ship or menu.maintenance.pending then return end
    menu.maintenance.pending = true
    menu.maintenance.nativeOpen = nil
    menu.notice = "FINDING A COMPATIBLE X4 REPAIR FACILITY - NO ORDER OR PAYMENT SENT"
    AddUITriggeredEvent(menu.name, "maintenance_open_repair", { ship.idcode, ship.scope })
    rebuild(false)
end

local function requestNativeLostEditor(selected, lost)
    if not selected or not lost or menu.maintenance.pending then return end
    menu.maintenance.pending = true
    menu.maintenance.nativeLostOpen = nil
    menu.notice = "REVALIDATING THE CURRENT LOST FLEET-UNIT RECORD - NO BUILD QUEUED"
    AddUITriggeredEvent(menu.name, "maintenance_open_lost_editor", { selected.commander.idcode, lost.index, lost.signature })
    rebuild(false)
end

local function requestFleetDraftSave(selected, key, orders, home)
    if menu.pendingDraftSaves[key] then
        menu.plan.lastResult = "DRAFT SAVE ALREADY PENDING - WAITING FOR PERSISTENT READBACK"
        menu.notice = menu.plan.lastResult
        DebugError("[FOC][B048][DRAFT_SAVE_SUPPRESSED] key=" .. tostring(key or "UNKNOWN") .. " reason=PENDING_READBACK mutation=NONE")
        rebuild(false)
        return
    end
    local commanderIdcode = safeText(selected and selected.commander and selected.commander.idcode, "")
    if commanderIdcode == "" or commanderIdcode == "UNKNOWN" then
        menu.plan.lastResult = "DRAFT NOT SAVED - FLEET COMMANDER IDENTITY IS UNKNOWN"
        menu.notice = menu.plan.lastResult
        rebuild(false)
        return
    end
    local requestedAt = getElapsedTime()
    menu.pendingDraftSaves[key] = draftSnapshot(orders, home, requestedAt)
    menu.draftReadback = { key = nil, result = nil, state = nil }
    local payload = {
        "SAVE_FLEET_DRAFT", fleetAuditSubject(selected, key), menu.plan.authority, requestedAt,
        "SAVE_PENDING", "DRAFT SAVE REQUEST SENT - PERSISTENT READBACK REQUIRED",
        commanderIdcode, safeText(selected.commander.fleetname, "Unnamed fleet"),
        home.id, home.text, home.position[1], home.position[2], home.position[3],
        orders.fleetRole, orders.coverage, orders.sectorChoice, orders.patrolPattern,
        orders.respondShips, orders.respondStations, orders.distress,
        orders.distressUrgency, orders.shipDamage, orders.stationDamage, orders.returnHome,
        orders.manualOverride, orders.locked, orders.nonCombatOverride, 4,
    }
    AddUITriggeredEvent(menu.name, "plan_action", payload)
    local sample = menu.sample
    table.insert(menu.history, 1, {
        reason = "SAVE_FLEET_DRAFT", time = requestedAt,
        shipsExamined = sample and sample.shipsExamined or 0,
        fleetCount = sample and #sample.fleets or 0,
        missingCaptains = sample and (sample.counts.missingCaptains + sample.counts.unknownCaptains) or 0,
        state = "SAVE_PENDING", result = payload[6],
    })
    menu.plan.lastState = "SAVE_PENDING"
    menu.plan.lastResult = payload[6]
    menu.notice = payload[6]
    DebugError("[FOC][B048][DRAFT_SAVE_REQUEST] fleet=" .. fleetAuditSubject(selected, key) .. " home_key=" .. tostring(home.id) .. " schema=4 readback=PENDING mutation=NONE")
    rebuild(false)
end

local function requestFleetPatrolStart(selected, key, orders, home)
    if menu.pendingActionKind then
        menu.plan.lastResult = "WAIT FOR THE CURRENT FOC ACTION TO FINISH"
        menu.notice = menu.plan.lastResult
        rebuild(false)
        return
    end
    local commanderIdcode = safeText(selected and selected.commander and selected.commander.idcode, "")
    if commanderIdcode == "" or commanderIdcode == "UNKNOWN" then
        menu.plan.lastResult = "PATROL NOT SENT - FLEET COMMANDER IDENTITY IS UNKNOWN"
        menu.notice = menu.plan.lastResult
        rebuild(false)
        return
    end
    if not home then
        menu.plan.lastResult = "PATROL NOT SENT - CHOOSE A HOME POINT ON THE MAP"
        menu.notice = menu.plan.lastResult
        rebuild(false)
        return
    end
    local requestedAt = getElapsedTime()
    local armedOrders = draftSnapshot(orders, home, requestedAt)
    armedOrders.manualOverride = false
    armedOrders.locked = false
    menu.pendingPatrolStart = { key = key, snapshot = armedOrders }
    menu.pendingActionKind = "START_FLEET_PATROL"
    local payload = {
        "START_FLEET_PATROL", fleetAuditSubject(selected, key), "FULL AUTOMATION", requestedAt,
        "FLEET_PATROL_PENDING", "SENDING THIS FLEET ON PATROL - WAITING FOR ACTIVE NATIVE READBACK",
        commanderIdcode, safeText(selected.commander.fleetname, "Unnamed fleet"),
        home.id, home.text, home.position[1], home.position[2], home.position[3],
        orders.fleetRole, orders.coverage, orders.sectorChoice, orders.patrolPattern,
        orders.respondShips, orders.respondStations, orders.distress,
        orders.distressUrgency, orders.shipDamage, orders.stationDamage, orders.returnHome,
        false, false, orders.nonCombatOverride, 4,
    }
    AddUITriggeredEvent(menu.name, "plan_action", payload)
    local sample = menu.sample
    table.insert(menu.history, 1, {
        reason = "START_FLEET_PATROL", time = requestedAt,
        shipsExamined = sample and sample.shipsExamined or 0,
        fleetCount = sample and #sample.fleets or 0,
        missingCaptains = sample and (sample.counts.missingCaptains + sample.counts.unknownCaptains) or 0,
        state = payload[5], result = payload[6],
    })
    menu.plan.lastState = payload[5]
    menu.plan.lastResult = payload[6]
    menu.notice = payload[6]
    DebugError("[FOC][B048][FLEET_PATROL_REQUEST] fleet=" .. fleetAuditSubject(selected, key) .. " home_key=" .. tostring(home.id) .. " replace_selected=1 automation_selected=1 readback=PENDING")
    rebuild(false)
end

local function draftKeyReceived(_, value)
    menu.draftReadback.key = tostring(value or "")
end

local function draftResultReceived(_, value)
    menu.draftReadback.result = tostring(value or "DRAFT SAVE FAILED - NO RESULT RETURNED")
end

local function draftStateReceived(_, value)
    menu.draftReadback.state = tostring(value or "BLOCKED")
end

local function draftSaveComplete()
    local key = menu.draftReadback.key
    local state = menu.draftReadback.state or "BLOCKED"
    local result = menu.draftReadback.result or "DRAFT SAVE FAILED - PERSISTENT READBACK WAS INCOMPLETE"
    local pending = key and menu.pendingDraftSaves[key] or nil
    if state == "DRAFT_SAVED" and pending then
        menu.draftsByFleet[key] = pending
        menu.pendingDraftSaves[key] = nil
    elseif key then
        menu.pendingDraftSaves[key] = nil
    end
    menu.plan.lastState = state
    menu.plan.lastResult = result
    menu.notice = result
    if menu.history[1] and menu.history[1].reason == "SAVE_FLEET_DRAFT" then
        menu.history[1].state = state
        menu.history[1].result = result
    end
    DebugError("[FOC][B048][DRAFT_SAVE_READBACK] key=" .. tostring(key or "UNKNOWN") .. " state=" .. state .. " result=" .. result .. " mutation=NONE")
    menu.draftReadback = { key = nil, result = nil, state = nil }
    if menu.frame then rebuild(false) end
end

local actionReadback = { result = nil, state = nil }
local function actionResultReceived(_, value) actionReadback.result = tostring(value or "NO RESULT RETURNED") end
local function actionStateReceived(_, value) actionReadback.state = tostring(value or "BLOCKED") end
local function actionComplete()
    local completedKind = menu.pendingActionKind
    menu.plan.lastResult = actionReadback.result or "TRANSACTION FAILED - READBACK WAS INCOMPLETE"
    menu.plan.lastState = actionReadback.state or "BLOCKED"
    menu.notice = menu.plan.lastResult
    if menu.history[1] then menu.history[1].result = menu.plan.lastResult; menu.history[1].state = menu.plan.lastState end
    if completedKind == "START_FLEET_PATROL" and menu.pendingPatrolStart and tostring(menu.plan.lastState):find("FLEET_PATROL", 1, true) then
        local pending = menu.pendingPatrolStart
        menu.draftsByFleet[pending.key] = pending.snapshot
        menu.ordersByFleet[pending.key] = pending.snapshot
        if menu.plan.lastState == "FLEET_PATROL_ACTIVE" then
            menu.plan.authority = "FULL AUTOMATION"
            menu.lastActivePatrolFleet = pending.key
        elseif menu.lastActivePatrolFleet == pending.key then
            menu.lastActivePatrolFleet = nil
        end
    end
    menu.pendingPatrolStart = nil
    if completedKind == "SAVE_SAFETY_THRESHOLDS" and menu.plan.lastState == "SAFETY_THRESHOLDS_SAVED" then menu.safety.dirty = false end
    if completedKind == "ACADEMY_PREVIEW_RECRUIT" then
        if menu.plan.lastState ~= "ACADEMY_RECRUIT_READY" then menu.academy.previewRecruitTrack = nil end
    elseif completedKind == "ACADEMY_RECRUIT" then
        menu.academy.previewRecruitTrack = nil
    end
    local keepPending = completedKind == "ACADEMY_MARINE_ASSIGN" and menu.plan.lastState == "ACADEMY_MARINE_TRANSFER_PENDING"
    actionReadback = { result = nil, state = nil }
    if not keepPending then menu.pendingActionKind = nil end
    if menu.frame then
        sampleFleets("NATIVE READBACK")
        if menu.page == "fleets" and menu.fleetMode == "maintenance" and completedKind == "MAINTENANCE_REPLACE" then
            menu.maintenance.pending = false
            menu.maintenance.status = menu.plan.lastState == "FLEET_REBUILD_REQUESTED" and "REQUEST SENT - PRESS REFRESH TO VERIFY NATIVE BUILDING READBACK" or menu.plan.lastResult
        end
        rebuild(false)
    end
end

local function liveActivityRow()
    if not menu.liveActivityIncoming then menu.liveActivityIncoming = {} end
    return menu.liveActivityIncoming
end

local function liveActivityID(_, value) liveActivityRow().id = tonumber(value) end
local function liveActivityTime(_, value) liveActivityRow().time = tonumber(value) end
local function liveActivityKind(_, value) liveActivityRow().kind = safeText(value, "ACTIVITY") end
local function liveActivityState(_, value) liveActivityRow().state = safeText(value, "RECORDED") end
local function liveActivitySubject(_, value) liveActivityRow().subject = safeText(value, "FOC") end
local function liveActivityDetail(_, value) liveActivityRow().detail = safeText(value, "No detail recorded.") end
local function liveActivitySeverity(_, value) liveActivityRow().severity = activitySeverity(liveActivityRow().kind, liveActivityRow().detail, value) end
local function liveActivityNow(_, value) menu.gameTime = tonumber(value) or menu.gameTime end
local function liveActivityCommit()
    local row = menu.liveActivityIncoming
    menu.liveActivityIncoming = nil
    if not row or not row.id or row.id < 1 or row.id % 1 ~= 0 or not row.time or not row.kind or not row.state or not row.subject or not row.detail or not row.severity then
        if menu.activitySnapshot then menu.activitySnapshot.invalid = true end
        return
    end
    row.severity = activitySeverity(row.kind, row.detail, row.severity)
    if menu.activitySnapshot then
        local snapshot = menu.activitySnapshot
        if snapshot.ids[row.id] or #snapshot.rows >= LIVE_ACTIVITY_LIMIT then snapshot.invalid = true; return end
        snapshot.ids[row.id] = true
        snapshot.rows[#snapshot.rows + 1] = row
        return
    end
    for index = #menu.liveActivity, 1, -1 do
        if menu.liveActivity[index].id == row.id then table.remove(menu.liveActivity, index) end
    end
    table.insert(menu.liveActivity, 1, row)
    while #menu.liveActivity > LIVE_ACTIVITY_LIMIT do table.remove(menu.liveActivity) end
    if menu.frame and menu.page == "activity" and menu.activityView == "live" then rebuild(false) end
end

function menu.activityTarget(_, value) liveActivityRow().target = value end
function menu.activityTargetID(_, value) liveActivityRow().targetid = tostring(value or "") end
function menu.activitySector(_, value) liveActivityRow().sector = value end

function menu.activitySnapshotBegin(_, expected)
    menu.liveActivityIncoming = nil
    menu.activitySnapshot = { expected = tonumber(expected), rows = {}, ids = {} }
end

function menu.activitySnapshotComplete()
    local snapshot = menu.activitySnapshot
    if snapshot and menu.liveActivityIncoming then snapshot.invalid = true end
    menu.activitySnapshot, menu.liveActivityIncoming = nil, nil
    if not snapshot or snapshot.invalid or not snapshot.expected or snapshot.expected < 0 or snapshot.expected > LIVE_ACTIVITY_LIMIT or #snapshot.rows ~= snapshot.expected then return end
    if snapshot.expected == 0 and #menu.liveActivity > 0 then return end
    table.sort(snapshot.rows, function(a, b) return a.id > b.id end)
    menu.liveActivity = snapshot.rows
    if menu.frame and menu.page == "activity" then rebuild(false) end
end

local function academySnapshotBegin(_, expected)
    menu.academyIncoming = { expected = tonumber(expected) or -1, rows = {}, row = {} }
end

local function academyIncomingRow()
    if not menu.academyIncoming then menu.academyIncoming = { expected = -1, rows = {}, row = {} } end
    return menu.academyIncoming.row
end

local function academySnapshotID(_, value) academyIncomingRow()[2] = tonumber(value) end
local function academySnapshotName(_, value) academyIncomingRow()[3] = safeText(value, "Unnamed trainee") end
local function academySnapshotOrigin(_, value) academyIncomingRow()[4] = safeText(value, "UNKNOWN STATION") end
local function academySnapshotOriginID(_, value) academyIncomingRow()[5] = safeText(value, "UNKNOWN") end
local function academySnapshotPiloting(_, value) academyIncomingRow()[6] = tonumber(value) end
local function academySnapshotMorale(_, value) academyIncomingRow()[7] = tonumber(value) end
local function academySnapshotSeminar(_, value) academyIncomingRow()[8] = safeText(value, "MAXIMUM PILOTING RANK") end
local function academySnapshotSeminarCount(_, value) academyIncomingRow()[9] = tonumber(value) or 0 end
local function academySnapshotValid(_, value) academyIncomingRow()[10] = value == true or value == 1 or tostring(value) == "true" end
local function academySnapshotTrack(_, value) academyIncomingRow()[11] = safeText(value, "PILOT") end
local function academySnapshotBoarding(_, value) academyIncomingRow()[12] = tonumber(value) end

local function academySnapshotRowCommit()
    local incoming = menu.academyIncoming
    if not incoming then return end
    local row = incoming.row
    row[1] = 1
    if row[2] and row[2] > 0 and row[3] and row[4] and row[5] then incoming.rows[#incoming.rows + 1] = row end
    incoming.row = {}
end

local function academySnapshotComplete()
    local incoming = menu.academyIncoming
    menu.academyIncoming = nil
    if not incoming or incoming.expected < 0 or #incoming.rows ~= incoming.expected then
        DebugError("[FOC][B048][COLLECTION_REJECTED] collection=ACADEMY expected=" .. tostring(incoming and incoming.expected or "NONE") .. " received=" .. tostring(incoming and #incoming.rows or 0) .. " cache=PRESERVED")
        return
    end
    loadAcademyRows(incoming.rows)
    DebugError("[FOC][B048][COLLECTION_COMMIT] collection=ACADEMY rows=" .. tostring(#incoming.rows) .. " cache=REPLACED")
    if menu.frame and not menu.pendingActionKind and menu.plan.lastState ~= "REFRESH_PENDING" then rebuild(false) end
end

local function protectedSnapshotBegin(_, expected)
    menu.protectedIncoming = { expected = tonumber(expected) or -1, rows = {} }
end

local function protectedSnapshotID(_, value)
    if not menu.protectedIncoming then menu.protectedIncoming = { expected = -1, rows = {} } end
    local idcode = safeText(value, "")
    if idcode ~= "" and idcode ~= "UNKNOWN" then menu.protectedIncoming.rows[#menu.protectedIncoming.rows + 1] = idcode end
end

local function protectedSnapshotComplete()
    local incoming = menu.protectedIncoming
    menu.protectedIncoming = nil
    if not incoming or incoming.expected < 0 or #incoming.rows ~= incoming.expected then
        DebugError("[FOC][B048][COLLECTION_REJECTED] collection=PROTECTED expected=" .. tostring(incoming and incoming.expected or "NONE") .. " received=" .. tostring(incoming and #incoming.rows or 0) .. " cache=PRESERVED")
        if menu.plan.lastState == "REFRESH_PENDING" then
            menu.plan.lastState = "BLOCKED"
            menu.plan.lastResult = "REFRESH BLOCKED - PROTECTED SHIP SNAPSHOT WAS INCOMPLETE | PRIOR PROTECTION CACHE PRESERVED"
            menu.notice = menu.plan.lastResult
        end
        if menu.frame and not menu.pendingActionKind then rebuild(false) end
        return
    end
    loadProtectedShipIDs(incoming.rows)
    DebugError("[FOC][B048][COLLECTION_COMMIT] collection=PROTECTED rows=" .. tostring(#incoming.rows) .. " cache=REPLACED")
    if menu.frame then
        sampleFleets("MD_PROTECTION_REFRESH")
        if menu.plan.lastState == "REFRESH_PENDING" then
            menu.notice = "REFRESH COMPLETE - " .. tostring(menu.sample.shipsExamined) .. " SHIPS CHECKED | " .. tostring(#menu.sample.fleets) .. " FLEETS FOUND | " .. tostring(menu.protectedShipCount) .. " QUEST / MISSION SHIP(S) EXCLUDED | " .. tostring(menu.sample.counts.missingCaptains + menu.sample.counts.unknownCaptains) .. " CAPTAIN RECORDS MISSING OR UNKNOWN" .. (menu.sample.capped and " | SAMPLE CAP REACHED" or "")
            menu.plan.lastResult = menu.notice
            menu.plan.lastState = "REFRESH_COMPLETE"
        end
        if not menu.pendingActionKind then rebuild(false) end
    end
end

local function storyOverrideSnapshotBegin(_, expected)
    menu.storyOverrideIncoming = { expected = tonumber(expected) or -1, rows = {} }
end

local function storyOverrideSnapshotID(_, value)
    if not menu.storyOverrideIncoming then menu.storyOverrideIncoming = { expected = -1, rows = {} } end
    local idcode = safeText(value, "")
    if idcode ~= "" and idcode ~= "UNKNOWN" then menu.storyOverrideIncoming.rows[#menu.storyOverrideIncoming.rows + 1] = idcode end
end

local function storyOverrideSnapshotComplete()
    local incoming = menu.storyOverrideIncoming
    menu.storyOverrideIncoming = nil
    if not incoming or incoming.expected < 0 or #incoming.rows ~= incoming.expected then
        DebugError("[FOC][B048][COLLECTION_REJECTED] collection=STORY_OVERRIDES cache=PRESERVED")
        return
    end
    loadStoryOverrideIDs(incoming.rows)
    DebugError("[FOC][B048][COLLECTION_COMMIT] collection=STORY_OVERRIDES rows=" .. tostring(#incoming.rows) .. " cache=REPLACED")
    if menu.frame then sampleFleets("MD_STORY_OVERRIDE_REFRESH"); if not menu.pendingActionKind then rebuild(false) end end
end

function menu.storyAnsweredSnapshotBegin(_, expected)
    menu.storyAnsweredIncoming = { expected = tonumber(expected) or -1, rows = {} }
end

function menu.storyAnsweredSnapshotID(_, value)
    if not menu.storyAnsweredIncoming then menu.storyAnsweredIncoming = { expected = -1, rows = {} } end
    local idcode = safeText(value, "")
    if idcode ~= "" and idcode ~= "UNKNOWN" then menu.storyAnsweredIncoming.rows[#menu.storyAnsweredIncoming.rows + 1] = idcode end
end

function menu.storyAnsweredSnapshotComplete()
    local incoming = menu.storyAnsweredIncoming
    menu.storyAnsweredIncoming = nil
    if not incoming or incoming.expected < 0 or #incoming.rows ~= incoming.expected then
        DebugError("[FOC][B048][COLLECTION_REJECTED] collection=STORY_ANSWERED cache=PRESERVED")
        return
    end
    loadStoryAnsweredIDs(incoming.rows)
    DebugError("[FOC][B048][COLLECTION_COMMIT] collection=STORY_ANSWERED rows=" .. tostring(#incoming.rows) .. " cache=REPLACED")
    if menu.frame then sampleFleets("MD_STORY_ANSWERED_REFRESH"); if not menu.pendingActionKind then rebuild(false) end end
end

local function vacancySnapshotBegin(_, expected)
    menu.vacancyIncoming = { expected = tonumber(expected) or -1, rows = {}, row = {} }
end

local function vacancyIncomingRow()
    if not menu.vacancyIncoming then menu.vacancyIncoming = { expected = -1, rows = {}, row = {} } end
    return menu.vacancyIncoming.row
end

local function vacancySnapshotComponent(_, value) vacancyIncomingRow()[2] = value end
local function vacancySnapshotName(_, value) vacancyIncomingRow()[3] = safeText(value, "Unnamed ship") end
local function vacancySnapshotIDCode(_, value) vacancyIncomingRow()[4] = safeText(value, "UNKNOWN") end
local function vacancySnapshotSector(_, value) vacancyIncomingRow()[5] = safeText(value, "UNKNOWN SECTOR") end

local function vacancySnapshotRowCommit()
    local incoming = menu.vacancyIncoming
    if not incoming then return end
    local row = incoming.row
    row[1] = 1
    if row[2] and row[3] and row[4] and row[4] ~= "UNKNOWN" then incoming.rows[#incoming.rows + 1] = row end
    incoming.row = {}
end

local function vacancySnapshotComplete()
    local incoming = menu.vacancyIncoming
    menu.vacancyIncoming = nil
    if not incoming or incoming.expected < 0 or #incoming.rows ~= incoming.expected then
        DebugError("[FOC][B048][COLLECTION_REJECTED] collection=VACANCY expected=" .. tostring(incoming and incoming.expected or "NONE") .. " received=" .. tostring(incoming and #incoming.rows or 0) .. " cache=PRESERVED")
        return
    end
    loadVacancyRows(incoming.rows)
    DebugError("[FOC][B048][COLLECTION_COMMIT] collection=VACANCY rows=" .. tostring(#incoming.rows) .. " cache=REPLACED identity=NATIVE_COMPONENT")
    if menu.frame and not menu.pendingActionKind and menu.plan.lastState ~= "REFRESH_PENDING" then rebuild(false) end
end

local function marineTargetSnapshotBegin(_, expected)
    menu.marineTargetIncoming = { expected = tonumber(expected) or -1, rows = {}, row = {} }
end

local function marineTargetIncomingRow()
    if not menu.marineTargetIncoming then menu.marineTargetIncoming = { expected = -1, rows = {}, row = {} } end
    return menu.marineTargetIncoming.row
end

local function marineTargetSnapshotComponent(_, value) marineTargetIncomingRow()[2] = value end
local function marineTargetSnapshotName(_, value) marineTargetIncomingRow()[3] = safeText(value, "Unnamed ship") end
local function marineTargetSnapshotIDCode(_, value) marineTargetIncomingRow()[4] = safeText(value, "UNKNOWN") end
local function marineTargetSnapshotSector(_, value) marineTargetIncomingRow()[5] = safeText(value, "UNKNOWN SECTOR") end
local function marineTargetSnapshotRelationship(_, value) marineTargetIncomingRow()[6] = safeText(value, "UNCLASSIFIED") end
local function marineTargetSnapshotPeople(_, value) marineTargetIncomingRow()[7] = tonumber(value) or 0 end
local function marineTargetSnapshotCapacity(_, value) marineTargetIncomingRow()[8] = tonumber(value) or 0 end
local function marineTargetSnapshotMarines(_, value) marineTargetIncomingRow()[9] = tonumber(value) or 0 end

local function marineTargetSnapshotRowCommit()
    local incoming = menu.marineTargetIncoming
    if not incoming then return end
    local row = incoming.row
    row[1] = 1
    if row[2] and row[3] and row[4] and row[4] ~= "UNKNOWN" and row[6] then incoming.rows[#incoming.rows + 1] = row end
    incoming.row = {}
end

local function marineTargetSnapshotComplete()
    local incoming = menu.marineTargetIncoming
    menu.marineTargetIncoming = nil
    if not incoming or incoming.expected < 0 or #incoming.rows ~= incoming.expected then
        DebugError("[FOC][B048][COLLECTION_REJECTED] collection=MARINE_TARGET expected=" .. tostring(incoming and incoming.expected or "NONE") .. " received=" .. tostring(incoming and #incoming.rows or 0) .. " cache=PRESERVED")
        return
    end
    loadMarineTargetRows(incoming.rows)
    DebugError("[FOC][B048][COLLECTION_COMMIT] collection=MARINE_TARGET rows=" .. tostring(#incoming.rows) .. " cache=REPLACED identity=NATIVE_COMPONENT")
    if menu.frame and not menu.pendingActionKind and menu.plan.lastState ~= "REFRESH_PENDING" then rebuild(false) end
end

local function storeSnapshotBegin()
    menu.storeIncoming = { balance = 0, pilot = { 0, 0, 0, 0, 0 }, marine = { 0, 0, 0, 0, 0 } }
end
local function storeSnapshotBalance(_, value)
    if not menu.storeIncoming then storeSnapshotBegin() end
    menu.storeIncoming.balance = tonumber(value) or 0
end
local function storePilotTier(tier, value)
    if not menu.storeIncoming then storeSnapshotBegin() end
    menu.storeIncoming.pilot[tier] = tonumber(value) or 0
end
local function storeMarineTier(tier, value)
    if not menu.storeIncoming then storeSnapshotBegin() end
    menu.storeIncoming.marine[tier] = tonumber(value) or 0
end
local function storeSnapshotComplete()
    if not menu.storeIncoming then return end
    menu.store = menu.storeIncoming
    menu.storeIncoming = nil
    DebugError("[FOC][B048][COLLECTION_COMMIT] collection=ACADEMY_STORE tiers=5 balance=" .. tostring(menu.store.balance))
    if menu.frame and not menu.pendingActionKind then rebuild(false) end
end

local function previewGlobalPlan()
    if FOC_Plan then FOC_Plan.preview(); menu.page = "command"; menu.activeTab = "command"; rebuild(false); return end
    local sample = menu.sample
    local reactionFleetCount = 0
    for _, fleet in ipairs(sample.fleets) do
        local orders = ordersForFleet(fleet)
        if not fleet.missionProtected and (fleet.commander.primarypurpose == "fight" or orders.nonCombatOverride) then
            reactionFleetCount = reactionFleetCount + 1
        end
    end
    local blockerCount = sample.counts.critical + sample.counts.degraded + sample.counts.unknown
    local result = (blockerCount > 0 and "PLAN PREVIEW BLOCKED - " or "PLAN PREVIEW COMPLETE - ") .. tostring(reactionFleetCount) .. " REACTION FLEETS IN SCOPE | " ..
        tostring(sample.counts.ready) .. " READY | " .. tostring(blockerCount) ..
        " BLOCKED OR NEED ATTENTION | " .. tostring(sample.counts.missingCaptains + sample.counts.unknownCaptains) ..
        " CAPTAIN RECORDS MISSING OR UNKNOWN" .. (sample.capped and " | 500-SHIP CAP REACHED" or "") .. " | NO ORDERS SENT"
    menu.previews.global = result
    auditAction("PREVIEW_PLAN", "GLOBAL", result, blockerCount > 0 and "PREVIEW_BLOCKED" or "PREVIEW_COMPLETE")
end

local function previewDispatchPlan(selected, orders)
    local blocked = not selected or selected.missionProtected or (selected.commander.primarypurpose ~= "fight" and not orders.nonCombatOverride)
    local result = blocked and "DISPATCH PREVIEW BLOCKED - QUEST PROTECTION OR NON-COMBAT OVERRIDE REQUIRED | NO ORDER SENT" or "DISPATCH PREVIEW REQUESTED - FOC WILL REQUIRE A FRESH PLAYER-SHIP ATTACK, AN UNCLAIMED ATTACKER, AND A READY FLEET | NO ORDER SENT"
    menu.previews.dispatch = result
    auditAction("PREVIEW_DISPATCH", selected and selected.commander.idcode or "NONE", result, blocked and "PREVIEW_BLOCKED" or "PREVIEW_COMPLETE")
end

local function calculateRenderBudget(total, pageKey, options)
    options = options or {}
    total = math.max(0, tonumber(total) or 0)
    local rowPitch = Helper.scaleY(Helper.standardTextHeight)
    local measured, measuredHeight = pcall(function()
        local fontsize = Helper.scaleFont(Helper.standardFont, Helper.standardFontSize)
        return math.ceil(C.GetTextHeight("Ag", Helper.standardFont, math.floor(fontsize), 0))
    end)
    if measured and type(measuredHeight) == "number" then
        rowPitch = math.max(rowPitch, Helper.scaleY(Helper.standardTextOffsety) + measuredHeight)
    end
    rowPitch = math.max(1, rowPitch + Helper.borderSize)
    local fixedRows = math.max(0, tonumber(options.fixedRows) or 0)
    local rowUnits = math.max(1, tonumber(options.rowUnits) or 1)
    local viewportPixels = tonumber(options.contentPixels) or tonumber(menu.listContentHeight) or Helper.scaleY(config.maxHeight)
    local viewportCapacity = math.max(1, math.floor(viewportPixels / rowPitch) - fixedRows)
    local poolCapacity = math.max(1, (ROW_POOL_LIMIT - ROW_POOL_RESERVE - FIRST_DRAW_LIMBO_ROWS) - fixedRows)
    local pageSize = math.max(1, math.floor(math.min(viewportCapacity, poolCapacity) / rowUnits))
    if options.maximum then pageSize = math.min(pageSize, math.max(1, tonumber(options.maximum) or pageSize)) end
    local pageCount = math.max(1, math.ceil(total / pageSize))
    local page = clamp(tonumber(menu.listPages[pageKey]) or 1, 1, pageCount)
    menu.listPages[pageKey] = page
    return pageSize, pageCount, page, viewportCapacity, poolCapacity
end

function menu.shipyardRowUnits(captions)
    local width=tonumber(menu.listContentWidth)
    if not width or width<=0 or type(captions)~='table' then return nil end
    local ok,units,fits=pcall(function()
        local font=Helper.standardFont
        local size=math.floor(Helper.scaleFont(font,Helper.standardFontSize))
        local offset=Helper.scaleY(Helper.standardTextOffsety)
        -- Same base pitch as calculateRenderBudget; charge the tallest actual
        -- caption conservatively for every row, including buttons/dropdowns.
        local pitch=math.max(Helper.scaleY(Helper.standardTextHeight),offset+math.ceil(C.GetTextHeight('Ag',font,size,0)))+Helper.borderSize
        local height=math.max(pitch,Helper.scaleY(Helper.standardButtonHeight)+Helper.borderSize)
        for _,c in ipairs(captions) do
            local left=C.GetTextHeight(tostring(c[1]),font,size,math.floor(width*0.20))
            local right=C.GetTextHeight(tostring(c[2]),font,size,math.floor(width*0.65))
            height=math.max(height,offset+math.max(left,right)+Helper.borderSize)
        end
        local charged=math.max(1,math.ceil(height/math.max(1,pitch)))
        local pixels=tonumber(menu.listContentHeight)
        return charged,pixels and (charged+8)*pitch<=pixels and charged+8<=ROW_POOL_LIMIT-ROW_POOL_RESERVE-FIRST_DRAW_LIMBO_ROWS or false
    end)
    if ok and type(units)=='number' and units==units then return units,fits end
end

function menu.npcReviewFits(count, captions)
    if type(captions) ~= 'table' or #captions ~= count or count > 14 then return false end
    local width,height = tonumber(menu.listContentWidth),tonumber(menu.listContentHeight)
    if not width or not height or width <= 0 or height <= 0 then return false end
    local ok,required = pcall(function()
        local font = Helper.standardFont
        local size = math.floor(Helper.scaleFont(font,Helper.standardFontSize))
        local offset = Helper.scaleY(Helper.standardTextOffsety)
        local pitch = math.max(Helper.scaleY(Helper.standardButtonHeight),Helper.scaleY(Helper.standardTextHeight),offset + C.GetTextHeight('Ag',font,size,0)) + Helper.borderSize
        -- NPC omits pageGuide. Reserve eight rows for section/selector/evidence,
        -- title/navigation siblings, spacing and first-draw measurement margin.
        local pixels = 8 * pitch
        for _,caption in ipairs(captions) do
            local left = C.GetTextHeight(caption[1],font,size,math.floor(width * 0.20))
            local right = C.GetTextHeight(caption[2],font,size,math.floor(width * 0.65))
            pixels = pixels + math.max(pitch,offset + math.max(left,right) + Helper.borderSize)
        end
        return pixels
    end)
    return ok and type(required)=='number' and required==required and required <= height and count + 8 <= ROW_POOL_LIMIT - ROW_POOL_RESERVE - FIRST_DRAW_LIMBO_ROWS
end

local function renderSlice(total, pageKey, options)
    local pageSize, pageCount, page = calculateRenderBudget(total, pageKey, options)
    local first = (page - 1) * pageSize + 1
    local last = math.min(total, first + pageSize - 1)
    return first, last, page, pageCount, pageSize
end

rebuild = function(resetScroll)
    if menu.recoveryDropdown then
        menu.deferredRedraw = true
        menu.deferredResetScroll = menu.deferredResetScroll or resetScroll
        return
    end
    if resetScroll then menu.restoreTopRow = nil end
    menu.refresh()
end

local function addPager(tableWidget, pageKey, total, options)
    local first, last, page, pageCount, pageSize = renderSlice(total, pageKey, options)
    if pageCount > 1 then
        local row = tableWidget:addRow(true, { fixed = true })
        local target=options and options.nextIndex
        local previousLabel=menu.workflowPointersVisible and target and target<first and '-> PREVIOUS' or 'PREVIOUS'
        local nextLabel=menu.workflowPointersVisible and target and target>last and '-> NEXT' or 'NEXT'
        row[1]:createButton({ active = page > 1 }):setText(previousLabel, { halign = "center" })
        row[1].handlers.onClick = function() menu.listPages[pageKey] = math.max(1, page - 1); rebuild(true) end
        row[2]:setColSpan(2):createText("PAGE " .. tostring(page) .. " / " .. tostring(pageCount) .. " | " .. tostring(total) .. " RECORDS", { halign = "center" })
        row[4]:createButton({ active = page < pageCount }):setText(nextLabel, { halign = "center" })
        row[4].handlers.onClick = function() menu.listPages[pageKey] = math.min(pageCount, page + 1); rebuild(true) end
    end
    return first, last, page, pageCount, pageSize
end

local function createHeader(frame, width)
    local titleHeight = Helper.scaleY(42)
    local tabHeight = Helper.scaleY(38)
    local feedbackHeight = Helper.scaleY(Helper.standardTextHeight + 8)
    local headerHeight = titleHeight + tabHeight + feedbackHeight
    local header = frame:addTable(12, { tabOrder = 1, x = Helper.borderSize, y = Helper.borderSize, width = width - 2 * Helper.borderSize, borderEnabled = false })
    local title = header:addRow(true, { fixed = true })
    local screenTitle = menu.page == "fleets" and "FLEET ORDERS" or "PLAN CONTROL"
    local buildLabel = safeText(menu.param and menu.param[4], "FOC Build UNKNOWN"):gsub("^FOC%s+", ""):upper()
    title[1]:setColSpan(9):createText("FLEET OPERATIONS COMMAND  |  " .. buildLabel .. "  |  " .. screenTitle, { font = Helper.headerFont, fontsize = Helper.standardFontSize + 4 })
    title[10]:setColSpan(2):createButton({ active = true, bgColor = pointerActionBackground }):setText(menu.workflowPointersVisible and "CLEAR NEXT-STEP POINTERS" or "SHOW NEXT-STEP POINTERS", { halign = "center" })
    title[10].handlers.onClick = function()
        menu.workflowPointersVisible = not menu.workflowPointersVisible
        menu.notice = menu.workflowPointersVisible and "NEXT-STEP POINTERS ARE NOW SHOWN" or "NEXT-STEP POINTERS ARE NOW HIDDEN"
        menu.plan.lastResult = menu.notice
        menu.plan.lastState = "DISPLAY_UPDATED"
        rebuild(false)
    end
    title[12]:createButton({ active = true }):setText("CLOSE", { halign = "center" })
    title[12].handlers.onClick = function() menu.onCloseElement("close") end
    local tabRow = header:addRow(true, { fixed = true })
    for index, tab in ipairs(tabs) do
        local properties = { active = true }
        if menu.page == tab.id then properties.bgColor = activeTabBackground end
        tabRow[index]:createButton(properties):setText(tab.label, { halign = "center" })
        tabRow[index].handlers.onClick = function()
            if tab.id == "operationsmap" then
                local intel, unlocated = buildOperationsIntel()
                DebugError("[FOC][B050][MAP_HANDOFF] route=FOC_OPERATIONS_MAP helper_slots=0,0 intel=" .. tostring(#intel) .. " pirate=" .. tostring(#menu.mapPirateObservations) .. " patrol=" .. tostring(#menu.mapPatrolTraversals) .. " edges=" .. tostring(#menu.mapGateEdges) .. " unlocated=" .. tostring(unlocated) .. " return=FOC")
                openNativeMenu("FOC_OperationsMap", { 0, 0, intel, unlocated, menu.operationsMap.window, nil, menu.mapPirateObservations, menu.mapPatrolTraversals, menu.mapGateEdges, menu.gameTime, menu.strategicObservations })
                return
            end
            menu.page = tab.id
            menu.activeTab = tab.id
            if tab.id == 'shipyard' and not FOC_Advisor.data and not FOC_Advisor.started then FOC_Advisor.refresh() end
            if tab.id == "taskforces" then AddUITriggeredEvent(menu.name, "strategic_refresh", nil) end
            rebuild(true)
        end
    end
    tabRow[12]:createButton({ active = not menu.pendingActionKind and not menu.carrierTransaction }):setText("REFRESH", { halign = "center" })
    tabRow[12].handlers.onClick = function()
        if menu.pendingActionKind or menu.carrierTransaction then return end
        if menu.page == 'shipyard' then
            if not FOC_Shipyard.busy() then FOC_Advisor.refresh(); FOC_Advisor.ships=nil; FOC_Shipyard.stage='START' end
            rebuild(false);return
        end
        if menu.page == "taskforces" and menu.strategic.view == "COVERAGE AND FLEET TEMPLATES" and not FOC_Advisor.saving then FOC_Advisor.refresh() end
        if menu.page == "taskforces" then
            menu.strategicSnapshotStatus = "REQUESTED"
        else
            menu.notice = "REFRESH REQUESTED - WAITING FOR AUTHORITATIVE MD FLEET AND QUEST-PROTECTION SNAPSHOTS"
            menu.plan.lastResult = menu.notice
            menu.plan.lastState = "REFRESH_PENDING"
        end
        AddUITriggeredEvent(menu.name, "refresh", nil)
        AddUITriggeredEvent(menu.name, "strategic_refresh", nil)
        rebuild(true)
    end
    local feedbackRow = header:addRow(false, { fixed = true })
    local feedback = menu.notice or "READY - CHOOSE AN ACTION"
    if #feedback > 180 then feedback = feedback:sub(1, 177) .. "..." end
    feedbackRow[1]:setColSpan(12):createText("LAST ACTION: " .. feedback, {
        halign = "center",
        color = needsAction(feedback) and warningColor or passColor,
    })
    header.properties.maxVisibleHeight = headerHeight
    return headerHeight
end

local function pageGuide(tableWidget)
    section(tableWidget, "START HERE")
    textRow(tableWidget, "Purpose", guides[menu.page], headingColor)
    textRow(tableWidget, "Authority", menu.plan.authority .. " - preview never mutates; apply routes require approval, revalidation, readback, and bounded authority.", passColor)
    if menu.notice then textRow(tableWidget, "Last action", menu.notice, needsAction(menu.notice) and warningColor or passColor) end
end

local function commandPage(tableWidget)
    if not menu.homeAdvanced then
        section(tableWidget,'WHAT WOULD YOU LIKE TO DO?')
        actionRow(tableWidget,'Build','HOW DO I BUILD A NEW TASK FORCE?',function()
            menu.page='shipyard';menu.activeTab='shipyard'
            if not FOC_Advisor.data and not FOC_Advisor.started then FOC_Advisor.refresh() end
            rebuild(true)
        end,true,passColor)
        actionRow(tableWidget,'Assign','HOW DO I GIVE A FLEET A HOME AND MISSION?',function() menu.page='fleets';menu.activeTab='fleets';rebuild(true) end,true,passColor)
        actionRow(tableWidget,'Maintain','WHICH SHIPS NEED ATTENTION?',function() menu.page='readiness';menu.activeTab='readiness';rebuild(true) end,true,passColor)
        actionRow(tableWidget,'Command','REVIEW AUTOMATION AND FLEET STATUS',function() menu.homeAdvanced=true;rebuild(true) end,true,headingColor)
        return
    end
    actionRow(tableWidget,'Home','BACK TO HOME QUESTIONS',function() menu.homeAdvanced=false;rebuild(true) end,true,passColor)
    local sample = menu.sample
    section(tableWidget, "FLEET STATUS")
    textRow(tableWidget, "Known fleet commanders", tostring(#sample.fleets))
    textRow(tableWidget, "Critical / degraded", tostring(sample.counts.critical) .. " / " .. tostring(sample.counts.degraded), (sample.counts.critical > 0 and criticalColor or warningColor))
    textRow(tableWidget, "Sampled ships with no captain", tostring(sample.counts.missingCaptains), sample.counts.missingCaptains > 0 and criticalColor or passColor)
    textRow(tableWidget, "Damaged subordinate ships", tostring(sample.counts.damaged), sample.counts.damaged > 0 and warningColor or passColor)
    section(tableWidget, "FLEETS NEEDING ATTENTION")
    local attention = {}
    for _, fleet in ipairs(sample.fleets) do
        if fleet.status ~= "READY" then table.insert(attention, fleet) end
    end
    local commandGuidanceRows = (menu.plan.lastState == "ACTION_REQUIRED_MODE" or menu.plan.lastState == "ACTION_REQUIRED_NATIVE" or menu.plan.lastState == "PLAN_PARTIAL" or menu.plan.lastState == "BLOCKED") and 6 or 0
    -- The exact order preview owns the only variable list on this page.
    -- Do not spend the viewport twice on attention rows and preview rows.
    local first, last = 1, 0
    if not FOC_Plan then
        first, last = addPager(tableWidget, "command.attention", #attention, { fixedRows = 22 + commandGuidanceRows, contentPixels = menu.listContentHeight, maximum = 20 })
    elseif #attention > 0 then
        textRow(tableWidget, "Needs attention", tostring(#attention) .. " fleets. Preview below for each fleet's reason, or inspect it in Fleets.", warningColor)
    end
    for index = first, last do
        local fleet = attention[index]
        if fleet then
            local row = tableWidget:addRow(true)
            row[1]:createText(fleet.status, { color = statusColor(fleet.status) })
            row[2]:createText(fleet.commander.fleetname)
            row[3]:createText(fleet.commander.name .. " [" .. fleet.commander.idcode .. "]")
            row[4]:createText(fleet.reason, { wordwrap = true })
        end
    end
    if #attention == 0 then textRow(tableWidget, "Result", "No first-rollout blocker was observed in the bounded sample.", passColor) end
    section(tableWidget, "COMMAND AUTOMATION")
    dropdownRow(tableWidget, "Mode", automationModes, menu.plan.authority, function(value)
        menu.plan.authority = tostring(value)
        menu.plan.status = "DRAFT"
        auditAction("MODE_CHANGE", "GLOBAL", "MASTER MODE CHANGED TO " .. menu.plan.authority .. " - NO PLAN WAS APPLIED", "AUTHORITY_CHANGED")
        return false
    end)
    local authorityMeaning = menu.plan.authority == "PREVIEW PLAN" and "PREVIEW ONLY - NO ORDERS CAN BE SENT."
        or menu.plan.authority == "APPLY APPROVED PLAN" and "ARMED - NO ORDERS SENT YET. Press the Apply button below to send eligible saved and unlocked fleet orders."
        or "FULL AUTOMATION AUTHORIZED - eligible orders may be sent by the bounded scheduler."
    textRow(tableWidget, "Authority", authorityMeaning, menu.plan.authority == "PREVIEW PLAN" and warningColor or passColor)
    if FOC_Plan then
        FOC_Plan.onChange = function()
            menu.planRedraw = true
            if menu.page == "command" then menu.notice = FOC_Plan.message; menu.plan.lastResult = menu.notice end
        end
        FOC_Plan.draw(tableWidget, textRow, actionRow, dropdownRow, addPager, passColor, warningColor, neutralColor, menu.plan.authority ~= "PREVIEW PLAN")
        actionRow(tableWidget, "Emergency", "STOP FOC AUTOMATION", function() menu.plan.authority = "PREVIEW PLAN"; auditAction("STOP_AUTOMATION", "GLOBAL", "FOC AUTOMATION STOP REQUESTED", "STOPPED") end, true, warningColor)
        return
    end
    textRow(tableWidget, "Current result", menu.plan.lastResult, needsAction(menu.plan.lastResult) and warningColor or passColor)
    actionRow(tableWidget, "Plan", "PREVIEW CURRENT PLAN", previewGlobalPlan, true, headingColor)
    actionRow(tableWidget, "Send orders", "APPLY APPROVED PLAN - SEND ORDERS", function()
        if menu.plan.authority == "PREVIEW PLAN" then
            menu.plan.lastResult = "PLAN NOT APPLIED - PREVIEW MODE DOES NOT ALLOW CHANGES. NOTHING CHANGED."
            menu.plan.lastState = "ACTION_REQUIRED_MODE"
            rebuild(false)
        else
            auditAction("APPLY_APPROVED_PLAN", "GLOBAL_BOUNDED", "ORDER REQUEST SENT - WAITING FOR X4 TO CONFIRM THE ORDER IS ACTIVE", "APPLY_PENDING")
        end
    end, true, warningColor)
    if menu.plan.lastState == "ACTION_REQUIRED_MODE" then
        actionRequired(tableWidget,
            "FOC kept the plan in preview and did not apply it.",
            "The current mode allows planning only, so X4 changes are not authorized.",
            "Open Settings, choose APPLY APPROVED PLAN, return to Command, then press APPLY APPROVED PLAN - SEND ORDERS.",
            "settings", "OPEN SETTINGS")
    elseif menu.plan.lastState == "PLAN_PARTIAL" then
        actionRequired(tableWidget,
            "FOC confirmed at least one active fleet order, but another order was blocked or remained inactive.",
            "An assigned default behavior is not counted as dispatched unless X4 also makes it the fleet's current order.",
            "Open Activity to see the named fleet and exact active, blocked, assigned-but-inactive, and locked-skipped counts.",
            "activity", "OPEN ACTIVITY",
            "Only fleets reported ACTIVE are confirmed dispatched. An ASSIGNED BUT INACTIVE fleet is not moving under the planned order.")
    elseif menu.plan.lastState == "ACTION_REQUIRED_NATIVE" or menu.plan.lastState == "BLOCKED" then
        actionRequired(tableWidget,
            "FOC stopped before sending the fleet plan.",
            "At least one required native action or readback could not be proven safe.",
            "Open Activity to see the exact blocker. Correct the named fleet, captain, Home point, lock, or readiness issue, then preview again.",
            "activity", "OPEN ACTIVITY")
    end
    local stopped = menu.plan.status == "STOPPED" and menu.plan.authority == "PREVIEW PLAN" and not (FOCRecovery and (FOCRecovery.policy.repair or FOCRecovery.policy.shelter))
    actionRow(tableWidget, "Emergency", stopped and "FOC AUTOMATION ALREADY STOPPED" or "STOP FOC AUTOMATION", function() menu.plan.authority = "PREVIEW PLAN"; menu.plan.status = "STOPPED"; auditAction("STOP_AUTOMATION", "GLOBAL", "FOC AUTOMATION STOPPED - PERSISTENT READBACK REQUIRED", "STOPPED") end, not stopped, warningColor)
end

local function fleetSelectorPane(tableWidget)
    section(tableWidget, "CHOOSE A FLEET")
    textRow(tableWidget, "Scope", "Use the alphabetical finder to narrow all structurally eligible combat fleets from authoritative MD discovery.", headingColor)
    dropdownRow(tableWidget, "Fleet finder", fleetFinderOptions, menu.fleetFinder, function(value)
        menu.fleetFinder = tostring(value)
        menu.listPages["fleets.registry"] = 1
    end)
    actionRow(tableWidget, "Fleet tools", menu.fleetMode == "maintenance" and "BACK TO FLEET ORDERS" or "REPAIR / REPLACE / REBUILD", function()
        menu.fleetMode = menu.fleetMode == "maintenance" and "orders" or "maintenance"
        menu.maintenance.previewCommanderID = nil
        if menu.fleetMode == "maintenance" then requestMaintenanceSnapshot(menu.sample.fleets[menu.selectedFleet]) else rebuild(true) end
    end, true, menu.fleetMode == "maintenance" and passColor or headingColor)
    actionRow(tableWidget, "Safety", menu.fleetMode == "thresholds" and "BACK TO FLEET ORDERS" or "REPAIR THRESHOLDS / RESPONSE CAP", function()
        menu.fleetMode = menu.fleetMode == "thresholds" and "orders" or "thresholds"
        rebuild(true)
    end, true, menu.fleetMode == "thresholds" and passColor or warningColor)
    local visibleFleets = {}
    for index, fleet in ipairs(menu.sample.fleets) do
        local name = tostring(fleet.commander.fleetname or ""):upper()
        local firstLetter = name:sub(1, 1)
        local finderMatch = menu.fleetFinder == "ALL FLEETS"
            or (menu.fleetFinder == "A-F" and firstLetter >= "A" and firstLetter <= "F")
            or (menu.fleetFinder == "G-L" and firstLetter >= "G" and firstLetter <= "L")
            or (menu.fleetFinder == "M-R" and firstLetter >= "M" and firstLetter <= "R")
            or (menu.fleetFinder == "S-Z" and firstLetter >= "S" and firstLetter <= "Z")
        if finderMatch and (menu.showNonCombat or fleet.commander.primarypurpose == "fight") then table.insert(visibleFleets, { index = index, fleet = fleet }) end
    end
    table.sort(visibleFleets, function(a, b)
        local an = tostring(a.fleet.commander.fleetname or ""):upper()
        local bn = tostring(b.fleet.commander.fleetname or ""):upper()
        if an ~= bn then return an < bn end
        return tostring(a.fleet.commander.idcode or "") < tostring(b.fleet.commander.idcode or "")
    end)
    if #visibleFleets == 0 then textRow(tableWidget, "Finder result", "NO FLEETS MATCH " .. menu.fleetFinder .. " - CHOOSE ALL FLEETS OR ANOTHER LETTER RANGE", warningColor) end
    if not menu.showNonCombat and menu.sample.fleets[menu.selectedFleet] and menu.sample.fleets[menu.selectedFleet].commander.primarypurpose ~= "fight" and visibleFleets[1] then menu.selectedFleet = visibleFleets[1].index end
    local selectedVisible = false
    for _, entry in ipairs(visibleFleets) do if entry.index == menu.selectedFleet then selectedVisible = true; break end end
    if not selectedVisible and visibleFleets[1] then menu.selectedFleet = visibleFleets[1].index end
    local first, last, _, pageCount = addPager(tableWidget, "fleets.registry", #visibleFleets, { fixedRows = 8, contentPixels = menu.listContentHeight, maximum = 16 })
    local selectedRow = nil
    local rowsBeforeFleets = 5 + (pageCount > 1 and 1 or 0)
    for visibleIndex = first, last do
        local entry = visibleFleets[visibleIndex]
        local fleet = entry and entry.fleet
        local index = entry and entry.index
        if fleet and index then
            local row = tableWidget:addRow(true)
            local buttonProperties = { active = true }
            local selectedMark = ""
            if index == menu.selectedFleet then
                buttonProperties.bgColor = activeTabBackground
                selectedMark = "  |  SELECTED"
            end
            row[1]:setColSpan(4):createButton(buttonProperties):setText(
                fleet.commander.fleetname .. "  |  " .. fleet.commander.sector .. selectedMark,
                { halign = "left" }
            )
            row[1].handlers.onClick = function()
                menu.selectedFleet = index
                menu.maintenance.previewCommanderID = nil
                if menu.fleetMode == "maintenance" then requestMaintenanceSnapshot(fleet) else rebuild(true) end
            end
            if index == menu.selectedFleet then selectedRow = rowsBeforeFleets + (visibleIndex - first + 1) end
        end
    end
    if selectedRow then pcall(tableWidget.setSelectedRow, tableWidget, selectedRow) end
end

local function taskForcesLegacyPage(tableWidget)
    section(tableWidget, "GROUP FLEETS FOR DEFENSE")
    actionRow(tableWidget, "All Fleets", "GIVE ALL SAVED FOC FLEETS THE SAME ORDER", function()
        if not FOC_Plan or FOC_Plan.pending then return end
        FOC_Plan.mode = "PATROL"; FOC_Plan.token = 0; FOC_Plan.rows = {}
        FOC_Plan.message = "Preview the common order before sending. Nothing has moved."
        menu.page = "command"; menu.activeTab = "command"; rebuild(true)
    end, FOC_Plan and not FOC_Plan.pending, headingColor)
    textRow(tableWidget, "What is a Task Force?", "A group of existing fleets that share a defense plan. Ships stay in their own fleets. Set each fleet's Home in the Fleets tab.", passColor)
    textRow(tableWidget, "Capacity", tostring(#menu.taskForces) .. " / 8 TASK FORCES", #menu.taskForces < 8 and neutralColor or warningColor)
    local usedNames, nextName = {}, nil
    for _, force in ipairs(menu.taskForces) do usedNames[tostring(force[2] or "")] = true end
    for _, name in ipairs(taskForceNames) do if not usedNames[name] then nextName = name; break end end
    actionRow(tableWidget, "Create", nextName and "CREATE " .. nextName or "LIMIT REACHED - 8 UNIQUE TASK FORCES", function()
        auditAction("TASK_FORCE_CREATE", nextName, "CREATION REQUEST SENT - SAVE READBACK REQUIRED", "TASK_FORCE_PENDING")
    end, nextName ~= nil and #menu.taskForces < 8 and not menu.pendingActionKind, headingColor)
    if #menu.taskForces == 0 then
        textRow(tableWidget, "Start here", "Create a group, then add the fleets you want to coordinate. Configure individual fleets in the Fleets tab first.", warningColor)
        return
    end
    menu.taskForce.selected = clamp(menu.taskForce.selected, 1, #menu.taskForces)
    local labels = {}
    for index, force in ipairs(menu.taskForces) do labels[index] = tostring(force[2]) .. " [" .. tostring(force[1]) .. "]" end
    dropdownRow(tableWidget, "Task Force", labels, labels[menu.taskForce.selected], function(value)
        for index, label in ipairs(labels) do if label == value then menu.taskForce.selected = index; rebuild(false); return end end
    end)
    local force = menu.taskForces[menu.taskForce.selected]
    local members = type(force[9]) == "table" and force[9] or {}
    menu.taskForce.name = tostring(force[2] or taskForceNames[menu.taskForce.selected])
    menu.taskForce.priority = tostring(force[3] or "NORMAL")
    menu.taskForce.zone = tostring(force[4] or "NORMAL")
    menu.taskForce.coverage = normalizeCoverage(force[5])
    menu.taskForce.rotation = tostring(force[6] or "MANUAL")
    section(tableWidget, "DEFENSE PLAN")
    dropdownRow(tableWidget, "Name", taskForceNames, menu.taskForce.name, function(value) menu.taskForce.name = tostring(value); return false end)
    dropdownRow(tableWidget, "Response priority", taskForcePriorities, menu.taskForce.priority, function(value) menu.taskForce.priority = tostring(value); return false end)
    dropdownRow(tableWidget, "Home defense priority", taskForcePriorities, menu.taskForce.zone, function(value) menu.taskForce.zone = tostring(value); return false end)
    dropdownRow(tableWidget, "Response range", coverageRanges, menu.taskForce.coverage, function(value) menu.taskForce.coverage = normalizeCoverage(value); return false end)
    textRow(tableWidget, "Home defense choices", "NORMAL: standard priority. HIGH: higher priority. EXCLUDED: no response in member Home sectors. This does not choose a Home location.", neutralColor)
    actionRow(tableWidget, "Save plan", "SAVE TASK FORCE DEFENSE PLAN", function()
        auditAction("TASK_FORCE_SAVE", tostring(force[1]), "DEFENSE PLAN SAVE REQUESTED - PERSISTENT READBACK REQUIRED", "TASK_FORCE_PENDING", { menu.taskForce.name, menu.taskForce.priority, menu.taskForce.zone, menu.taskForce.coverage, menu.taskForce.rotation })
    end, not menu.pendingActionKind, passColor)
    section(tableWidget, "MEMBER FLEETS")
    local fleetLabels, fleetIDs = {}, {}
    for index, fleet in ipairs(menu.sample and menu.sample.fleets or {}) do
        fleetLabels[index] = fleet.commander.fleetname .. " [" .. fleet.commander.idcode .. "] | " .. safeText(fleet.commander.order, "UNKNOWN") .. " | " .. safeText(fleet.commander.assignment, "UNKNOWN") .. " | " .. safeText(fleet.commander.sector, "UNKNOWN")
        fleetIDs[index] = fleet.commander.idcode
    end
    menu.taskForce.fleetChoice = clamp(menu.taskForce.fleetChoice, 1, math.max(1, #fleetLabels))
    if #fleetLabels > 0 then
        dropdownRow(tableWidget, "Fleet to add", fleetLabels, fleetLabels[menu.taskForce.fleetChoice], function(value)
            for index, label in ipairs(fleetLabels) do if label == value then menu.taskForce.fleetChoice = index; return end end
        end)
        actionRow(tableWidget, "Membership", "ADD SELECTED FLEET TO THIS TASK FORCE", function()
            auditAction("TASK_FORCE_ADD", tostring(force[1]), "MEMBERSHIP REQUEST SENT - UNIQUE STABLE-ID READBACK REQUIRED", "TASK_FORCE_PENDING", fleetIDs[menu.taskForce.fleetChoice])
        end, #members < 100 and not menu.pendingActionKind, headingColor)
    else
        textRow(tableWidget, "Proven fleet", "NO CURRENT STRUCTURALLY PROVEN FLEET", warningColor)
    end
    textRow(tableWidget, "Fleets in this group", #members > 0 and (tostring(#members) .. " FLEETS") or "NO FLEETS ADDED YET", #members > 0 and neutralColor or warningColor)
    local function memberLabel(id)
        if not id or id == "" then return "NOT CHOSEN" end
        for _, fleet in ipairs(menu.sample and menu.sample.fleets or {}) do
            if fleet.commander.idcode == id then return fleet.commander.fleetname .. " [" .. id .. "]" end
        end
        return tostring(id) .. " (not found in current fleet list)"
    end
    if #members > 0 then
        menu.taskForce.memberChoice = clamp(menu.taskForce.memberChoice, 1, #members)
        local memberLabels = {}
        for index, id in ipairs(members) do memberLabels[index] = memberLabel(id) end
        dropdownRow(tableWidget, "Fleet in this group", memberLabels, memberLabels[menu.taskForce.memberChoice], function(value)
            for index, label in ipairs(memberLabels) do if label == value then menu.taskForce.memberChoice = index; return end end
        end)
        local chosen = members[menu.taskForce.memberChoice]
        local chosenFleet = nil
        for _, fleet in ipairs(menu.sample and menu.sample.fleets or {}) do
            if fleet.commander.idcode == chosen then chosenFleet = fleet; break end
        end
        if chosenFleet then
            textRow(tableWidget, "Commander evidence", chosenFleet.commander.name .. " [" .. chosen .. "] | CAPTAIN " .. chosenFleet.commander.captainState .. " | HULL " .. percent(chosenFleet.commander.hull) .. " | " .. tostring(chosenFleet.missingCaptains) .. " SUBORDINATE CAPTAIN VACANCY/VACANCIES", chosenFleet.commander.captainState == "PRESENT" and neutralColor or warningColor)
        else
            textRow(tableWidget, "Commander evidence", "SAVED MEMBER IS NOT IN THE CURRENT STRUCTURAL FLEET SNAPSHOT - NO MUTATION IS AUTHORIZED", warningColor)
        end
        actionRow(tableWidget, "Remove", "REMOVE SELECTED MEMBER FROM THIS TASK FORCE", function()
            auditAction("TASK_FORCE_REMOVE", tostring(force[1]), "MEMBER REMOVAL REQUESTED", "TASK_FORCE_PENDING", chosen)
        end, not menu.pendingActionKind, warningColor)
    end
    textRow(tableWidget, "What saving does", "Saves this group's defense settings. It does not send ships anywhere. Fleet orders and maintenance stay in the Fleets tab.", neutralColor)
end

function menu.strategicAction(kind, subject, data)
    if menu.pendingActionKind then return end
    menu.pendingActionKind = kind
    menu.notice = kind .. " RECEIVED - WAITING FOR EXACT NATIVE/PERSISTENT READBACK"
    menu.plan.lastState = "STRATEGIC_PENDING"
    menu.plan.lastResult = menu.notice
    AddUITriggeredEvent(menu.name, "strategic_action", { kind, tostring(subject or "NONE"), data or {}, menu.plan.authority, getElapsedTime() })
    rebuild(false)
end

function menu.strategicFleet(index)
    return menu.sample and menu.sample.fleets and menu.sample.fleets[index] or nil
end

function menu.carrierDraftKey(subject, group)
    return tostring(subject) .. ":" .. tostring(group)
end

function menu.savedCarrierWing(subject, group)
    if menu.carrierWingEvidenceValid ~= true then return nil, "UNKNOWN - REFRESH SAVED WING EVIDENCE" end
    for _, row in ipairs(menu.strategicRecords.carrierwings or {}) do
        if row[2] == subject and row[3] == group then return row, "SAVED" end
    end
    return nil, "NO SAVED PROFILE FOR THIS GROUP"
end

function menu.carrierEditor(subject, group)
    local saved, status = menu.savedCarrierWing(subject, group)
    local key = menu.carrierDraftKey(subject, group)
    menu.carrierDrafts = menu.carrierDrafts or {}
    local draft = menu.carrierDrafts[key]
    if not draft then
        local count = 0
        for _ in pairs(menu.carrierDrafts) do count = count + 1 end
        if count >= 100 then return nil, saved, "100 DRAFT LIMIT - NO NEW EDITOR OPENED" end
        draft = { role = "INTERCEPTOR", damage = 70, dirty = false }
        menu.carrierDrafts[key] = draft
    end
    if not draft.dirty and not menu.carrierTransaction then
        if saved then draft.role, draft.damage = saved[4], saved[5]
        elseif menu.carrierWingEvidenceValid == true then draft.role, draft.damage = "INTERCEPTOR", 70 end
    end
    menu.strategic.wingRole, menu.strategic.damageHull = draft.role, draft.damage
    local signature = status .. ":" .. tostring(saved and saved[5]) .. ":" .. draft.role .. ":" .. tostring(draft.damage) .. ":" .. tostring(draft.dirty)
    if draft.logged ~= signature then
        draft.logged = signature
        DebugError("[FOC][B058][CARRIER_EDITOR] subject=" .. tostring(subject) .. " group=" .. tostring(group) .. " saved_role=" .. tostring(saved and saved[4] or "UNKNOWN") .. " saved_recall=" .. tostring(saved and saved[5] or "UNKNOWN") .. " draft_recall=" .. tostring(draft.damage) .. " dirty=" .. tostring(draft.dirty) .. " status=" .. status)
    end
    return draft, saved, status
end

function menu.requestCarrierProfile(selected, group, role, damage)
    if menu.pendingActionKind or menu.carrierTransaction then return end
    local commander = selected and selected.commander and bridgeComponent64(selected.commander.object)
    local luaid = commander and componentLuaID(commander)
    if not luaid then rejectLocal("CARRIER BLOCKED - EXACT COMPONENT IS NO LONGER VALID"); return end
    menu.carrierTransactionCounter = (menu.carrierTransactionCounter or 0) + 1
    local token = tostring(getElapsedTime()) .. ":" .. tostring(menu.carrierTransactionCounter)
    menu.carrierTransaction = { token = token, component = commander, luaid = luaid, subject = selected.commander.idcode, group = group, role = role, damage = damage, phase = "PREFLIGHT" }
    menu.strategicAction("CARRIER_PROFILE_PREFLIGHT", selected.commander.idcode, { group, role, damage, "PREFLIGHT", luaid, token })
end

function menu.carrierReplyValue(field, value)
    menu.carrierReply = menu.carrierReply or {}
    menu.carrierReply[field] = value
end

function menu.carrierGroupSignature(commander, group)
    local members = {}
    local subordinates = directSubordinates(commander)
    if #subordinates > 500 then return nil end
    for _, member in ipairs(subordinates) do
        if tonumber(GetComponentData(member, "subordinategroup")) == group then members[#members + 1] = tostring(member) end
    end
    table.sort(members)
    return table.concat(members, ":")
end

function menu.rollbackCarrier(transaction)
    local saved = transaction.rollback
    if not saved then return "NOT NEEDED - NO NATIVE WRITE" end
    local commander = bridgeComponent64(saved.commander)
    if not commander or GetComponentData(commander, "isplayerowned") ~= true then return "BLOCKED - CARRIER NO LONGER VALID/OWNED" end
    if menu.carrierGroupSignature(commander, saved.group) ~= saved.members then return "BLOCKED - GROUP MEMBERSHIP CHANGED; NEWER HIERARCHY PRESERVED" end
    local assignment = ffi.string(C.GetSubordinateGroupAssignment(commander, saved.group))
    local dock = C.ShouldSubordinateGroupDockAtCommander(commander, saved.group)
    local resupply = C.ShouldSubordinateGroupResupplyAtFleet(commander, saved.group)
    if assignment == saved.assignment and dock == saved.dock and resupply == saved.resupply then return "CONFIRMED" end
    if assignment ~= saved.expectedassignment or dock ~= saved.expecteddock or resupply ~= true then
        return "BLOCKED - GROUP CHANGED AFTER REQUEST; NEWER SETTINGS PRESERVED"
    end
    C.SetSubordinateGroupAssignment(commander, saved.group, saved.assignment)
    C.SetSubordinateGroupDockAtCommander(commander, saved.group, saved.dock)
    C.SetSubordinateGroupResupplyAtFleet(commander, saved.group, saved.resupply)
    local restored = ffi.string(C.GetSubordinateGroupAssignment(commander, saved.group)) == saved.assignment
        and C.ShouldSubordinateGroupDockAtCommander(commander, saved.group) == saved.dock
        and C.ShouldSubordinateGroupResupplyAtFleet(commander, saved.group) == saved.resupply
    return restored and "CONFIRMED" or "FAILED - NATIVE READBACK MISMATCH"
end

function menu.carrierReplyComplete()
    local reply, transaction = menu.carrierReply, menu.carrierTransaction
    menu.carrierReply = nil
    if not reply or not transaction or tostring(reply.token or "") ~= transaction.token then return end
    local state = (reply.state ~= nil and reply.result ~= nil) and tostring(reply.state) or "BLOCKED"
    local result = tostring(reply.result or "CARRIER RESPONSE INCOMPLETE")
    if state == "CARRIER_PREFLIGHT_READY" and transaction.phase == "PREFLIGHT" then
        if not menu.frame or (menu.plan.authority ~= "APPLY APPROVED PLAN" and menu.plan.authority ~= "FULL AUTOMATION") then
            state, result = "BLOCKED", "CARRIER BLOCKED - MENU CLOSED OR AUTHORITY CHANGED AFTER PREFLIGHT | NOTHING CHANGED"
        else
            sampleFleets("CARRIER PREFLIGHT REVALIDATION")
            local current
            for _, fleet in ipairs(menu.sample.fleets or {}) do
                local component = fleet.commander and bridgeComponent64(fleet.commander.object)
                if component and tostring(component) == tostring(transaction.component) then current = fleet; break end
            end
            transaction.phase = "NATIVE"
            local called, ok, detail = pcall(menu.applyWingGroup, current, transaction.group, transaction.role)
            if called and ok then
                transaction.phase = "SAVE"
                menu.pendingActionKind = nil
                menu.strategicAction("CARRIER_PROFILE_SAVE", transaction.subject, { transaction.group, transaction.role, transaction.damage, "CONFIRMED", transaction.luaid, transaction.token })
                return
            end
            state, result = "BLOCKED", called and tostring(detail) or "CARRIER NATIVE CALL FAILED"
        end
    elseif state == "CARRIER_PREFLIGHT_READY" then
        return
    elseif transaction.phase == "PREFLIGHT" and state == "CARRIER_PROFILE_SAVED" then
        return
    end
    if state ~= "CARRIER_PROFILE_SAVED" and transaction.rollback then
        local ok, rollback = pcall(menu.rollbackCarrier, transaction)
        result = result .. " | ROLLBACK " .. (ok and tostring(rollback) or "UNKNOWN - NATIVE CALL FAILED")
    end
    if state == "CARRIER_PROFILE_SAVED" and menu.carrierDrafts then
        local draft = menu.carrierDrafts[menu.carrierDraftKey(transaction.subject, transaction.group)]
        if draft and draft.damage == transaction.damage and draft.role == transaction.role then
            draft.role, draft.damage, draft.dirty = transaction.role, transaction.damage, false
        end
    end
    menu.carrierTransaction = nil
    menu.pendingActionKind = nil
    menu.plan.lastState, menu.plan.lastResult, menu.notice = state, result, result
    DebugError("[FOC][B058][CARRIER_RESULT] token=" .. transaction.token .. " subject=" .. tostring(transaction.subject) .. " state=" .. state .. " result=" .. result)
    if menu.frame then sampleFleets("CARRIER FINAL READBACK"); rebuild(false) end
end

function menu.applyWingGroup(selected, group, role)
    local assignment = wingAssignments[role]
    local commander, groups = fleetSubordinateGroups(selected)
    local validgroup = false
    for _, value in ipairs(groups) do if value == group then validgroup = true; break end end
    if not commander or not validgroup or not assignment or not selected or selected.missionProtected or selected.commander.playerOccupied or GetComponentData(commander, "isplayerowned") ~= true or GetComponentData(commander, "shiptype") ~= "carrier" then
        return false, "BLOCKED - CARRIER/GROUP OWNERSHIP, PROTECTION, OR PLAYER-CONTROL GUARD FAILED"
    end
    local oldassignment = ffi.string(C.GetSubordinateGroupAssignment(commander, group))
    local olddock = C.ShouldSubordinateGroupDockAtCommander(commander, group)
    local oldresupply = C.ShouldSubordinateGroupResupplyAtFleet(commander, group)
    local wantdock = role == "RESERVE"
    local signature = menu.carrierGroupSignature(commander, group)
    if not signature or signature == "" then return false, "BLOCKED - GROUP EMPTY OR CARRIER EXCEEDS 500 DIRECT-MEMBER SAFETY BOUND" end
    if menu.carrierTransaction then
        menu.carrierTransaction.rollback = { commander = commander, group = group, assignment = oldassignment, dock = olddock, resupply = oldresupply, expectedassignment = assignment, expecteddock = wantdock, members = signature }
    end
    C.SetSubordinateGroupAssignment(commander, group, assignment)
    C.SetSubordinateGroupResupplyAtFleet(commander, group, true)
    C.SetSubordinateGroupDockAtCommander(commander, group, wantdock)
    local newassignment = ffi.string(C.GetSubordinateGroupAssignment(commander, group))
    local newdock = C.ShouldSubordinateGroupDockAtCommander(commander, group)
    local newresupply = C.ShouldSubordinateGroupResupplyAtFleet(commander, group)
    if newassignment ~= assignment or newdock ~= wantdock or newresupply ~= true then
        C.SetSubordinateGroupAssignment(commander, group, oldassignment)
        C.SetSubordinateGroupResupplyAtFleet(commander, group, oldresupply)
        C.SetSubordinateGroupDockAtCommander(commander, group, olddock)
        local restored = ffi.string(C.GetSubordinateGroupAssignment(commander, group)) == oldassignment and C.ShouldSubordinateGroupDockAtCommander(commander, group) == olddock and C.ShouldSubordinateGroupResupplyAtFleet(commander, group) == oldresupply
        return false, "BLOCKED - NATIVE WING READBACK FAILED | ROLLBACK " .. (restored and "CONFIRMED" or "UNKNOWN")
    end
    return true, "NATIVE WING ROLE CONFIRMED - GROUP " .. tostring(group) .. " | " .. role .. " | ASSIGNMENT " .. assignment .. " | DOCK " .. (wantdock and "YES" or "NO") .. " | RESUPPLY AT FLEET YES"
end

function menu.supplyEvidence(component)
    local result = { count = 0, deficit = 0, current = 0, total = 0, budget = nil, wares = {} }
    if not component then return result end
    local ok, count = pcall(C.GetNumSupplyOrderResources, component)
    if not ok then return result end
    result.count = tonumber(count) or 0
    if result.count > 0 then
        local buffer = ffi.new("SupplyResourceInfo[?]", result.count)
        local readok, actual = pcall(C.GetSupplyOrderResources, buffer, result.count, component)
        if readok then
            for index = 0, (tonumber(actual) or 0) - 1 do
                local total, current = tonumber(buffer[index].total) or 0, tonumber(buffer[index].current) or 0
                result.total = result.total + total
                result.current = result.current + current
                result.deficit = result.deficit + math.max(0, total - current)
                local ware = buffer[index].ware ~= nil and ffi.string(buffer[index].ware) or "UNKNOWN"
                local supplytypes = buffer[index].supplytypes ~= nil and ffi.string(buffer[index].supplytypes) or "UNKNOWN"
                result.wares[#result.wares + 1] = { ware = ware, supplytypes = supplytypes, current = current, total = total, deficit = math.max(0, total - current) }
            end
        end
    end
    local budgetok, budget = pcall(C.GetSupplyBudget, component)
    if budgetok then result.budget = tonumber(budget) and tonumber(budget) / 100 or nil end
    return result
end

function menu.carrierPage(tableWidget)
    local selected = menu.strategicFleet(menu.selectedFleet)
    section(tableWidget, "CARRIER AIR-WING MANAGER")
    for index = 1, math.min(3, #(menu.strategicRecords.carriers or {})) do local row = menu.strategicRecords.carriers[index]; textRow(tableWidget, "Saved carrier " .. tostring(index), tostring(row[3]) .. " | " .. tostring(row[4]) .. " WING(S) | " .. tostring(row[5]), neutralColor) end
    textRow(tableWidget, "Native boundary", "Roles are X4 assignments. RESERVE is X4 dock-at-commander. Every write is read back; a mismatch restores the prior assignment and dock state.", passColor)
    if not selected then textRow(tableWidget, "Carrier", "BLOCKED - CHOOSE A FLEET ON THE FLEETS PAGE", warningColor); return end
    textRow(tableWidget, "Selected fleet", selected.commander.fleetname .. " | " .. selected.commander.name .. " | TYPE " .. selected.commander.shiptype, headingColor)
    if selected.commander.shiptype ~= "carrier" then textRow(tableWidget, "Carrier proof", "BLOCKED - THE SELECTED COMMANDER IS NOT AN X4 CARRIER", warningColor); return end
    local commander, groups = fleetSubordinateGroups(selected)
    if not commander or #groups == 0 then textRow(tableWidget, "Wing groups", "BLOCKED - NO DIRECT X4 SUBORDINATE GROUP", warningColor); return end
    local selectedGroupExists = false
    for _, group in ipairs(groups) do if group == menu.strategic.group then selectedGroupExists = true; break end end
    if not selectedGroupExists then menu.strategic.group = groups[1] end
    local draft, saved, status = menu.carrierEditor(selected.commander.idcode, menu.strategic.group)
    if not draft then textRow(tableWidget, "Carrier draft", status, warningColor); return end
    dropdownRow(tableWidget, "Direct group", groups, menu.strategic.group, function(value) menu.strategic.group = tonumber(value) or groups[1] end)
    dropdownRow(tableWidget, "Wing role", wingRoles, menu.strategic.wingRole, function(value) draft.role = tostring(value); draft.dirty = true; menu.strategic.wingRole = draft.role end)
    dropdownRow(tableWidget, "Damage recall", damageOptions, menu.strategic.damageHull, function(value) draft.damage = tonumber(value) or draft.damage; draft.dirty = true; menu.strategic.damageHull = draft.damage end, "% hull")
    textRow(tableWidget, "Saved wing", saved and (selected.commander.idcode .. " | GROUP " .. tostring(saved[3]) .. " | " .. saved[4] .. " | RECALL " .. tostring(saved[5]) .. "%") or status, saved and passColor or warningColor)
    textRow(tableWidget, "Editor", draft.dirty and "UNSAVED EDIT - APPLY TO SAVE; REFRESH AND MAP BACK KEEP THIS DRAFT" or (saved and "MATCHES SAVED PROFILE" or (menu.carrierWingEvidenceValid == true and "NEW DRAFT - DEFAULTS ARE NOT SAVED SETTINGS" or "SAVED SETTINGS UNKNOWN - APPLY AND RECALL BLOCKED")), draft.dirty and warningColor or neutralColor)
    local currentassignment = ffi.string(C.GetSubordinateGroupAssignment(commander, menu.strategic.group))
    local currentdock = C.ShouldSubordinateGroupDockAtCommander(commander, menu.strategic.group)
    textRow(tableWidget, "Native readback", "GROUP " .. tostring(menu.strategic.group) .. " | ASSIGNMENT " .. safeText(currentassignment, "UNKNOWN") .. " | DOCK AT CARRIER " .. (currentdock and "YES" or "NO"), neutralColor)
    actionRow(tableWidget, "Apply role", "APPLY TO THIS EXACT X4 GROUP AND SAVE PROFILE", function()
        menu.requestCarrierProfile(selected, menu.strategic.group, menu.strategic.wingRole, menu.strategic.damageHull)
    end, menu.carrierWingEvidenceValid == true and not menu.pendingActionKind and not selected.missionProtected and not selected.commander.playerOccupied, passColor)
    actionRow(tableWidget, "Recover wing", "RECALL THIS GROUP - ENABLE NATIVE DOCK AT COMMANDER", function()
        menu.requestCarrierProfile(selected, menu.strategic.group, "RESERVE", menu.strategic.damageHull)
    end, menu.carrierWingEvidenceValid == true and not menu.pendingActionKind and not selected.missionProtected and not selected.commander.playerOccupied, warningColor)
    local damaged = 0
    for _, member in ipairs(selected.members) do if member.hull and member.hull <= menu.strategic.damageHull then damaged = damaged + 1 end end
    textRow(tableWidget, "Recovery evidence", tostring(damaged) .. " SHIP(S) AT/BELOW " .. tostring(menu.strategic.damageHull) .. "% HULL | UNKNOWN HULL NEVER COUNTS READY", damaged > 0 and warningColor or passColor)
end

function menu.defenseGridPage(tableWidget)
    section(tableWidget, "SECTOR DEFENSE GRID")
    for index = 1, math.min(3, #(menu.strategicRecords.grids or {})) do local row = menu.strategicRecords.grids[index]; textRow(tableWidget, "Saved grid " .. tostring(index), "TASK FORCE " .. tostring(row[2]) .. " | " .. tostring(row[3]) .. " | " .. tostring(row[5]), neutralColor) end
    textRow(tableWidget, "How this works", "Choose a group and response range, then save. Send eligible fleets to the current incident, or return dispatched fleets to their saved Home posts. Up to three group members are checked per dispatch.", passColor)
    if #menu.taskForces == 0 then textRow(tableWidget, "Task Force", "BLOCKED - CREATE A TASK FORCE FIRST", warningColor); return end
    menu.taskForce.selected = clamp(menu.taskForce.selected, 1, #menu.taskForces)
    local labels = {}
    for index, force in ipairs(menu.taskForces) do labels[index] = tostring(force[2]) .. " [" .. tostring(force[1]) .. "]" end
    dropdownRow(tableWidget, "Task Force", labels, labels[menu.taskForce.selected], function(value) for i, label in ipairs(labels) do if label == value then menu.taskForce.selected = i; return end end end)
    dropdownRow(tableWidget, "Grid range", coverageRanges, menu.strategic.defenseRange, function(value) menu.strategic.defenseRange = normalizeCoverage(value) end)
    local force = menu.taskForces[menu.taskForce.selected]
    textRow(tableWidget, "Fleets in this group", tostring(#(force[9] or {})) .. " FLEET(S) - NO PRIMARY OR BACKUP ROLES", neutralColor)
    actionRow(tableWidget, "Save settings", "SAVE AREA DEFENSE SETTINGS", function() menu.strategicAction("DEFENSE_GRID_SAVE", tostring(force[1]), { menu.strategic.defenseRange, menu.strategic.reserveThreshold }) end, not menu.pendingActionKind, passColor)
    buttonPairRow(tableWidget,
        "SEND DEFENSE TO THE CURRENT INCIDENT", function() menu.strategicAction("DEFENSE_GRID_DISPATCH", tostring(force[1]), {}) end,
        "RETURN DEFENSE FLEETS HOME", function() menu.strategicAction("DEFENSE_GRID_RETURN", tostring(force[1]), {}) end,
        warningColor, not menu.pendingActionKind, not menu.pendingActionKind)
end

function menu.convoyPage(tableWidget)
    section(tableWidget, "CONVOY ESCORT OPERATIONS")
    for index = 1, math.min(3, #(menu.strategicRecords.convoys or {})) do local row = menu.strategicRecords.convoys[index]; textRow(tableWidget, "Convoy " .. tostring(index), tostring(row[2]) .. " + " .. tostring(row[3]) .. " | " .. tostring(row[4]), neutralColor) end
    textRow(tableWidget, "How this works", "Choose a trader or miner and a fleet to protect it. The civilian keeps its work orders. Release returns the escort to its previous fleet assignment.", passColor)
    local civilians = {}
    for _, row in ipairs(menu.strategicAssets or {}) do if row.kind == "CIVILIAN" then civilians[#civilians + 1] = row end end
    if #civilians == 0 or not menu.sample or #menu.sample.fleets == 0 then textRow(tableWidget, "Eligibility", "BLOCKED - REFRESH MUST PROVE A PLAYER MINER/TRADER AND AN ESCORT FLEET", warningColor); return end
    menu.strategic.assetChoice = clamp(menu.strategic.assetChoice, 1, #civilians)
    menu.strategic.secondaryChoice = clamp(menu.strategic.secondaryChoice, 1, #menu.sample.fleets)
    local civilianLabels, escortLabels = {}, {}
    for i, row in ipairs(civilians) do civilianLabels[i] = row.name .. " [" .. row.idcode .. "] | " .. row.sector end
    for i, fleet in ipairs(menu.sample.fleets) do escortLabels[i] = fleet.commander.fleetname .. " [" .. fleet.commander.idcode .. "]" end
    dropdownRow(tableWidget, "Ship to protect", civilianLabels, civilianLabels[menu.strategic.assetChoice], function(value) for i, label in ipairs(civilianLabels) do if label == value then menu.strategic.assetChoice = i; return end end end)
    dropdownRow(tableWidget, "Escort fleet", escortLabels, escortLabels[menu.strategic.secondaryChoice], function(value) for i, label in ipairs(escortLabels) do if label == value then menu.strategic.secondaryChoice = i; return end end end)
    local civilian, escort = civilians[menu.strategic.assetChoice], menu.sample.fleets[menu.strategic.secondaryChoice]
    textRow(tableWidget, "Trip evidence", civilian.order ~= "UNKNOWN" and ("CURRENT CIVILIAN ORDER " .. civilian.order .. " | EXACT ORDER CAPTURE REQUIRED") or "BLOCKED - CURRENT CIVILIAN ORDER UNKNOWN", civilian.order ~= "UNKNOWN" and neutralColor or warningColor)
    buttonPairRow(tableWidget,
        "START PROTECTING THIS SHIP", function() menu.strategicAction("CONVOY_ATTACH", civilian.idcode, { escort.commander.idcode }) end,
        "END ESCORT - RESTORE PREVIOUS ASSIGNMENT", function() menu.strategicAction("CONVOY_RELEASE", civilian.idcode, {}) end,
        warningColor, civilian.order ~= "UNKNOWN" and not menu.pendingActionKind, not menu.pendingActionKind)
end

function menu.logisticsPage(tableWidget)
    section(tableWidget, "MOBILE LOGISTICS FLEET")
    for index = 1, math.min(3, #(menu.strategicRecords.logistics or {})) do local row = menu.strategicRecords.logistics[index]; textRow(tableWidget, "Logistics " .. tostring(index), tostring(row[2]) .. " -> " .. tostring(row[3]) .. " | " .. tostring(row[4]), neutralColor) end
    textRow(tableWidget, "How this works", "Assign a supply ship to support a fleet. This assigns X4's Supply Fleet role; FOC does not buy supplies or move cargo here.", passColor)
    local suppliers = {}
    for _, row in ipairs(menu.strategicAssets or {}) do if row.kind == "RESUPPLIER" then suppliers[#suppliers + 1] = row end end
    if #suppliers == 0 or not menu.sample or #menu.sample.fleets == 0 then textRow(tableWidget, "Eligibility", "BLOCKED - REFRESH MUST PROVE AN AUXILIARY AND A TARGET FLEET", warningColor); return end
    menu.strategic.assetChoice = clamp(menu.strategic.assetChoice, 1, #suppliers)
    menu.strategic.secondaryChoice = clamp(menu.strategic.secondaryChoice, 1, #menu.sample.fleets)
    local supplierLabels, targetLabels = {}, {}
    for i, row in ipairs(suppliers) do supplierLabels[i] = row.name .. " [" .. row.idcode .. "] | " .. row.sector end
    for i, fleet in ipairs(menu.sample.fleets) do targetLabels[i] = fleet.commander.fleetname .. " [" .. fleet.commander.idcode .. "]" end
    dropdownRow(tableWidget, "Auxiliary", supplierLabels, supplierLabels[menu.strategic.assetChoice], function(value) for i, label in ipairs(supplierLabels) do if label == value then menu.strategic.assetChoice = i; return end end end)
    dropdownRow(tableWidget, "Supported fleet", targetLabels, targetLabels[menu.strategic.secondaryChoice], function(value) for i, label in ipairs(targetLabels) do if label == value then menu.strategic.secondaryChoice = i; return end end end)
    local supplier, target = suppliers[menu.strategic.assetChoice], menu.sample.fleets[menu.strategic.secondaryChoice]
    local evidence = menu.supplyEvidence(bridgeComponent64(target.commander.object))
    textRow(tableWidget, "Supply resources", tostring(evidence.count) .. " WARE(S) | CURRENT " .. tostring(evidence.current) .. " / " .. tostring(evidence.total) .. " | DEFICIT " .. tostring(evidence.deficit), evidence.deficit > 0 and warningColor or passColor)
    for index = 1, math.min(6, #evidence.wares) do
        local ware = evidence.wares[index]
        textRow(tableWidget, "Native ware " .. tostring(index), string.upper(ware.ware) .. " | " .. string.upper(ware.supplytypes) .. " | " .. tostring(ware.current) .. " / " .. tostring(ware.total) .. " | SHORT " .. tostring(ware.deficit), ware.deficit > 0 and warningColor or neutralColor)
    end
    textRow(tableWidget, "Native budget", evidence.budget and ("ESTIMATED SUPPLY BUDGET " .. ConvertMoneyString(evidence.budget, false, true, 0, true) .. " | INFORMATION ONLY - NOT A QUOTE OR APPROVAL") or "UNKNOWN - BUDGET READBACK UNAVAILABLE", evidence.budget and neutralColor or warningColor)
    textRow(tableWidget, "Compatibility boundary", "AMMO / CONSUMABLES ARE REPORTED ONLY WHEN X4 EXPOSES THEM AS SUPPLY WARES. TRADER, BLUEPRINT, AND EQUIPMENT COMPATIBILITY REMAIN UNKNOWN; FOC WILL NOT PURCHASE OR TRANSFER THEM.", warningColor)
    buttonPairRow(tableWidget,
        "ASSIGN AUXILIARY TO SUPPLY FLEET", function() menu.strategicAction("LOGISTICS_ATTACH", supplier.idcode, { target.commander.idcode }) end,
        "RELEASE AUXILIARY", function() menu.strategicAction("LOGISTICS_RELEASE", supplier.idcode, {}) end,
        warningColor, not menu.pendingActionKind, not menu.pendingActionKind)
end

function menu.assaultPage(tableWidget)
    section(tableWidget, "COORDINATED ASSAULT GROUP")
    for index = 1, math.min(3, #(menu.strategicRecords.assaults or {})) do local row = menu.strategicRecords.assaults[index]; textRow(tableWidget, "Assault " .. tostring(index), "TASK FORCE " .. tostring(row[2]) .. " | " .. tostring(row[3]) .. " -> " .. tostring(row[4]) .. " | " .. tostring(row[5]), neutralColor) end
    textRow(tableWidget, "How this works", "Choose a gathering point and target, then save. Gather brings fleets together; Attack sends them when ready. Cancel removes only this operation's FOC orders.", passColor)
    if #menu.taskForces == 0 then textRow(tableWidget, "Task Force", "BLOCKED - CREATE A TASK FORCE FIRST", warningColor); return end
    menu.taskForce.selected = clamp(menu.taskForce.selected, 1, #menu.taskForces)
    local labels = {}
    for index, force in ipairs(menu.taskForces) do labels[index] = tostring(force[2]) .. " [" .. tostring(force[1]) .. "]" end
    dropdownRow(tableWidget, "Task Force", labels, labels[menu.taskForce.selected], function(value) for i, label in ipairs(labels) do if label == value then menu.taskForce.selected = i; return end end end)
    dropdownRow(tableWidget, "Minimum readiness", { 50, 60, 70, 80, 90, 100 }, menu.strategic.minimumReadiness, function(value) menu.strategic.minimumReadiness = tonumber(value) or 80 end, "%")
    actionRow(tableWidget, "Rally point", menu.strategic.rally and ("MARKED " .. menu.strategic.rally.name .. " | " .. table.concat(menu.strategic.rally.position, ", ")) or "CHOOSE EXACT RALLY POINT ON FOC MAP", function() menu.openStrategicMap("ASSAULT_RALLY") end, not menu.pendingActionKind, headingColor)
    actionRow(tableWidget, "Attack target", menu.strategic.target and (menu.strategic.target.name .. " [" .. menu.strategic.target.id .. "]") or "CHOOSE EXACT ATTACKABLE TARGET ON FOC MAP", function() menu.openStrategicMap("ASSAULT_TARGET") end, not menu.pendingActionKind, headingColor)
    local force = menu.taskForces[menu.taskForce.selected]
    actionRow(tableWidget, "Save assault", "SAVE TASK FORCE, RALLY, TARGET, AND READINESS", function()
        menu.strategicAction("ASSAULT_SAVE", tostring(force[1]), { menu.strategic.minimumReadiness, menu.strategic.rally and menu.strategic.rally.id or "", menu.strategic.rally and menu.strategic.rally.position or {}, menu.strategic.target and menu.strategic.target.id or "" })
    end, menu.strategic.rally ~= nil and menu.strategic.target ~= nil and not menu.pendingActionKind, passColor)
    local members = force[9] or {}
    if #members > 0 then
        menu.strategic.assaultMemberChoice = clamp(menu.strategic.assaultMemberChoice, 1, #members)
        dropdownRow(tableWidget, "Role fleet", members, members[menu.strategic.assaultMemberChoice], function(value) for i, member in ipairs(members) do if member == value then menu.strategic.assaultMemberChoice = i; return end end end)
        dropdownRow(tableWidget, "Assault role", { "INTERCEPT", "BOMBARDMENT", "CAPITAL ASSAULT", "RESERVE" }, menu.strategic.assaultRole, function(value) menu.strategic.assaultRole = tostring(value) end)
        actionRow(tableWidget, "Save role", "SAVE EXPLICIT ROLE FOR THIS FLEET; RESERVE RALLIES BUT DOES NOT LAUNCH", function() menu.strategicAction("ASSAULT_ROLE_SAVE", tostring(force[1]), { members[menu.strategic.assaultMemberChoice], menu.strategic.assaultRole }) end, not menu.pendingActionKind, headingColor)
    end
    buttonPairRow(tableWidget,
        "GATHER FLEETS AT RALLY POINT", function() menu.strategicAction("ASSAULT_RALLY", tostring(force[1]), {}) end,
        "ATTACK TARGET IF FLEETS ARE READY", function() menu.strategicAction("ASSAULT_LAUNCH", tostring(force[1]), {}) end,
        warningColor, not menu.pendingActionKind, not menu.pendingActionKind)
    actionRow(tableWidget, "Abort / withdraw", "ABORT RETAINED FOC ORDERS AND RETURN TO SAVED POSTS", function() menu.strategicAction("ASSAULT_ABORT", tostring(force[1]), {}) end, not menu.pendingActionKind, criticalColor)
end

function menu.advisorWorkspaceActive()
    return menu.shown == true and not menu.minimized and menu.frame ~= nil and not menu.closeInProgress and (menu.page == 'shipyard' or (menu.page == 'taskforces' and menu.strategic.view == 'COVERAGE AND FLEET TEMPLATES'))
end
function menu.bindAdvisor()
    FOC_Advisor.onChange=function() menu.advisorRedraw=true end
    FOC_Advisor.resetDetailPage=function() menu.listPages['advisor.detail']=1 end
    FOC_Advisor.fitReview=menu.npcReviewFits
    FOC_Advisor.shipyardRowUnits=menu.shipyardRowUnits
    FOC_Advisor.showPointers=function() return menu.workflowPointersVisible end
    FOC_Advisor.isCurrent=function(w) return menu.advisorWorkspaceActive() and menu.mainTable==w end
    FOC_Advisor.openSector=menu.openAdvisorSector
    FOC_Advisor.purchaseEpoch=menu.purchaseEpoch
    FOC_Advisor.purchaseContextActive=function(epoch) return epoch==menu.purchaseEpoch and menu.advisorWorkspaceActive() end
    FOC_Advisor.openPurchase=function(yard)
        if not menu.advisorWorkspaceActive() then return end
        openNativeMenu('ShipConfigurationMenu',{0,0,yard,'purchase',{}})
    end
end
function menu.shipyardPage(tableWidget)
    menu.bindAdvisor()
    FOC_Shipyard.render(tableWidget,actionRow,textRow,dropdownRow,passColor,warningColor,addPager,function()
        menu.page='fleets';menu.activeTab='fleets';rebuild(true)
    end)
end
function menu.taskForcesPage(tableWidget)
    section(tableWidget, "STRATEGIC OPERATIONS")
    dropdownRow(tableWidget, "Choose an operation", menu.strategicViews, menu.strategic.view, function(value) menu.strategic.view = tostring(value); rebuild(true) end)
    actionRow(tableWidget, "Evidence", "REFRESH STRATEGIC EVIDENCE | " .. (menu.strategicSnapshotStatus or "NOT REFRESHED"), function() menu.strategicSnapshotStatus = "REQUESTED"; AddUITriggeredEvent(menu.name, "strategic_refresh", nil); rebuild(false) end, not menu.pendingActionKind, headingColor, true)
    if menu.strategic.view == "COVERAGE AND FLEET TEMPLATES" then
        menu.bindAdvisor()
        FOC_Advisor.render(tableWidget, actionRow, textRow, dropdownRow, passColor, warningColor, addPager)
    elseif menu.strategic.view == "TASK FORCES" then taskForcesLegacyPage(tableWidget)
    elseif menu.strategic.view == "CARRIER AIR WINGS" then
        menu.carrierPage(tableWidget)
        local selected = menu.strategicFleet(menu.selectedFleet)
        local key = selected and fleetKey(selected)
        actionRow(tableWidget, "Inspect live fleet", "SHOW SELECTED FLEET / SHIP IN X4 MAP", function() menu.openFleetInspection(key) end,
            key ~= nil and not menu.pendingActionKind and not menu.carrierTransaction, headingColor, true)
    elseif menu.strategic.view == "SECTOR DEFENSE GRID" then menu.defenseGridPage(tableWidget)
    elseif menu.strategic.view == "CONVOY ESCORT" then menu.convoyPage(tableWidget)
    elseif menu.strategic.view == "MOBILE LOGISTICS" then menu.logisticsPage(tableWidget)
    else menu.assaultPage(tableWidget) end
end

function menu.applyPreset(orders, preset)
    if preset == "PROTECT HOME" then orders.fleetRole = "GUARD HOME"; orders.coverage = "HOME SECTOR ONLY"; orders.respondShips = "YES"; orders.respondStations = "YES"; orders.distressUrgency = 5; orders.shipDamage = 70; orders.stationDamage = 70
    elseif preset == "GUARD TRADERS" then orders.fleetRole = "PATROL"; orders.coverage = "TWO GATES"; orders.respondShips = "YES"; orders.respondStations = "NO"; orders.distressUrgency = 4; orders.shipDamage = 80
    elseif preset == "DEFEND STATIONS" then orders.fleetRole = "GUARD HOME"; orders.coverage = "ONE GATE"; orders.respondShips = "NO"; orders.respondStations = "YES"; orders.distressUrgency = 3; orders.stationDamage = 90
    elseif preset == "HUNT PIRATES" then orders.fleetRole = "PATROL"; orders.coverage = "THREE GATES"; orders.respondShips = "YES"; orders.respondStations = "YES"; orders.distressUrgency = 3; orders.shipDamage = 90; orders.stationDamage = 90
    elseif preset == "STAY SAFE" then orders.fleetRole = "GUARD HOME"; orders.coverage = "HOME SECTOR ONLY"; orders.respondShips = "YES"; orders.respondStations = "YES"; orders.distressUrgency = 8; orders.shipDamage = 50; orders.stationDamage = 50
    else orders.coverage = "OFF"; orders.respondShips = "NO"; orders.respondStations = "NO" end
end

local function fleetOrdersPane(tableWidget)
    local selected = menu.sample.fleets[menu.selectedFleet]
    if selected then
        local selectedFleetKey = fleetKey(selected)
        section(tableWidget, selected.commander.fleetname .. "  |  EDITING THIS FLEET")
        textRow(tableWidget, "Flagship", selected.commander.name .. " [" .. selected.commander.idcode .. "]", headingColor)
        textRow(tableWidget, "Current location", selected.commander.sector .. "  |  " .. tostring(selected.shipCount) .. " ship(s)", neutralColor)
        textRow(tableWidget, "Captain / condition", selected.commander.captain .. " - " .. selected.commander.captainState .. "  |  Hull " .. percent(selected.commander.hull) .. "  |  Shields " .. percent(selected.commander.shield), statusColor(selected.status))
        local memberSummary = {}
        for index = 1, math.min(#selected.members, 8) do
            local member = selected.members[index]
            memberSummary[#memberSummary + 1] = member.name .. " [" .. member.idcode .. "] | " .. member.assignment .. " | Captain " .. member.captainState .. (member.isMission and " | MISSION/STORY PROTECTED" or "")
        end
        if #selected.members > 8 then memberSummary[#memberSummary + 1] = "+ " .. tostring(#selected.members - 8) .. " additional fleet member(s)" end
        textRow(tableWidget, "Fleet members", #memberSummary > 0 and table.concat(memberSummary, "\n") or "NO SUBORDINATES REPORTED BY X4", selected.missionProtected and warningColor or neutralColor)
        textRow(tableWidget, "Before you start", "These settings are a draft. Previewing does not send orders.", passColor)
        if not selectedFleetKey then
            actionRequired(tableWidget,
                "FOC could not save a draft for this fleet.",
                "The fleet commander's stable registration identity is unavailable.",
                "Open Readiness, refresh the fleet evidence, and choose a fleet whose commander identity is shown.",
                "readiness", "OPEN READINESS")
            return
        end
        local selectedFleetAudit = fleetAuditSubject(selected, selectedFleetKey)
        local orders = ordersForFleet(selected)
        local homeSector = homeSectorForFleet(selected)
        local homeSectorName = homeSector and homeSector.text or "NOT CHOSEN"
        if menu.notice then textRow(tableWidget, "Last action", menu.notice, needsAction(menu.notice) and warningColor or passColor) end
        local storyShip = selected.protectedObject or selected.overrideObject
        if storyShip and not storyShip.storyAnswered then
            local storyStatus = selected.missionProtected and "YES - STORY OR MISSION IS STILL ACTIVE" or "NO - STORY OR MISSION IS FINISHED"
            textRow(tableWidget, "Story ship", storyShip.name .. " [" .. storyShip.idcode .. "] | CURRENT ANSWER: " .. storyStatus, selected.missionProtected and criticalColor or passColor)
            textRow(tableWidget, "Question", "Is this ship still being used by a story or mission?", headingColor)
            textRow(tableWidget, "What this means", "Choose No only if that story or mission is finished. This changes FOC only; it does not change the game's story.", warningColor)
            buttonPairRow(tableWidget,
                "YES - STORY OR MISSION IS STILL ACTIVE", function()
                    auditAction("SET_STORY_STATUS", storyShip.idcode, "SAVING YES - WAIT FOR CONFIRMATION", "STORY_STATUS_PENDING", "YES")
                end,
                "NO - STORY OR MISSION IS FINISHED", function()
                    auditAction("SET_STORY_STATUS", storyShip.idcode, "SAVING NO - WAIT FOR CONFIRMATION", "STORY_STATUS_PENDING", "NO")
                end,
                warningColor, not menu.pendingActionKind, not menu.pendingActionKind)
        elseif selected.commander.primarypurpose ~= "fight" then
            textRow(tableWidget, "Reaction-force scope", "NON-COMBAT COMMANDER (" .. string.upper(selected.commander.primarypurpose) .. ") - SUPPLY OR LOGISTICS ORDERS ARE PROTECTED BY DEFAULT.", warningColor)
            actionRow(tableWidget, "Override", orders.nonCombatOverride and "OVERRIDE ACTIVE - DO THIS ANYWAY" or "OVERRIDE - DO THIS ANYWAY", function()
                orders.nonCombatOverride = not orders.nonCombatOverride
                markFleetOrdersChanged(selectedFleetKey, orders)
                rebuild(false)
            end, true, warningColor)
        end

        section(tableWidget, "1  FLEET ORDER")
        dropdownRow(tableWidget, "Native order", fleetRoles, orders.fleetRole, function(value) orders.fleetRole = normalizeFleetRole(value); markFleetOrdersChanged(selectedFleetKey, orders) end)
        actionRow(tableWidget, "Home sector", homeSectorName, function() chooseHomeOnMap(selected) end, true, homeSector and headingColor or warningColor)
        actionRow(tableWidget, "Choose home", "CHOOSE HOME POINT ON MAP", function() chooseHomeOnMap(selected) end, true, activeTabBackground)
        textRow(tableWidget, "Home point", homePointText(homeSector), homeSector and headingColor or warningColor)
        textRow(tableWidget, "How to choose", "Open the dedicated FOC map, pan or zoom to a discovered sector, then left-click the exact home point. FOC records that sector and position in the unsaved draft and returns here. Dragging still pans; Escape cancels; no order is sent.", headingColor)
        if menu.plan.lastState == "ACTION_REQUIRED_HOME" then
            actionRequired(tableWidget,
                "FOC could not open the safe X4 Home-point choice.",
                "The required native right-click menu was not available.",
                "Close other map or interaction menus, return to Fleets, and press CHOOSE HOME POINT ON MAP again.",
                "fleets", "TRY FLEETS AGAIN")
        end
        section(tableWidget, "2  DISTRESS CALLS")
        dropdownRow(tableWidget, "Response range", coverageRanges, orders.coverage, function(value) orders.coverage = normalizeCoverage(value); markFleetOrdersChanged(selectedFleetKey, orders) end)
        dropdownRow(tableWidget, "Help my ships", yesNoOptions, orders.respondShips, function(value) orders.respondShips = tostring(value); markFleetOrdersChanged(selectedFleetKey, orders) end)
        dropdownRow(tableWidget, "Help my stations", yesNoOptions, orders.respondStations, function(value) orders.respondStations = tostring(value); markFleetOrdersChanged(selectedFleetKey, orders) end)
        textRow(tableWidget, "Eligible distress owners", "PLAYER-OWNED SHIPS AND STATIONS ONLY", passColor)
        dropdownRow(tableWidget, "Minimum urgency", urgencyOptions, orders.distressUrgency, function(value) orders.distressUrgency = tonumber(value) or 5; markFleetOrdersChanged(selectedFleetKey, orders) end, " / 10")
        textRow(tableWidget, "Urgency scale", "FOC derives urgency from damage: 1 is light damage; 10 is critical damage.", neutralColor)
        dropdownRow(tableWidget, "Help ships below", damageOptions, orders.shipDamage, function(value) orders.shipDamage = tonumber(value) or 70; markFleetOrdersChanged(selectedFleetKey, orders) end, "% hull")
        dropdownRow(tableWidget, "Help stations below", damageOptions, orders.stationDamage, function(value) orders.stationDamage = tonumber(value) or 70; markFleetOrdersChanged(selectedFleetKey, orders) end, "% hull")
        textRow(tableWidget, "After response", "RETURN TO THE FLEET'S NATIVE DEFAULT ORDER", passColor)

        section(tableWidget, "3  READY TO SEND")
        local route = tableWidget:addRow(false)
        route[1]:createText("HOME", { halign = "center", color = passColor })
        route[2]:createText("FLEET ORDER", { halign = "center", color = headingColor })
        route[3]:createText("DISTRESS CALL", { halign = "center", color = warningColor })
        route[4]:createText("RETURN", { halign = "center", color = passColor })
        local routeValues = tableWidget:addRow(false)
        routeValues[1]:createText(homeSectorName, { halign = "center" })
        routeValues[2]:createText(orders.fleetRole, { halign = "center", wordwrap = true })
        routeValues[3]:createText("Urgency " .. tostring(orders.distressUrgency) .. "+\nShip " .. tostring(orders.shipDamage) .. "% | Station " .. tostring(orders.stationDamage) .. "%", { halign = "center", wordwrap = true })
        routeValues[4]:createText("RESUME DEFAULT ORDER", { halign = "center", wordwrap = true })
        textRow(tableWidget, "What happens", "This saves this fleet, unlocks only this fleet, replaces its eligible current orders, starts patrol, and arms its distress response.", passColor)
        local patrolPending = menu.pendingActionKind == "START_FLEET_PATROL"
        local reactionEligible = not selected.missionProtected and (selected.commander.primarypurpose == "fight" or orders.nonCombatOverride)
        local sendReady = homeSector ~= nil and reactionEligible and not menu.pendingActionKind
        local sendLabel = patrolPending and "SENDING - WAIT FOR ACTIVE CONFIRMATION" or not homeSector and "CHOOSE HOME POINT BEFORE SENDING" or not reactionEligible and "BLOCKED - FLEET IS PROTECTED" or "SEND THIS FLEET ON PATROL - REPLACES CURRENT ORDERS"
        actionRow(tableWidget, "Ready to send", sendLabel, function()
            requestFleetPatrolStart(selected, selectedFleetKey, orders, homeSector)
        end, sendReady, patrolPending and warningColor or passColor)
        local savedDraft = menu.draftsByFleet[selectedFleetKey]
        local activeConfirmed = menu.lastActivePatrolFleet == selectedFleetKey and menu.plan.lastState == "FLEET_PATROL_ACTIVE"
        local patrolStatus = patrolPending and "WAITING FOR X4 ACTIVE-ORDER READBACK" or activeConfirmed and "PATROL ACTIVE - DISTRESS RESPONSE ARMED" or savedDraft and "SETTINGS SAVED - ACTIVE PATROL NOT CONFIRMED THIS SESSION" or "NOT ACTIVE YET - CONFIGURE THIS FLEET AND PRESS SEND"
        if orders.shipyardReady and orders.locked and not patrolPending and not activeConfirmed then patrolStatus='READY FOR ASSIGNMENT - choose Home and mission, then Send. Gathering arrival is not confirmed here.' end
        textRow(tableWidget, "Fleet status", patrolStatus, activeConfirmed and passColor or warningColor)
        textRow(tableWidget, "Hard safety", "Player control, mission/story protection, missing pilot or Home, non-combat scope, and critical non-cancelable orders still block the send.", passColor)

        section(tableWidget, "ADVANCED CONTROLS - OPTIONAL")
        actionRow(tableWidget, "Advanced", menu.showFleetAdvanced and "HIDE ADVANCED CONTROLS" or "SHOW ADVANCED CONTROLS", function() menu.showFleetAdvanced = not menu.showFleetAdvanced; rebuild(false) end, true, headingColor)
        if menu.showFleetAdvanced then
        local pendingDraft = menu.pendingDraftSaves[selectedFleetKey]
        actionRow(tableWidget, "Draft", pendingDraft and "SAVE PENDING - WAIT FOR READBACK" or "SAVE AS DRAFT", function()
            menu.plan.status = "DRAFT"
            if not homeSector then
                menu.plan.lastResult = "DRAFT NOT SAVED - CHOOSE A HOME POINT ON THE MAP"
                rebuild(false)
                return
            end
            requestFleetDraftSave(selected, selectedFleetKey, orders, homeSector)
        end, not pendingDraft, headingColor)
        textRow(tableWidget, "Draft status", savedDraft and "DRAFT SAVED IN GAME STATE - NO ORDERS WERE SENT" or pendingDraft and "SAVE REQUEST SENT - WAITING FOR PERSISTENT READBACK" or "NOT SAVED - PRESS SAVE AS DRAFT", savedDraft and passColor or warningColor)
        section(tableWidget, "TEMPLATES AND PRESETS")
        dropdownRow(tableWidget, "Plain-language preset", automationPresets, menu.operations.preset, function(value)
            menu.operations.preset = tostring(value)
            menu.applyPreset(orders, menu.operations.preset)
            markFleetOrdersChanged(selectedFleetKey, orders)
            menu.plan.lastResult = menu.operations.preset .. " LOADED INTO THIS FLEET'S VISIBLE DRAFT - NO ORDER WAS SENT"
            menu.plan.lastState = "VISIBLE_DRAFT_UPDATED"
            menu.notice = menu.plan.lastResult
            rebuild(false)
        end)
        textRow(tableWidget, "Preset safety", "A preset only fills the visible fleet draft. Review it, choose Home, then separately save or send.", passColor)
        actionRow(tableWidget, "Save template", #menu.templates < 8 and "SAVE CURRENT VISIBLE DRAFT AS TEMPLATE " .. tostring(#menu.templates + 1) or "LIMIT REACHED - 8 TEMPLATES", function()
            auditAction("TEMPLATE_SAVE", selectedFleetAudit, "TEMPLATE SAVE REQUESTED - PERSISTENT READBACK REQUIRED", "TEMPLATE_PENDING", { "TEMPLATE " .. tostring(#menu.templates + 1), orders.fleetRole, orders.coverage, orders.respondShips, orders.respondStations, orders.distressUrgency, orders.shipDamage, orders.stationDamage, orders.returnHome })
        end, #menu.templates < 8 and not menu.pendingActionKind, headingColor)
        if #menu.templates > 0 then
            menu.templateChoice = clamp(menu.templateChoice, 1, #menu.templates)
            local templateLabels = {}
            for index, template in ipairs(menu.templates) do templateLabels[index] = tostring(template[2]) end
            dropdownRow(tableWidget, "Saved template", templateLabels, templateLabels[menu.templateChoice], function(value)
                for index, label in ipairs(templateLabels) do if label == value then menu.templateChoice = index; return end end
            end)
            actionRow(tableWidget, "Apply template", "APPLY TO THIS VISIBLE DRAFT - DO NOT SEND", function()
                local template = menu.templates[menu.templateChoice]
                orders.fleetRole = normalizeFleetRole(template[3]); orders.coverage = normalizeCoverage(template[4]); orders.respondShips = tostring(template[5]); orders.respondStations = tostring(template[6]); orders.distressUrgency = tonumber(template[7]) or 5; orders.shipDamage = tonumber(template[8]) or 70; orders.stationDamage = tonumber(template[9]) or 70; orders.returnHome = tostring(template[10] or "YES")
                markFleetOrdersChanged(selectedFleetKey, orders)
                menu.plan.lastResult = tostring(template[2]) .. " APPLIED TO THIS VISIBLE DRAFT - NO ORDER WAS SENT"
                menu.plan.lastState = "VISIBLE_DRAFT_UPDATED"
                menu.notice = menu.plan.lastResult
                rebuild(false)
            end, true, passColor)
        end
        actionRow(tableWidget, "Automation lock", orders.locked and "LOCKED - FOC CANNOT CHANGE THIS FLEET" or "UNLOCKED - APPROVED PLANS MAY CHANGE THIS FLEET", function() orders.locked = not orders.locked; markFleetOrdersChanged(selectedFleetKey, orders); rebuild(false) end, true, warningColor)
        section(tableWidget, "X4 SUBORDINATE GROUP POLICIES")
        textRow(tableWidget, "What these do", "These controls change X4's real settings for every current direct subordinate group in this fleet. FOC reads the setting back immediately and reports BLOCKED unless every group matches.", headingColor)
        local _, provenGroups = fleetSubordinateGroups(selected)
        textRow(tableWidget, "Current groups", #provenGroups > 0 and (tostring(#provenGroups) .. " DIRECT GROUP(S): " .. table.concat(provenGroups, ", ")) or "NO CURRENT DIRECT SUBORDINATE GROUP WAS PROVEN", #provenGroups > 0 and passColor or warningColor)
        for _, policy in ipairs({ "dock", "resupply", "distress", "reinforce" }) do
            local policyState, enabledGroups, totalGroups = fleetGroupPolicyState(selected, policy)
            local contract = groupPolicyContracts[policy]
            textRow(tableWidget, contract.label, policyState .. " | " .. tostring(enabledGroups) .. " OF " .. tostring(totalGroups) .. " GROUP(S) ENABLED", (policyState == "UNKNOWN" or policyState == "UNAVAILABLE" or policyState == "MIXED") and warningColor or neutralColor)
            buttonPairRow(tableWidget,
                "YES - ENABLE FOR ALL CURRENT GROUPS", function()
                    local success, result = setFleetGroupPolicy(selected, policy, true)
                    auditAction("NATIVE_GROUP_POLICY", selectedFleetAudit, result, success and "GROUP_POLICY_CONFIRMED" or "BLOCKED", { policy, "YES", success and "CONFIRMED" or "BLOCKED" })
                end,
                "NO - DISABLE FOR ALL CURRENT GROUPS", function()
                    local success, result = setFleetGroupPolicy(selected, policy, false)
                    auditAction("NATIVE_GROUP_POLICY", selectedFleetAudit, result, success and "GROUP_POLICY_CONFIRMED" or "BLOCKED", { policy, "NO", success and "CONFIRMED" or "BLOCKED" })
                end,
                warningColor, #provenGroups > 0 and not menu.pendingActionKind, #provenGroups > 0 and not menu.pendingActionKind)
            if policy == "reinforce" then
                textRow(tableWidget, "Reinforcement warning", "YES enables X4's native fleet-reinforcement policy. X4 may use its normal ship-building and resource rules. FOC does not buy a blueprint, create a free ship, or hide a cost.", warningColor)
            end
        end
        local recallLabel = selected.missionProtected and "BLOCKED - MISSION / QUEST FLEET" or (reactionEligible and "RECALL TO HOME POST" or "BLOCKED - NON-COMBAT OVERRIDE REQUIRED")
        actionRow(tableWidget, "Emergency", recallLabel, function()
            auditAction("RECALL_FLEET", selected.commander.idcode, "RECALL REQUEST SENT - WAITING FOR RETURN-TO-POST READBACK", "RECALL_PENDING")
        end, reactionEligible, warningColor)
        if menu.plan.lastState == "ACTION_REQUIRED_RECALL" then
            actionRequired(tableWidget,
                "FOC did not recall this fleet.",
                "Replacing an unverified current order could interrupt player or mission control.",
                "Open Activity, review the current-order blocker, then clear or finish the protected order in X4 before trying again.",
                "activity", "OPEN ACTIVITY")
        end
        end
    else
        section(tableWidget, "FLEET ORDERS")
        textRow(tableWidget, "Start here", "Choose a fleet on the left.", warningColor)
    end
end

local function fleetMaintenancePane(tableWidget)
    local selected = menu.sample.fleets[menu.selectedFleet]
    local commanderID = safeText(selected and selected.commander and selected.commander.idcode, "GLOBAL")
    section(tableWidget, "REPAIR / REPLACE / REBUILD")
    if selected then
        textRow(tableWidget, "Current fleet", selected.commander.fleetname .. " | " .. selected.commander.name .. " [" .. commanderID .. "] | " .. tostring(selected.shipCount) .. " current ship(s)", headingColor)
    else
        textRow(tableWidget, "Current fleet", "NO LIVING FLEET COMMANDER SELECTED - GLOBAL RECOVERY REMAINS AVAILABLE", warningColor)
    end
    textRow(tableWidget, "Recovery scope", "Current-fleet native records plus persistent exact losses from every enrolled fleet. This keeps a destroyed-command fleet recoverable even after it disappears from X4's live fleet list.", passColor)
    textRow(tableWidget, "Safety", "FOC rechecks ownership, mission/story protection, player control, current orders, native yards, blueprints, equipment and duplicate build state at every action.", passColor)
    actionRow(tableWidget, "Native status", menu.maintenance.pending and "REFRESH IN PROGRESS" or "REFRESH REPAIR / REBUILD READBACK", function() requestMaintenanceSnapshot(selected) end, not menu.maintenance.pending, menu.maintenance.pending and warningColor or headingColor)
    textRow(tableWidget, "Rebuild scan", menu.maintenance.status, needsAction(menu.maintenance.status) and warningColor or neutralColor)

    section(tableWidget, "1  REPAIR CURRENT SHIPS")
    textRow(tableWidget, "How repair works", "Choose a damaged current ship. FOC finds a known compatible facility, then opens X4's native Repair / Upgrade screen. X4 shows the exact price and resources and requires your confirmation. FOC never performs a free repair or claims completion here.", headingColor)
    local damaged = menu.maintenance.repairRows
    if #damaged == 0 then
        textRow(tableWidget, "Result", "No player-owned ship is currently at or below its saved repair threshold. Surface-component-only damage remains visible in X4's native repair screen.", passColor)
    else
        menu.maintenance.selectedRepair = clamp(menu.maintenance.selectedRepair, 1, #damaged)
        local repairOptions = {}
        for index, ship in ipairs(damaged) do repairOptions[#repairOptions + 1] = { id = index, text = ship.name .. " [" .. ship.idcode .. "] | Hull " .. percent(ship.hull) .. " | " .. ship.scope .. " <= " .. tostring(ship.threshold) .. "%", icon = "", displayremoveoption = false } end
        local repairRow = tableWidget:addRow(true)
        repairRow[1]:createText("Damaged ship", { color = neutralColor })
        repairRow[2]:setColSpan(3):createDropDown(repairOptions, { active = true, startOption = menu.maintenance.selectedRepair, height = Helper.standardButtonHeight })
        repairRow[2].handlers.onDropDownConfirmed = function(_, value) menu.maintenance.selectedRepair = tonumber(value) or 1; rebuild(false) end
        local repairShip = damaged[menu.maintenance.selectedRepair]
        textRow(tableWidget, "Eligibility", repairShip.fleet .. " | " .. repairShip.scope .. " threshold " .. tostring(repairShip.threshold) .. "% hull", headingColor)
        local repairBlocked = repairShip.protected or repairShip.playerOccupied or menu.maintenance.pending
        local repairLabel = repairShip.playerOccupied and "BLOCKED - PLAYER IS CONTROLLING THIS SHIP" or repairShip.protected and "BLOCKED - MISSION / STORY PROTECTED" or menu.maintenance.pending and "WAIT FOR CURRENT NATIVE READBACK" or "OPEN X4 NATIVE REPAIR SCREEN"
        actionRow(tableWidget, "Repair", repairLabel, function() requestNativeRepair(repairShip) end, not repairBlocked, repairBlocked and warningColor or passColor)
    end

    section(tableWidget, "2  LOST-SHIP BLUEPRINTS AND LOADOUTS")
    textRow(tableWidget, "Blueprint rule", "FOC shows living-command native fleet-unit losses plus persistent exact recovery-ledger losses from every enrolled fleet. Ship and equipment blueprints/resources are enforced. FOC does not buy blueprints or substitute a guessed design.", headingColor)
    local lost = menu.maintenance.lostRows
    if #lost == 0 then
        textRow(tableWidget, "Result", menu.maintenance.pending and "Waiting for native and recovery-ledger records." or "No native or enrolled-fleet recovery loss was returned.", menu.maintenance.pending and warningColor or passColor)
    else
        menu.maintenance.selectedLost = clamp(menu.maintenance.selectedLost, 1, #lost)
        local lostOptions = {}
        for index, row in ipairs(lost) do lostOptions[#lostOptions + 1] = { id = index, text = row.name .. " | " .. row.state, icon = "", displayremoveoption = false } end
        local lostRow = tableWidget:addRow(true)
        lostRow[1]:createText("Lost record", { color = neutralColor })
        lostRow[2]:setColSpan(3):createDropDown(lostOptions, { active = true, startOption = menu.maintenance.selectedLost, height = Helper.standardButtonHeight })
        lostRow[2].handlers.onDropDownConfirmed = function(_, value) menu.maintenance.selectedLost = tonumber(value) or 1; menu.maintenance.previewCommanderID = nil; rebuild(false) end
        local selectedLost = lost[menu.maintenance.selectedLost]
        textRow(tableWidget, "Native readiness", selectedLost.detail, selectedLost.ready and passColor or warningColor)
        actionRow(tableWidget, "Blueprint / loadout", "OPEN X4 LOST-SHIP BLUEPRINT EDITOR", function()
            requestNativeLostEditor(selected, selectedLost)
        end, selected ~= nil and selectedLost.fleetunit ~= nil and selectedLost.state ~= "BUILDING" and not menu.maintenance.pending, headingColor)
    end

    section(tableWidget, "3  REPLACE / REBUILD LOST SHIPS")
    local readyCount = 0
    for _, row in ipairs(lost) do if row.ready then readyCount = readyCount + 1 end end
    textRow(tableWidget, "What X4 will do", "Queue each eligible exact record at a compatible player-owned yard, reject missing ship/equipment capability, wait for native build completion, then restore its name and original fleet hierarchy when a commander exists. Rebuilt ships may still need captains.", passColor)
    local previewed = menu.maintenance.previewCommanderID == commanderID
    actionRow(tableWidget, "Preview", "PREVIEW " .. tostring(readyCount) .. " READY LOST SHIP(S) - NO BUILD QUEUED", function()
        menu.maintenance.previewCommanderID = commanderID
        menu.notice = "REBUILD PREVIEW COMPLETE - " .. tostring(readyCount) .. " CURRENT NATIVE OR ENROLLED-FLEET LOSS RECORD(S) READY | NOTHING QUEUED"
        rebuild(false)
    end, not menu.maintenance.pending and #lost > 0, headingColor)
    local selectedProtected = selected and selected.missionProtected or false
    local canConfirm = previewed and readyCount > 0 and not selectedProtected and not menu.pendingActionKind and not menu.maintenance.pending
    local replaceLabel = not previewed and "PREVIEW REQUIRED BEFORE QUEUING" or readyCount == 0 and "BLOCKED - NO LOST RECORD IS READY" or selectedProtected and "BLOCKED - MISSION / STORY PROTECTED" or "CONFIRM: QUEUE EXACT REBUILDS FOR READY LOST SHIPS"
    actionRow(tableWidget, "Replace / rebuild", replaceLabel, function()
        menu.maintenance.previewCommanderID = nil
        auditAction("MAINTENANCE_REPLACE", commanderID, "EXACT FLEET REBUILD REQUEST SENT - REFRESH TO CONFIRM QUEUED / BUILDING RECORDS", "FLEET_REBUILD_REQUESTED")
    end, canConfirm, canConfirm and warningColor or neutralColor)
    textRow(tableWidget, "Authority", "This action consumes only your player-owned yard's normal X4 build resources. It sends no NPC-yard purchase and performs no automatic blueprint purchase.", warningColor)
end

local function fleetSafetyPane(tableWidget)
    section(tableWidget, "REPAIR THRESHOLDS / RESPONSE FLOOD GATE")
    textRow(tableWidget, "Purpose", "These values control which damaged ships appear for manual native repair and how large a whole reaction fleet may be when responding to one distress. They never spend credits, buy blueprints, detach ships, or issue subordinate orders.", headingColor)
    section(tableWidget, "1  REPAIR ELIGIBILITY")
    dropdownRow(tableWidget, "Reaction-force ships", repairThresholdOptions, menu.safety.reactionRepair, function(value) menu.safety.reactionRepair = tonumber(value) or 100; menu.safety.dirty = true end, "% hull")
    dropdownRow(tableWidget, "All player-owned default", repairThresholdOptions, menu.safety.playerRepair, function(value) menu.safety.playerRepair = tonumber(value) or 100; menu.safety.dirty = true end, "% hull")
    textRow(tableWidget, "Threshold rule", "A damaged ship is offered when its hull is at or below the applicable value. Reaction-force membership takes precedence. 0% disables that scope because a surviving ship cannot qualify.", passColor)
    section(tableWidget, "2  DISTRESS RESPONSE FLOOD GATE")
    dropdownRow(tableWidget, "Maximum fleet ships", responseFleetCapOptions, menu.safety.responseCap, function(value) menu.safety.responseCap = tonumber(value) or 100; menu.safety.dirty = true end, " ships")
    textRow(tableWidget, "Response rule", "FOC chooses one closest eligible fleet. Commander plus all subordinates must fit under this cap. Oversized fleets are skipped; fleets are never split.", passColor)
    textRow(tableWidget, "Repeat protection", "One uniquely named response order is attempted. The commander and victim stay locked until recovery above the captured distress threshold, or victim/attacker/commander destruction. Readback failure does not permit another order.", passColor)
    section(tableWidget, "3  SAVE")
    actionRow(tableWidget, "Safety settings", menu.pendingActionKind == "SAVE_SAFETY_THRESHOLDS" and "SAVE PENDING - WAIT FOR READBACK" or menu.safety.dirty and "SAVE REPAIR THRESHOLDS AND RESPONSE CAP" or "SAVED VALUES - PRESS TO RECONFIRM", function()
        auditAction("SAVE_SAFETY_THRESHOLDS", "GLOBAL", "SAFETY THRESHOLD SAVE REQUESTED - PERSISTENT READBACK REQUIRED", "SAFETY_SAVE_PENDING", { menu.safety.reactionRepair, menu.safety.playerRepair, menu.safety.responseCap })
    end, not menu.pendingActionKind, menu.safety.dirty and warningColor or passColor)
    textRow(tableWidget, "Current draft", "Reaction repair " .. tostring(menu.safety.reactionRepair) .. "% | All-player default " .. tostring(menu.safety.playerRepair) .. "% | Whole-fleet response cap " .. tostring(menu.safety.responseCap) .. " ships", menu.safety.dirty and warningColor or passColor)
    textRow(tableWidget, "Last result", menu.plan.lastResult, needsAction(menu.plan.lastResult) and warningColor or passColor)
end

local function readinessPage(tableWidget)
    local provenVacancies = menu.sample.captainIssues
    section(tableWidget, "SHIPS NEEDING CAPTAINS")
    if #provenVacancies == 0 then
        textRow(tableWidget, "Result", "No proven captain vacancy was observed in the bounded ship sample.", passColor)
    else
        local captainHeader = tableWidget:addRow(false)
        captainHeader[1]:createText("STATE", { color = headingColor })
        captainHeader[2]:createText("SHIP", { color = headingColor })
        captainHeader[3]:createText("IDENTITY", { color = headingColor })
        captainHeader[4]:createText("LOCATION", { color = headingColor })
        local personnelGuidanceRows = (menu.plan.lastState == "ACTION_REQUIRED_PERSONNEL" or (menu.previews.personnel and menu.previews.personnel:find("BLOCKED"))) and 6 or 0
        local first, last = addPager(tableWidget, "readiness.captains", #provenVacancies, { fixedRows = 22 + personnelGuidanceRows, contentPixels = menu.listContentHeight })
        for index = first, last do
            local issue = provenVacancies[index]
            if issue then
            local row = tableWidget:addRow(false)
            row[1]:createText(issue.state, { color = issue.state == "MISSING" and criticalColor or warningColor })
            row[2]:createText(issue.name)
            row[3]:createText(issue.idcode)
            row[4]:createText(issue.sector)
            end
        end
    end
    section(tableWidget, "UNKNOWN CAPTAIN EVIDENCE")
    textRow(tableWidget, "Excluded records", tostring(menu.sample.counts.unknownCaptains) .. " unknown record(s). They are not vacancies and cannot authorize assignment.", menu.sample.counts.unknownCaptains > 0 and warningColor or passColor)
    textRow(tableWidget, "Fleet summary", tostring(menu.sample.counts.critical) .. " critical | " .. tostring(menu.sample.counts.degraded) .. " degraded | " .. tostring(menu.sample.counts.unknown) .. " unknown")
    section(tableWidget, "PERSONNEL - CAPTAIN ASSIGNMENT")
    textRow(tableWidget, "Eligibility", "Only proven vacancies may receive a persistent Academy trainee. Field-ship service crew and marines are never used.", passColor)
    textRow(tableWidget, "Selection", tostring(#provenVacancies) .. " proven vacancy record(s); " .. tostring(menu.sample.counts.unknownCaptains) .. " unknown record(s) are separately excluded.", warningColor)
    actionRow(tableWidget, "Personnel plan", "OPEN TRAINING ACADEMY", function() menu.page = "academy"; menu.activeTab = "academy"; rebuild(true) end, true, headingColor)
    if menu.plan.lastState == "ACTION_REQUIRED_PERSONNEL" or (menu.previews.personnel and menu.previews.personnel:find("BLOCKED")) then
        actionRequired(tableWidget,
            "FOC found captain vacancies but did not move any person.",
            "A safe eligible candidate and confirmed captain transfer are not both available.",
            "Open Training Academy, select a retained trainee and one proven vacancy, then preview the exact assignment.",
            "academy", "OPEN TRAINING ACADEMY")
    end
end

local function academyPage(tableWidget)
    local academy = menu.academy
    local track = academy.recruitTrack == "MARINE" and "MARINE" or "PILOT"
    local trackRows = academyRowsForTrack(track)
    if not selectedAcademyRecruit(track) then academy.selectedRecruitID = trackRows[1] and tostring(trackRows[1].id) or nil end
    if not selectedAcademyVacancy(academy.vacancies) then academy.selectedVacancyID = academy.vacancies[1] and academy.vacancies[1].key or nil end
    if not selectedMarineTarget(academy.marineTargets) then academy.selectedMarineTargetID = academy.marineTargets[1] and academy.marineTargets[1].key or nil end

    local function rejectLocal(message)
        menu.plan.lastState = "BLOCKED"
        menu.plan.lastResult = message
        menu.notice = message
        academy.previewPair = nil
        rebuild(false)
    end

    section(tableWidget, "TRAINING ACADEMY")
    textRow(tableWidget, "Purpose", "Maintain one shared station-based reserve. Every retained trainee can receive Pilot or Marine training, then be assigned under the selected focus. The roster can never exceed 100 NPCs.", headingColor)
    textRow(tableWidget, "Capacity", tostring(#academy.rows) .. " / 100 SHARED TRAINEES | AVAILABLE TO PILOT AND MARINE", #academy.rows < 100 and warningColor or passColor)
    dropdownRow(tableWidget, "Training focus", { "PILOT", "MARINE" }, track, function(value)
        academy.recruitTrack = value == "MARINE" and "MARINE" or "PILOT"
        local rows = academyRowsForTrack(academy.recruitTrack)
        academy.selectedRecruitID = rows[1] and tostring(rows[1].id) or nil
        academy.previewPair = nil
    end)
    textRow(tableWidget, "Recruitment safety", "One NPC per approval from an operational player station. Existing shipboard crew, mission/story people, managers, and captains are never taken.", passColor)
    actionRow(tableWidget, "Recruitment", "PREVIEW RECRUITMENT", function()
        academy.previewRecruitTrack = academy.recruitTrack
        auditAction("ACADEMY_PREVIEW_RECRUIT", academy.recruitTrack, academy.recruitTrack .. " RECRUITMENT PREVIEW REQUESTED - NOTHING CHANGED", "ACADEMY_PREVIEW_PENDING")
    end, #academy.rows < 100 and menu.pendingActionKind == nil, headingColor)
    actionRow(tableWidget, "Recruitment", "APPROVE ONE " .. academy.recruitTrack .. " TRAINEE", function()
        auditAction("ACADEMY_RECRUIT", academy.recruitTrack, academy.recruitTrack .. " RECRUITMENT REQUEST SENT - NATIVE ROSTER READBACK REQUIRED", "ACADEMY_RECRUIT_PENDING")
    end, menu.plan.lastState == "ACADEMY_RECRUIT_READY" and academy.previewRecruitTrack == academy.recruitTrack and #academy.rows < 100 and menu.pendingActionKind == nil, warningColor)

    section(tableWidget, "SELECT " .. track .. " TRAINEE")
    if #trackRows == 0 then
        textRow(tableWidget, "Trainee", "No retained Academy trainees. Preview and approve one recruitment while capacity remains.", warningColor)
    else
        local options = {}
        for _, rowData in ipairs(trackRows) do
            local skill = track == "PILOT" and rowData.piloting or rowData.boarding
            options[#options + 1] = { id = tostring(rowData.id), text = rowData.name .. " | " .. track .. " " .. (skill and string.format("%.1f / 5", skill / 3) or "UNKNOWN") .. " | " .. rowData.origin, icon = "", displayremoveoption = false }
        end
        local row = tableWidget:addRow(true)
        row[1]:createText("Trainee", { color = neutralColor })
        local dropdown = row[2]:setColSpan(3):createDropDown(options, { active = true, startOption = academy.selectedRecruitID, height = Helper.standardButtonHeight })
        row[2].handlers.onDropDownConfirmed = function(_, value)
            academy.selectedRecruitID = tostring(value or "")
            academy.previewPair = nil
            rebuild(false)
        end
    end

    local recruit = selectedAcademyRecruit(track)
    local skill = recruit and (track == "PILOT" and recruit.piloting or recruit.boarding) or nil
    local nextTier = skill and math.min(5, math.floor(skill / 3) + 1) or 1
    local trainingOwned = recruit and (track == "PILOT" and recruit.seminarCount or menu.store.marine[nextTier]) or 0
    local canTrain = recruit and recruit.valid and skill and skill < 15 and trainingOwned > 0 and menu.pendingActionKind == nil
    local crewRow = tableWidget:addRow(true)
    local trainingName = track == "PILOT" and (recruit and recruit.seminar or "PILOT LESSON") or ("MARINE CREDIT - " .. tostring(nextTier) .. " STAR")
    local crewText = recruit and (recruit.name .. " | " .. track .. " " .. (skill and string.format("%.1f / 5", skill / 3) or "UNKNOWN") .. " | " .. trainingName .. " x" .. tostring(trainingOwned)) or "NO " .. track .. " TRAINEE SELECTED"
    crewRow[1]:setColSpan(2):createText(crewText, { color = recruit and headingColor or warningColor })
    crewRow[3]:setColSpan(2):createButton({ active = canTrain == true, bgColor = canTrain and requiredActionBackground or availableActionBackground }):setText("TRAIN ONE SESSION", { halign = "center" })
    if canTrain == true then
        crewRow[3].handlers.onClick = function()
            local current = selectedAcademyRecruit(track)
            if not current or not current.valid then
                rejectLocal("TRAINING BLOCKED - SELECTED " .. track .. " TRAINEE IS NO LONGER AVAILABLE | NOTHING CHANGED")
                return
            end
            auditAction("ACADEMY_TRAIN", tostring(current.id), track .. " TRAINING REQUEST SENT - ONE LESSON OR CREDIT MAXIMUM - SKILL READBACK REQUIRED", "ACADEMY_TRAIN_PENDING", track)
        end
    end
    actionRow(tableWidget, "Training supplies", "OPEN ACADEMY STORE", function() menu.page = "store"; menu.activeTab = "store"; rebuild(true) end, true, headingColor)

    if track == "PILOT" then
        section(tableWidget, "CAPTAIN ASSIGNMENT")
        textRow(tableWidget, "Eligibility", "Any shared trainee may be assigned to a proven captain vacancy while Pilot focus is selected.", passColor)
        local vacancy = selectedAcademyVacancy(academy.vacancies)
        if #academy.vacancies == 0 then
            textRow(tableWidget, "Destination", "No proven captain vacancy is available in the bounded scan.", warningColor)
        else
            local options = {}
            for _, issue in ipairs(academy.vacancies) do options[#options + 1] = { id = issue.key, text = issue.name .. " [" .. issue.idcode .. "] - " .. issue.sector, icon = "", displayremoveoption = false } end
            local row = tableWidget:addRow(true)
            row[1]:createText("Destination", { color = neutralColor })
            row[2]:setColSpan(3):createDropDown(options, { active = true, startOption = academy.selectedVacancyID, height = Helper.standardButtonHeight })
            row[2].handlers.onDropDownConfirmed = function(_, value) academy.selectedVacancyID = tostring(value or ""); academy.previewPair = nil; rebuild(false) end
        end
        vacancy = selectedAcademyVacancy(academy.vacancies)
        textRow(tableWidget, "Selected pair", recruit and vacancy and (recruit.name .. " -> " .. vacancy.name .. " [" .. vacancy.idcode .. "]") or "SELECT ONE PILOT AND ONE CAPTAIN VACANCY", recruit and vacancy and headingColor or warningColor)
        actionRow(tableWidget, "Assignment", "PREVIEW CAPTAIN ASSIGNMENT", function()
            local currentRecruit, currentVacancy = selectedAcademyRecruit("PILOT"), selectedAcademyVacancy(academy.vacancies)
            local shipLuaID = currentVacancy and componentLuaID(currentVacancy.component) or nil
            if not currentRecruit or not currentRecruit.valid or not shipLuaID then rejectLocal("CAPTAIN PREVIEW BLOCKED - SELECT ONE VALID PILOT AND ONE PROVEN VACANCY | NOTHING CHANGED"); return end
            academy.previewPair = tostring(currentRecruit.id) .. ":" .. currentVacancy.key
            auditAction("ACADEMY_PREVIEW_ASSIGN", tostring(currentRecruit.id), "CAPTAIN ASSIGNMENT PREVIEW REQUESTED - NOTHING CHANGED", "ACADEMY_ASSIGN_PREVIEW_PENDING", shipLuaID)
        end, recruit and recruit.valid and vacancy ~= nil and menu.pendingActionKind == nil, headingColor)
        local pair = recruit and vacancy and (tostring(recruit.id) .. ":" .. vacancy.key) or nil
        actionRow(tableWidget, "Assignment", "TRANSFER PILOT TO CAPTAIN POST", function()
            local currentRecruit, currentVacancy = selectedAcademyRecruit("PILOT"), selectedAcademyVacancy(academy.vacancies)
            local currentPair = currentRecruit and currentVacancy and (tostring(currentRecruit.id) .. ":" .. currentVacancy.key) or nil
            if not currentRecruit or currentPair ~= academy.previewPair or menu.plan.lastState ~= "ACADEMY_ASSIGN_READY" then rejectLocal("CAPTAIN TRANSFER BLOCKED - THE EXACT PAIR MUST PASS A FRESH PREVIEW | NOTHING CHANGED"); return end
            local shipLuaID = componentLuaID(currentVacancy.component)
            if not shipLuaID then rejectLocal("CAPTAIN TRANSFER BLOCKED - DESTINATION IDENTITY IS NO LONGER VALID | NOTHING CHANGED"); return end
            auditAction("ACADEMY_ASSIGN", tostring(currentRecruit.id), "CAPTAIN TRANSFER REQUEST SENT - EXACT PILOT READBACK REQUIRED", "ACADEMY_ASSIGN_PENDING", shipLuaID)
            academy.previewPair = nil
        end, pair and academy.previewPair == pair and menu.plan.lastState == "ACADEMY_ASSIGN_READY" and menu.pendingActionKind == nil, warningColor)
        actionRow(tableWidget, "Captain auto-fill", "PREVIEW RECRUIT / TRAIN / ASSIGN UP TO 25", function()
            academy.previewPair = nil
            academy.previewBulkFill = true
            auditAction("ACADEMY_PREVIEW_BULK_FILL", "BOUND_25", "CAPTAIN AUTO-FILL PREVIEW REQUESTED - NOTHING CHANGED", "ACADEMY_BULK_PREVIEW_PENDING")
        end, #academy.vacancies > 0 and menu.pendingActionKind == nil, headingColor)
        actionRow(tableWidget, "Captain auto-fill", "APPROVE RECRUIT / TRAIN / ASSIGN", function()
            academy.previewPair = nil
            auditAction("ACADEMY_BULK_ASSIGN", "SKILL_DESCENDING_BOUND_25", "CAPTAIN AUTO-FILL APPROVED - RECRUITMENT, TRAINING, AND NATIVE CAPTAIN READBACK REQUIRED", "ACADEMY_BULK_PENDING")
            academy.previewBulkFill = false
        end, academy.previewBulkFill and menu.plan.lastState == "ACADEMY_BULK_FILL_READY" and #academy.vacancies > 0 and menu.pendingActionKind == nil, warningColor)
    else
        section(tableWidget, "MARINE ASSIGNMENT")
        textRow(tableWidget, "Eligible destinations", "Any player-owned, non-mission ship with free personnel capacity. Each destination shows its FOC relationship, crew occupancy, and current Marine count.", passColor)
        local target = selectedMarineTarget(academy.marineTargets)
        if #academy.marineTargets == 0 then
            textRow(tableWidget, "Destination", "No eligible player ship currently has free personnel capacity.", warningColor)
        else
            local options = {}
            for _, ship in ipairs(academy.marineTargets) do options[#options + 1] = { id = ship.key, text = ship.relationship .. " | " .. ship.name .. " [" .. ship.idcode .. "] | CREW " .. ship.people .. "/" .. ship.capacity .. " | MARINES " .. ship.marines, icon = "", displayremoveoption = false } end
            local row = tableWidget:addRow(true)
            row[1]:createText("Destination", { color = neutralColor })
            row[2]:setColSpan(3):createDropDown(options, { active = true, startOption = academy.selectedMarineTargetID, height = Helper.standardButtonHeight })
            row[2].handlers.onDropDownConfirmed = function(_, value) academy.selectedMarineTargetID = tostring(value or ""); academy.previewPair = nil; rebuild(false) end
        end
        target = selectedMarineTarget(academy.marineTargets)
        textRow(tableWidget, "Ship role", target and target.relationship or "NO ELIGIBLE DESTINATION SELECTED", target and headingColor or warningColor)
        textRow(tableWidget, "Selected pair", recruit and target and (recruit.name .. " -> " .. target.name .. " [" .. target.idcode .. "]") or "SELECT ONE MARINE AND ONE ELIGIBLE DESTINATION", recruit and target and headingColor or warningColor)
        actionRow(tableWidget, "Assignment", "PREVIEW MARINE ASSIGNMENT", function()
            local currentRecruit, currentTarget = selectedAcademyRecruit("MARINE"), selectedMarineTarget(academy.marineTargets)
            local shipLuaID = currentTarget and componentLuaID(currentTarget.component) or nil
            if not currentRecruit or not currentRecruit.valid or not shipLuaID then rejectLocal("MARINE PREVIEW BLOCKED - SELECT ONE VALID MARINE AND ONE ELIGIBLE DESTINATION | NOTHING CHANGED"); return end
            academy.previewPair = tostring(currentRecruit.id) .. ":" .. currentTarget.key
            auditAction("ACADEMY_PREVIEW_MARINE_ASSIGN", tostring(currentRecruit.id), "MARINE ASSIGNMENT PREVIEW REQUESTED - NOTHING CHANGED", "ACADEMY_MARINE_PREVIEW_PENDING", shipLuaID)
        end, recruit and recruit.valid and target ~= nil and menu.pendingActionKind == nil, headingColor)
        local pair = recruit and target and (tostring(recruit.id) .. ":" .. target.key) or nil
        actionRow(tableWidget, "Assignment", "TRANSFER MARINE TO SELECTED SHIP", function()
            local currentRecruit, currentTarget = selectedAcademyRecruit("MARINE"), selectedMarineTarget(academy.marineTargets)
            local currentPair = currentRecruit and currentTarget and (tostring(currentRecruit.id) .. ":" .. currentTarget.key) or nil
            if not currentRecruit or currentPair ~= academy.previewPair or menu.plan.lastState ~= "ACADEMY_MARINE_ASSIGN_READY" then rejectLocal("MARINE TRANSFER BLOCKED - THE EXACT PAIR MUST PASS A FRESH PREVIEW | NOTHING CHANGED"); return end
            local shipLuaID = componentLuaID(currentTarget.component)
            if not shipLuaID then rejectLocal("MARINE TRANSFER BLOCKED - DESTINATION IDENTITY IS NO LONGER VALID | NOTHING CHANGED"); return end
            auditAction("ACADEMY_MARINE_ASSIGN", tostring(currentRecruit.id), "MARINE TRANSFER REQUEST SENT - ROLE AND CREW READBACK REQUIRED", "ACADEMY_MARINE_ASSIGN_PENDING", shipLuaID)
            academy.previewPair = nil
        end, pair and academy.previewPair == pair and menu.plan.lastState == "ACADEMY_MARINE_ASSIGN_READY" and menu.pendingActionKind == nil, warningColor)
    end
    textRow(tableWidget, "Last result", menu.plan.lastResult, needsAction(menu.plan.lastResult) and warningColor or passColor)
end

local function formatCredits(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    local formatted = text
    while true do
        local nextText, count = formatted:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
        formatted = nextText
        if count == 0 then break end
    end
    return formatted .. " Cr"
end

local function academyStorePage(tableWidget)
    section(tableWidget, "ACADEMY STORE")
    textRow(tableWidget, "Player balance", formatCredits(menu.store.balance), headingColor)
    textRow(tableWidget, "Pricing", "1-star 10,000 | 2-star 20,000 | 3-star 30,000 | 4-star 40,000 | 5-star 50,000 Cr", neutralColor)
    textRow(tableWidget, "Purchase policy", "All purchases are final. FOC verifies payment and delivery, but confirmed payments are never refunded.", warningColor)
    local function storeSection(label, kind, owned)
        section(tableWidget, label)
        for tier = 1, 5 do
            local price = tier * 10000
            local row = tableWidget:addRow(true)
            row[1]:createText(tostring(tier) .. " STAR", { color = headingColor })
            row[2]:createText("OWNED " .. tostring(owned[tier] or 0), { color = neutralColor })
            row[3]:createText(formatCredits(price), { color = menu.store.balance >= price and passColor or warningColor })
            row[4]:createButton({ active = menu.store.balance >= price and menu.pendingActionKind == nil, bgColor = menu.store.balance >= price and normalActionBackground or availableActionBackground }):setText("BUY 1", { halign = "center" })
            if menu.store.balance >= price and menu.pendingActionKind == nil then
                row[4].handlers.onClick = function() auditAction("ACADEMY_STORE_BUY", kind, kind .. " " .. tier .. "-STAR PURCHASE REQUESTED - PAYMENT AND DELIVERY READBACK REQUIRED", "ACADEMY_STORE_PENDING", tier) end
            end
        end
        actionRow(tableWidget, "Bundle", "BUY ALL FIVE " .. label .. " - " .. formatCredits(150000), function()
            auditAction("ACADEMY_STORE_BUY_ALL", kind, kind .. " FIVE-TIER BUNDLE REQUESTED - COMPLETE DELIVERY READBACK REQUIRED", "ACADEMY_STORE_PENDING")
        end, menu.store.balance >= 150000 and menu.pendingActionKind == nil, warningColor)
    end
    storeSection("PILOT LESSONS", "PILOT", menu.store.pilot)
    storeSection("MARINE CREDITS", "MARINE", menu.store.marine)
    section(tableWidget, "COMPLETE TRAINING BUNDLE")
    textRow(tableWidget, "Contents", "One Pilot Lesson and one Marine Credit at every tier: 10 training items total.", headingColor)
    actionRow(tableWidget, "Everything", "BUY ALL TRAINING - " .. formatCredits(300000), function()
        auditAction("ACADEMY_STORE_BUY_ALL", "ALL", "COMPLETE TEN-ITEM TRAINING BUNDLE REQUESTED - COMPLETE DELIVERY READBACK REQUIRED", "ACADEMY_STORE_PENDING")
    end, menu.store.balance >= 300000 and menu.pendingActionKind == nil, warningColor)
    textRow(tableWidget, "Last result", menu.plan.lastResult, needsAction(menu.plan.lastResult) and warningColor or passColor)
end

local function responsePage(tableWidget)
    local selected = menu.sample.fleets[menu.selectedFleet]
    local orders = selected and ordersForFleet(selected) or nil
    section(tableWidget, "FLEET RESPONSE RULES")
    textRow(tableWidget, "Distress ownership", "PLAYER-OWNED SHIPS AND STATIONS ONLY", passColor)
    textRow(tableWidget, "Eligibility", orders and ("Urgency " .. tostring(orders.distressUrgency) .. "+ | Ships at/below " .. tostring(orders.shipDamage) .. "% hull | Stations at/below " .. tostring(orders.stationDamage) .. "% hull | Range " .. orders.coverage .. " | Incident age 120 seconds") or "BLOCKED - SELECT A FLEET", neutralColor)
    textRow(tableWidget, "Dispatch bounds", "Closest eligible fleet: 1 | Named orders per incident: 1 | Reinforcements: NO | Whole-fleet ship cap: " .. tostring(menu.safety.responseCap), passColor)
    textRow(tableWidget, "Abort conditions", "Player control, mission/story protection, missing captain, non-combat without override, critical non-cancelable order, missing Home, stale incident, class disabled, threshold failure, or response-range failure.", passColor)
    actionRow(tableWidget, "Maintenance", "OPEN FLEET REPAIR / REPLACE / REBUILD", function() menu.page = "fleets"; menu.activeTab = "fleets"; menu.fleetMode = "maintenance"; requestMaintenanceSnapshot(selected) end, selected ~= nil, headingColor)
    actionRow(tableWidget, "Current orders", orders and orders.manualOverride and "PRESERVE CURRENT ORDERS - FOC BLOCKED" or "ALLOW FOC TO CANCEL / REPLACE ELIGIBLE ORDERS", function() orders.manualOverride = not orders.manualOverride; markFleetOrdersChanged(fleetKey(selected), orders); rebuild(false) end, selected ~= nil, warningColor)
    section(tableWidget, "DISPATCH DECISION")
    textRow(tableWidget, "Selection", "FOC re-resolves every saved reaction fleet at approval, filters locks and the " .. tostring(menu.safety.responseCap) .. "-ship cap, then chooses the lowest current gated distance. Saved list order and the currently viewed fleet do not decide.", headingColor)
    textRow(tableWidget, "Decision evidence", "Record distressed identity/source/location/age/ownership, every guard, closest eligible fleet or refusal, exact named order attempt, native readback, persistent lock, and resolution.", passColor)
    actionRow(tableWidget, "Response", "APPROVE ONE CLOSEST-ELIGIBLE DISPATCH", function()
        auditAction("APPROVE_DISPATCH", "GLOBAL CLOSEST", "EXCLUSIVE DISPATCH REQUEST SENT - ONE CLOSEST ELIGIBLE FLEET AND ONE NAMED ORDER MAXIMUM", "DISPATCH_PENDING")
    end, menu.pendingActionKind == nil, warningColor)
    if menu.plan.lastState == "ACTION_REQUIRED_DISPATCH" or menu.plan.lastState == "BLOCKED" then
        actionRequired(tableWidget,
            "FOC did not dispatch a fleet.",
            "There is no fresh unlocked incident or no saved fleet passed the current-distance, response-range, damage, urgency, safety, lock, and ship-cap guards.",
            "Open Fleets, confirm each fleet Home and distress settings, save its draft, then return while an active incident exists.",
            "fleets", "OPEN FLEETS")
    end
end

local function settingsPage(tableWidget)
    if FOCCapture then
        FOCCapture.onPolicy=function()
            if menu.shown == true and not menu.minimized and menu.frame and not menu.closeInProgress and menu.page == "settings" and not menu.recoveryDropdown then rebuild(false) end
        end
        FOCCapture.render(tableWidget,actionRow,textRow,passColor,warningColor)
    end
    if FOCRecovery then
        FOCRecovery.onPolicy = function()
            if menu.frame and menu.page == "settings" and not menu.recoveryDropdown then rebuild(false) end
        end
        FOCRecovery.render(tableWidget, actionRow, textRow, passColor, warningColor)
    end
    section(tableWidget, "GLOBAL AUTOMATION")
    dropdownRow(tableWidget, "Master mode", automationModes, menu.plan.authority, function(value)
        menu.plan.authority = tostring(value)
        menu.plan.status = "DRAFT"
        auditAction("MODE_CHANGE", "GLOBAL", "MASTER MODE CHANGED TO " .. menu.plan.authority .. " - NO PLAN WAS APPLIED", "AUTHORITY_CHANGED")
        return false
    end)
    local modeMeaning = menu.plan.authority == "PREVIEW PLAN" and "PLANNER PREVIEW ONLY. The two recovery opt-ins above are independent; STOP disables all."
        or menu.plan.authority == "APPLY APPROVED PLAN" and "ARMED - THIS TOGGLE SENDS NOTHING. Return to Command and press APPLY APPROVED PLAN - SEND ORDERS."
        or "FULL AUTOMATION AUTHORIZED - the bounded scheduler may send eligible orders automatically."
    textRow(tableWidget, "Mode meaning", modeMeaning, menu.plan.authority == "PREVIEW PLAN" and warningColor or passColor)
    actionRow(tableWidget, "Plan", "PREVIEW CURRENT PLAN", previewGlobalPlan, true, headingColor)
    local stopped = menu.plan.status == "STOPPED" and menu.plan.authority == "PREVIEW PLAN" and not (FOCRecovery and (FOCRecovery.policy.repair or FOCRecovery.policy.shelter))
    actionRow(tableWidget, "Emergency", stopped and "FOC AUTOMATION ALREADY STOPPED" or "STOP FOC AUTOMATION", function() menu.plan.authority = "PREVIEW PLAN"; menu.plan.status = "STOPPED"; auditAction("STOP_AUTOMATION", "GLOBAL", "FOC AUTOMATION STOPPED - PERSISTENT READBACK REQUIRED", "STOPPED") end, not stopped, warningColor)
    textRow(tableWidget, "Planner duties", "Inventory ships/personnel; fill proven vacancies; preserve locks; identify grouped ships; choose commanders/roles/names/homes; spread coverage; route patrols; retain reserve; warn on gaps, overlap, and overextension.", neutralColor)
    textRow(tableWidget, "Replacement boundary", "Destroyed-member replacement may create a recommendation only. No purchase, construction, credit spend, or staffing guess is authorized.", passColor)
    textRow(tableWidget, "Rebalance threshold", "25% minimum modeled benefit; 30 second cooldown; duplicate suppression; bounded backoff; maximum one native mutation per cycle.", neutralColor)
    section(tableWidget, "READINESS AND EMERGENCY POLICY")
    dropdownRow(tableWidget, "Emergency retreat", { "OFF", "ON" }, menu.operations.retreat, function(value) menu.operations.retreat = tostring(value) end)
    dropdownRow(tableWidget, "Retreat below", damageOptions, menu.operations.retreatHull, function(value) menu.operations.retreatHull = tonumber(value) or 30 end, "% commander hull")
    dropdownRow(tableWidget, "Return afterward", yesNoOptions, menu.operations.retreatReturn, function(value) menu.operations.retreatReturn = tostring(value) end)
    textRow(tableWidget, "Retreat safety", "When ON, FOC may issue X4's native Flee order only to an enrolled active fleet after exact attacker, hull, ownership, pilot, story, player-control, current-order and duplicate-lock checks. Cargo is never dropped.", warningColor)
    dropdownRow(tableWidget, "Commander hull minimum", repairThresholdOptions, menu.operations.commanderHull, function(value) menu.operations.commanderHull = tonumber(value) or 50 end, "%")
    dropdownRow(tableWidget, "Fleet hull minimum", repairThresholdOptions, menu.operations.fleetHull, function(value) menu.operations.fleetHull = tonumber(value) or 50 end, "%")
    dropdownRow(tableWidget, "Captain coverage minimum", repairThresholdOptions, menu.operations.captainCoverage, function(value) menu.operations.captainCoverage = tonumber(value) or 100 end, "%")
    dropdownRow(tableWidget, "Maximum fleet size", responseFleetCapOptions, menu.operations.maxFleetSize, function(value) menu.operations.maxFleetSize = tonumber(value) or 100 end, " ships")
    actionRow(tableWidget, "Save policy", "SAVE READINESS AND EMERGENCY POLICY", function()
        auditAction("OPERATIONS_POLICY_SAVE", "GLOBAL", "OPERATIONS POLICY SAVE REQUESTED - PERSISTENT READBACK REQUIRED", "OPERATIONS_POLICY_PENDING", { menu.operations.retreat, menu.operations.retreatHull, menu.operations.retreatReturn, menu.operations.commanderHull, menu.operations.fleetHull, menu.operations.captainCoverage, menu.operations.maxFleetSize, menu.operations.preset })
    end, not menu.pendingActionKind, passColor)
    section(tableWidget, "HARD PERFORMANCE AND SAFETY LIMITS")
    textRow(tableWidget, "Fleet source", "Authoritative MD structural discovery - all eligible commanders and all subordinates", passColor)
    textRow(tableWidget, "Fleet registry", "All authoritative eligible rows; paged 16 at a time", neutralColor)
    textRow(tableWidget, "Fleet members", "All living non-unit subordinates supplied by MD", neutralColor)
    textRow(tableWidget, "History limit", tostring(HISTORY_LIMIT), neutralColor)
    textRow(tableWidget, "Live activity limit", tostring(LIVE_ACTIVITY_LIMIT) .. " retained | " .. tostring(LIVE_ACTIVITY_VISIBLE) .. " shown", neutralColor)
    textRow(tableWidget, "Scheduler", "No per-frame scan or mutation. Open/refresh inventory is bounded; automation requests are cooldown guarded.", passColor)
    textRow(tableWidget, "Runtime status", "RUNTIME ACCEPTANCE REQUIRED", warningColor)
end

local function activityPage(tableWidget)
    buttonPairRow(tableWidget, "LIVE ACTIVITY", function() menu.activityView = "live"; rebuild(false) end,
        "SESSION HISTORY", function() menu.activityView = "history"; AddUITriggeredEvent(menu.name, "activity_snapshot", nil); rebuild(false) end,
        menu.activityView == "history" and passColor or headingColor, true, true)
    if menu.activityView == "live" then
        section(tableWidget, "LIVE ACTIVITY - NEWEST FIRST")
        textRow(tableWidget, "Boundary", "Latest " .. tostring(LIVE_ACTIVITY_VISIBLE) .. " shown | " .. tostring(LIVE_ACTIVITY_LIMIT) .. " retained | oldest entries roll off automatically", passColor)
        if #menu.liveActivity == 0 then
            textRow(tableWidget, "Status", "No FOC activity has been recorded yet. Distress detection, responses, patrol results, and completed actions appear here immediately.", warningColor)
        end
        for index = 1, math.min(#menu.liveActivity, LIVE_ACTIVITY_VISIBLE) do
            local entry = menu.liveActivity[index]
            local red = entry.severity == "RED_DAMAGE"
            local yellow = entry.severity == "YELLOW_DISTRESS"
            local activityColor = red and criticalColor or yellow and warningColor or headingColor
            local stateColor = red and criticalColor or yellow and warningColor or (needsAction(entry.state) and warningColor or passColor)
            local detailColor = red and criticalColor or yellow and warningColor or (needsAction(entry.detail) and warningColor or passColor)
            local row = tableWidget:addRow(false)
            row[1]:createText(formatGameTime(entry.time) .. "\nACTIVITY " .. tostring(entry.id), { color = activityColor })
            row[2]:createText(entry.kind .. " | " .. entry.state, { color = stateColor })
            row[3]:createText(entry.subject, { wordwrap = true, color = red and criticalColor or yellow and warningColor or nil })
            row[4]:createText(entry.detail, { wordwrap = true, color = detailColor })
        end
        section(tableWidget, "AFTER-ACTION REPORTS")
        textRow(tableWidget, "Boundary", "Latest resolved incidents are saved with honest UNKNOWN fields and a 50-report limit.", passColor)
        if #menu.afterActionReports == 0 then textRow(tableWidget, "Reports", "NO RESOLVED INCIDENT REPORT HAS BEEN RECORDED", neutralColor) end
        for index = #menu.afterActionReports, math.max(1, #menu.afterActionReports - 4), -1 do
            local report = menu.afterActionReports[index]
            if report then textRow(tableWidget, "REPORT " .. tostring(report[1]), "Victim: " .. safeText(report[5], "UNKNOWN") .. " | Attacker: " .. safeText(report[6], "UNKNOWN") .. " | Fleet: " .. safeText(report[7], "UNKNOWN") .. "\nOutcome: " .. safeText(report[8], "UNKNOWN") .. " | Losses: " .. safeText(report[9], "UNKNOWN") .. " | Damage: " .. safeText(report[10], "UNKNOWN"), neutralColor) end
        end
    else
        section(tableWidget, "SESSION HISTORY - RECORDED ACTIVITY")
        local rows, newer = menu.historyRows()
        textRow(tableWidget, "Retention", "Latest 50 events saved | Refresh reloads events, not diagnostics | " .. tostring(newer) .. " newer entries: return to page 1", headingColor)
        local first, last = addPager(tableWidget, "activity.history", #rows, { fixedRows = 10, rowUnits = 8, contentPixels = menu.listContentHeight, maximum = 8 })
        if #rows == 0 then textRow(tableWidget, "History", "NO RECORDED ACTIVITY YET", neutralColor) end
        for index = first, last do
            local entry = rows[index]
            if entry then
                local color = entry.severity == "RED_DAMAGE" and criticalColor or entry.severity == "YELLOW_DISTRESS" and warningColor or neutralColor
                local luaid, sectorOnly = menu.historyTarget(entry)
                local row = tableWidget:addRow(true)
                menu.historyMapButton(row, entry, color, luaid ~= nil and not menu.pendingActionKind and not menu.carrierTransaction, sectorOnly)
                row[2]:createText(formatGameTime(entry.time) .. "\n" .. entry.kind:sub(1, 40) .. " | " .. entry.state:sub(1, 64), { color = color, wordwrap = true })
                row[3]:createText(entry.subject:sub(1, 80) .. (luaid and "" or "\nMap identity unavailable"), { color = color, wordwrap = true })
                row[4]:createText(entry.detail:sub(1, 240) .. (#entry.detail > 240 and "..." or ""), { wordwrap = true, color = color })
            end
        end
    end
end

buildOperationsIntel = function()
    local sectors, order, unlocated = {}, {}, 0
    local function ensure(name, sectorID)
        name = safeText(name, "UNKNOWN")
        if name == "UNKNOWN" or name == "UNKNOWN SECTOR" then return nil end
        if not sectors[name] then
            sectors[name] = { name = name, id = sectorID and tostring(sectorID) or nil, score = 0, events = {}, fleets = {}, homes = {}, critical = 0, degraded = 0 }
            order[#order + 1] = sectors[name]
        elseif sectorID and not sectors[name].id then
            sectors[name].id = tostring(sectorID)
        end
        return sectors[name]
    end
    local fleetIndex = {}
    for _, fleet in ipairs(menu.sample and menu.sample.fleets or {}) do
        local sector = ensure(fleet.commander.sector, fleet.commander.sectorID)
        if sector then
            sector.fleets[#sector.fleets + 1] = fleet.commander.fleetname
            if fleet.status == "CRITICAL" then sector.score = sector.score + 5; sector.critical = sector.critical + 1
            elseif fleet.status == "DEGRADED" then sector.score = sector.score + 2; sector.degraded = sector.degraded + 1 end
        end
        fleetIndex[#fleetIndex + 1] = { name = string.lower(fleet.commander.name), sector = fleet.commander.sector }
        fleetIndex[#fleetIndex + 1] = { name = string.lower(fleet.commander.fleetname), sector = fleet.commander.sector }
        for _, member in ipairs(fleet.members or {}) do fleetIndex[#fleetIndex + 1] = { name = string.lower(member.name), sector = member.sector } end
        local home = menu.homeSectorByFleet[fleetKey(fleet)]
        local homeSector = home and ensure(home.text)
        if homeSector then homeSector.homes[#homeSector.homes + 1] = fleet.commander.fleetname end
    end
    local now = tonumber(menu.gameTime) or 0
    for _, entry in ipairs(menu.liveActivity or {}) do if tonumber(entry.time) and entry.time > now then now = entry.time end end
    local cutoff = tonumber(menu.operationsMap.window) or 60
    for _, observation in ipairs(menu.mapPirateObservations or {}) do
        local ageMinutes = math.max(0, (now - (tonumber(observation.time) or now)) / 60)
        if ageMinutes <= cutoff then
            local located = ensure(observation.sectorName, observation.sector)
            if located then
                local weight = observation.severity == "RED_DAMAGE" and 5 or 2
                located.score = located.score + weight
                located.events[#located.events + 1] = {
                    time = observation.time, kind = "PIRATE_ACTIVITY", state = "OBSERVED",
                    subject = observation.attacker, detail = observation.faction .. " attack observed in " .. observation.sectorName,
                    severity = observation.severity,
                }
            end
        end
    end
    for _, traversal in ipairs(menu.mapPatrolTraversals or {}) do
        local ageMinutes = math.max(0, (now - (tonumber(traversal.time) or now)) / 60)
        if ageMinutes <= cutoff then
            local fromSector = ensure(traversal.fromName, traversal.from)
            local toSector = ensure(traversal.toName, traversal.to)
            if fromSector then fromSector.fleets[#fromSector.fleets + 1] = traversal.commander end
            if toSector then toSector.fleets[#toSector.fleets + 1] = traversal.commander end
        end
    end
    for _, entry in ipairs(menu.liveActivity or {}) do
        local ageMinutes = math.max(0, (now - (tonumber(entry.time) or now)) / 60)
        if ageMinutes <= cutoff then
            local haystack = string.lower(safeText(entry.subject, "") .. " " .. safeText(entry.detail, ""))
            local located
            for _, candidate in ipairs(fleetIndex) do
                if candidate.name ~= "" and haystack:find(candidate.name, 1, true) then located = ensure(candidate.sector); if located then break end end
            end
            if not located then
                for _, candidate in ipairs(order) do
                    if haystack:find(string.lower(candidate.name), 1, true) then located = candidate; break end
                end
            end
            if located then
                local weight = entry.severity == "RED_DAMAGE" and 5 or entry.severity == "YELLOW_DISTRESS" and 2 or 0
                located.score = located.score + weight
                located.events[#located.events + 1] = entry
            elseif entry.severity == "RED_DAMAGE" or entry.severity == "YELLOW_DISTRESS" then
                unlocated = unlocated + 1
            end
        end
    end
    table.sort(order, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.name < b.name end)
    return order, unlocated
end

local function operationsMapPage(tableWidget)
    section(tableWidget, "INTERACTIVE EXECUTIVE OPERATIONS MAP - SECTOR INTELLIGENCE BOARD")
    textRow(tableWidget, "Boundary", "This is an FOC strategic board, not X4's native spatial map. Every cell comes from current fleet/home evidence and retained FOC observations; missing attribution stays UNKNOWN.", passColor)
    dropdownRow(tableWidget, "Show", operationsMapFilters, menu.operationsMap.filter, function(value) menu.operationsMap.filter = tostring(value); menu.operationsMap.selected = nil; rebuild(true) end)
    dropdownRow(tableWidget, "Observation window", operationsMapWindows, menu.operationsMap.window, function(value) menu.operationsMap.window = tonumber(value) or 60; menu.operationsMap.selected = nil; rebuild(true) end, " minutes")
    local intel, unlocated = buildOperationsIntel()
    local visible = {}
    for _, sector in ipairs(intel) do
        if menu.operationsMap.filter == "OVERVIEW" or (menu.operationsMap.filter == "PIRATE ACTIVITY" and sector.score > 0) or (menu.operationsMap.filter == "HEAVY PATROL ROUTES" and #sector.fleets > 0) or (menu.operationsMap.filter == "FLEET HOMES" and #sector.homes > 0) then visible[#visible + 1] = sector end
    end
    local matched = #visible
    while #visible > 20 do table.remove(visible) end
    textRow(tableWidget, "Readback", tostring(#visible) .. " OF " .. tostring(matched) .. " MATCHING SECTOR(S) SHOWN | TOP 20 BY RISK | " .. tostring(unlocated) .. " THREAT OBSERVATION(S) UNLOCATED AND NOT FABRICATED", unlocated > 0 and warningColor or passColor)
    section(tableWidget, "SELECT A SECTOR")
    if #visible == 0 then textRow(tableWidget, "Result", "NO SECTORS MATCH THIS FILTER AND OBSERVATION WINDOW", warningColor) end
    for index = 1, #visible, 2 do
        local row = tableWidget:addRow(true)
        for slot = 0, 1 do
            local sector = visible[index + slot]
            if sector then
                local level = sector.score >= 10 and "CRITICAL" or sector.score >= 4 and "HIGH" or sector.score > 0 and "ELEVATED" or "QUIET"
                local bg = level == "CRITICAL" and failedActionBackground or level == "HIGH" and requiredActionBackground or level == "ELEVATED" and pointerActionBackground or confirmedActionBackground
                local cell = slot == 0 and 1 or 3
                row[cell]:setColSpan(2):createButton({ active = true, bgColor = bg }):setText(sector.name .. " | " .. level .. " | SCORE " .. tostring(sector.score) .. " | " .. tostring(#sector.events) .. " OBS", { halign = "center" })
                row[cell].handlers.onClick = function() menu.operationsMap.selected = sector.name; menu.notice = "OPERATIONS MAP SECTOR SELECTED - " .. sector.name; rebuild(false) end
            end
        end
    end
    local selected
    for _, sector in ipairs(intel) do if sector.name == menu.operationsMap.selected then selected = sector; break end end
    if not selected and visible[1] then selected = visible[1]; menu.operationsMap.selected = selected.name end
    section(tableWidget, "SELECTED-SECTOR INTELLIGENCE")
    if selected then
        local level = selected.score >= 10 and "CRITICAL" or selected.score >= 4 and "HIGH" or selected.score > 0 and "ELEVATED" or "QUIET"
        textRow(tableWidget, "Sector", selected.name .. " | THREAT " .. level .. " | SCORE " .. tostring(selected.score), selected.score >= 10 and criticalColor or selected.score > 0 and warningColor or passColor)
        textRow(tableWidget, "Fleet presence", #selected.fleets > 0 and table.concat(selected.fleets, ", ") or "NO CURRENT FOC FLEET EVIDENCE", #selected.fleets > 0 and headingColor or neutralColor)
        textRow(tableWidget, "Saved home coverage", #selected.homes > 0 and table.concat(selected.homes, ", ") or "NO SAVED FOC HOME IN THIS SECTOR", #selected.homes > 0 and passColor or neutralColor)
        textRow(tableWidget, "Readiness", tostring(selected.critical) .. " CRITICAL | " .. tostring(selected.degraded) .. " DEGRADED", selected.critical > 0 and criticalColor or selected.degraded > 0 and warningColor or passColor)
        for index = 1, math.min(4, #selected.events) do
            local entry = selected.events[index]
            textRow(tableWidget, "Observation " .. tostring(index), entry.kind .. " | " .. entry.state .. " | " .. entry.subject .. "\n" .. entry.detail, entry.severity == "RED_DAMAGE" and criticalColor or warningColor)
        end
    else
        textRow(tableWidget, "Sector", "NO SECTOR SELECTED", neutralColor)
    end
    buttonPairRow(tableWidget, "OPEN ACTIVITY EVIDENCE", function() menu.page = "activity"; menu.activeTab = "activity"; rebuild(true) end,
        "OPEN FLEET RESPONSE", function() menu.page = "response"; menu.activeTab = "response"; rebuild(true) end,
        headingColor, true, true)
end

local function configureColumns(tableWidget, width)
    local columnWidth = math.floor((width - 4 * Helper.borderSize) / 4)
    tableWidget:setColWidth(1, columnWidth, false)
    tableWidget:setColWidth(2, columnWidth, false)
    tableWidget:setColWidth(3, columnWidth, false)
    tableWidget:setDefaultCellProperties("text", { fontsize = Helper.standardFontSize })
end

function menu.create()
    menu.feedbackRedraw, menu.deferredRedraw, menu.deferredResetScroll = nil, nil, nil
    Helper.clearDataForRefresh(menu, config.layer)
    local maxWidth = math.max(600, math.min(Helper.scaleX(config.maxWidth), Helper.viewWidth - 2 * Helper.borderSize))
    local maxHeight = math.max(420, math.min(Helper.scaleY(config.maxHeight), Helper.viewHeight - 2 * Helper.borderSize))
    local width = clamp(math.floor(Helper.viewWidth * config.widthRatio), math.min(Helper.scaleX(config.minWidth), maxWidth), maxWidth)
    local height = clamp(math.floor(Helper.viewHeight * config.heightRatio), math.min(Helper.scaleY(config.minHeight), maxHeight), maxHeight)
    menu.frame = Helper.createFrameHandle(menu, { layer = config.layer, x = (Helper.viewWidth - width) / 2, y = (Helper.viewHeight - height) / 2, width = width, height = height })
    menu.frame:setBackground("solid", { color = frameBackground })
    local headerHeight = createHeader(menu.frame, width)
    local contentY = Helper.borderSize + headerHeight + Helper.borderSize
    local contentHeight = height - contentY - 2 * Helper.borderSize
    menu.listContentHeight = contentHeight
    local contentWidth = width - 2 * Helper.borderSize
    menu.listContentWidth = contentWidth
    if menu.page == "fleets" then
        local paneGap = 2 * Helper.borderSize
        local fleetWidth = math.floor(contentWidth * 0.27)
        local ordersWidth = contentWidth - fleetWidth - paneGap
        local fleetTable = menu.frame:addTable(4, { tabOrder = 2, x = Helper.borderSize, y = contentY, width = fleetWidth, reserveScrollBar = true, borderEnabled = true })
        configureColumns(fleetTable, fleetWidth)
        fleetTable.properties.maxVisibleHeight = contentHeight
        local ordersTable = menu.frame:addTable(4, { tabOrder = 3, x = Helper.borderSize + fleetWidth + paneGap, y = contentY, width = ordersWidth, reserveScrollBar = true, borderEnabled = true })
        configureColumns(ordersTable, ordersWidth)
        ordersTable.properties.maxVisibleHeight = contentHeight
        menu.fleetTable = fleetTable
        menu.mainTable = ordersTable
        fleetSelectorPane(fleetTable)
        if menu.fleetMode == "maintenance" then fleetMaintenancePane(ordersTable) elseif menu.fleetMode == "thresholds" then fleetSafetyPane(ordersTable) else fleetOrdersPane(ordersTable) end
        if menu.restoreTopRow then pcall(ordersTable.setTopRow, ordersTable, menu.restoreTopRow) end
        menu.restoreTopRow = nil
        menu.frame:display()
        menu.renderedPage = menu.page
        return
    end
    menu.fleetTable = nil
    local tableWidget = menu.frame:addTable(4, { tabOrder = 2, x = Helper.borderSize, y = contentY, width = contentWidth, reserveScrollBar = true, borderEnabled = true })
    configureColumns(tableWidget, contentWidth)
    tableWidget.properties.maxVisibleHeight = contentHeight
    menu.mainTable = tableWidget
    if menu.page ~= 'shipyard' and menu.page ~= 'command' and not (menu.page == 'taskforces' and menu.strategic.view == 'COVERAGE AND FLEET TEMPLATES' and (FOC_Advisor.step == 'NPC' or FOC_Advisor.step == 'PROCUREMENT')) then pageGuide(tableWidget) end
    if menu.page == "command" then commandPage(tableWidget)
    elseif menu.page == 'shipyard' then menu.shipyardPage(tableWidget)
    elseif menu.page == "taskforces" then menu.taskForcesPage(tableWidget)
    elseif menu.page == "readiness" then readinessPage(tableWidget)
    elseif menu.page == "academy" then academyPage(tableWidget)
    elseif menu.page == "store" then academyStorePage(tableWidget)
    elseif menu.page == "response" then responsePage(tableWidget)
    elseif menu.page == "activity" then activityPage(tableWidget)
    elseif menu.page == "operationsmap" then operationsMapPage(tableWidget)
    else settingsPage(tableWidget) end
    if menu.restoreTopRow then pcall(tableWidget.setTopRow, tableWidget, menu.restoreTopRow) end
    menu.restoreTopRow = nil
    menu.frame:display()
    menu.renderedPage = menu.page
end

function menu.onDropDownActivated()
    menu.recoveryDropdown = true
end

function menu.onDropDownRemoved()
    menu.recoveryDropdown = false
end

function menu.onDropDownDeactivated()
    menu.recoveryDropdown = false
end

function menu.refresh(preserveScroll)
    if preserveScroll ~= false and menu.mainTable and menu.mainTable.id then
        local ok, top = pcall(GetTopRow, menu.mainTable.id)
        if ok then menu.restoreTopRow = top end
    end
    menu.create()
end

function menu.onShowMenu(state)
    menu.recoveryDropdown = false
    menu.purchaseEpoch = (menu.purchaseEpoch or 0) + 1
    -- Native Helper return must not replay the older MD launch snapshot over drafts.
    if menu.restoreFleetInspection(state) then return end
    menu.historyWindow, menu.activitySnapshot, menu.liveActivityIncoming = nil, nil, nil
    menu.listPages["activity.history"] = 1
    menu.param = menu.param or {}
    menu.param[1] = tonumber(menu.param[1]) or 0
    menu.param[2] = tonumber(menu.param[2]) or 0
    if menu.param[6] == "PREVIEW PLAN" or menu.param[6] == "APPLY APPROVED PLAN" or menu.param[6] == "FULL AUTOMATION" then menu.plan.authority = menu.param[6] end
    if menu.param[7] and tostring(menu.param[7]) ~= "" then menu.plan.lastResult = tostring(menu.param[7]) end
    if menu.param[8] and tostring(menu.param[8]) ~= "" then menu.plan.lastState = tostring(menu.param[8]) end
    if menu.plan.lastState == "ACADEMY_MARINE_TRANSFER_PENDING" then menu.pendingActionKind = "ACADEMY_MARINE_ASSIGN" end
    if menu.plan.lastState == "STOPPED" then menu.plan.status = "STOPPED" end
    local authoritativeDraftRows = type(menu.param[9]) == "table"
    if authoritativeDraftRows then
        menu.ordersByFleet = {}
        menu.homeSectorByFleet = {}
        menu.draftsByFleet = {}
        menu.pendingDraftSaves = {}
    end
    local restoredDrafts = restorePersistentDrafts(menu.param[9])
    if type(menu.param[11]) == "table" then loadAcademyRows(menu.param[11]) end
    if type(menu.param[12]) == "table" then loadProtectedShipIDs(menu.param[12]) end
    if type(menu.param[13]) == "table" then loadVacancyRows(menu.param[13]) end
    if type(menu.param[14]) == "table" then loadMarineTargetRows(menu.param[14]) end
    if type(menu.param[15]) == "table" then loadStoreData(menu.param[15]) end
    if type(menu.param[16]) == "table" then loadLiveActivityRows(menu.param[16]) end
    if type(menu.param[17]) == "table" then
        local thresholds = menu.param[17]
        menu.safety.reactionRepair = tonumber(thresholds[2]) or 100
        menu.safety.playerRepair = tonumber(thresholds[3]) or 100
        menu.safety.responseCap = tonumber(thresholds[4]) or 100
        menu.safety.dirty = false
    end
    if type(menu.param[18]) == "table" then loadStructuralFleetRows(menu.param[18]) end
    if type(menu.param[19]) == "table" then loadStoryOverrideIDs(menu.param[19]) end
    if type(menu.param[20]) == "table" then loadStoryAnsweredIDs(menu.param[20]) end
    if type(menu.param[21]) == "table" then menu.taskForces = menu.param[21] end
    for _, force in ipairs(menu.taskForces) do
        if tostring(force[7] or "") == "" then force[7] = nil end
        if tostring(force[8] or "") == "" then force[8] = nil end
        if type(force[9]) ~= "table" then force[9] = {} else for index, member in ipairs(force[9]) do force[9][index] = tostring(member) end end
    end
    if type(menu.param[22]) == "table" then menu.templates = menu.param[22] end
    if type(menu.param[23]) == "table" then menu.afterActionReports = menu.param[23] end
    if type(menu.param[24]) == "table" then
        local policy = menu.param[24]
        menu.operations.retreat = tostring(policy[2] or "OFF")
        menu.operations.retreatHull = tonumber(policy[3]) or 30
        menu.operations.retreatReturn = tostring(policy[4] or "YES")
        menu.operations.commanderHull = tonumber(policy[5]) or 50
        menu.operations.fleetHull = tonumber(policy[6]) or 50
        menu.operations.captainCoverage = tonumber(policy[7]) or 100
        menu.operations.maxFleetSize = tonumber(policy[8]) or 100
        menu.operations.preset = tostring(policy[9] or "MANUAL ORDERS ONLY")
    end
    menu.gameTime = tonumber(menu.param[25]) or menu.gameTime or 0
    if type(menu.param[26]) == "table" then loadMapPirateObservations(menu.param[26]) end
    if type(menu.param[27]) == "table" then loadMapPatrolTraversals(menu.param[27]) end
    if type(menu.param[28]) == "table" then loadMapGateEdges(menu.param[28]) end
    if authoritativeDraftRows and restoredDrafts > 0 then
        menu.notice = "RESTORED " .. tostring(restoredDrafts) .. " SAVED FLEET DRAFT(S) FROM THE GAME SAVE"
        DebugError("[FOC][B048][DRAFT_RESTORE] schema=3_or_4 ownership=MD_NATIVE_OBJECT restored=" .. tostring(restoredDrafts) .. " mutation=NONE")
    elseif authoritativeDraftRows then
        DebugError("[FOC][B048][DRAFT_RESTORE] schema=3_or_4 ownership=MD_NATIVE_OBJECT restored=0 reason=NO_SAVED_DRAFTS mutation=NONE")
    end
    if menu.pendingHomeSelection then
        menu.pendingHomeSelection = nil
        menu.homeReturnMetadata = nil
        menu.plan.lastResult = "HOME POINT NOT CHANGED - FOC MAP CLOSED WITHOUT SELECTING A POINT"
    end
    menu.page = menu.page or "command"
    sampleFleets("OPEN")
    menu.restoreFleetKey = menu.param[10] or menu.restoreFleetKey
    if menu.restoreFleetKey then
        for index, fleet in ipairs(menu.sample.fleets) do
            if fleetKey(fleet) == tostring(menu.restoreFleetKey) then menu.selectedFleet = index; break end
        end
        menu.restoreFleetKey = nil
    end
    AddUITriggeredEvent(menu.name, "strategic_refresh", nil)
    if menu.page == "taskforces" and menu.plan.lastResult then menu.notice = menu.plan.lastResult end
    menu.create()
    AddUITriggeredEvent(menu.name, "activity_snapshot", nil)
end

function menu.onCloseElement(reason, layer)
    if menu.frame == nil or menu.closeInProgress then return end
    menu.closeInProgress = true
    AddUITriggeredEvent(menu.name, "closed", { reason = reason or "close" })
    Helper.closeMenu(menu, reason or "close", layer)
    menu.frame = nil
    menu.closeInProgress = false
end

function menu.onUpdate()
    if menu.page == 'taskforces' and menu.strategic.view == 'COVERAGE AND FLEET TEMPLATES' and FOC_Advisor.step == 'NPC' and (menu.shown ~= true or menu.minimized or menu.closeInProgress) then return end
    if menu.frame and menu.page == "command" and FOC_Plan then FOC_Plan.tick() end
    if menu.planRedraw and menu.frame and not menu.closeInProgress and not menu.recoveryDropdown and menu.page == "command" then
        menu.planRedraw = false
        rebuild(false)
    end
    if menu.advisorWorkspaceActive() and not menu.recoveryDropdown then
        FOC_Advisor.tick()
        if menu.page == 'shipyard' then FOC_Shipyard.tick() end
        if menu.advisorRedraw then menu.advisorRedraw=nil; rebuild(false) end
    end
    if menu.frame and not menu.closeInProgress and not menu.recoveryDropdown and (menu.feedbackRedraw or menu.deferredRedraw) then
        rebuild(menu.deferredResetScroll == true)
    end
end

function menu.strategicSnapshotBegin()
    menu.strategicIncoming = { assets = {}, observations = {}, records = { carriers = {}, carrierwings = {}, grids = {}, convoys = {}, logistics = {}, assaults = {} }, wingKeys = {}, wingInvalid = false, asset = nil, observation = nil, record = nil }
end

function menu.strategicAssetBegin()
    if menu.strategicIncoming then menu.strategicIncoming.asset = {} end
end
function menu.strategicAssetValue(field, value)
    if menu.strategicIncoming and menu.strategicIncoming.asset then menu.strategicIncoming.asset[field] = value end
end
function menu.strategicAssetCommit()
    if not menu.strategicIncoming then return end
    local row = menu.strategicIncoming.asset
    menu.strategicIncoming.asset = nil
    if not row or not row.component or not row.idcode or row.idcode == "" or not row.kind or not row.name then return end
    menu.strategicIncoming.assets[#menu.strategicIncoming.assets + 1] = {
        kind = tostring(row.kind), component = row.component, idcode = tostring(row.idcode), name = tostring(row.name),
        purpose = tostring(row.purpose or "UNKNOWN"), sector = tostring(row.sector or "UNKNOWN"), order = tostring(row.order or "UNKNOWN"),
        commander = tostring(row.commander or ""), hull = tonumber(row.hull), shield = tonumber(row.shield),
    }
end
function menu.strategicObservationBegin()
    if menu.strategicIncoming then menu.strategicIncoming.observation = {} end
end
function menu.strategicObservationValue(field, value)
    if menu.strategicIncoming and menu.strategicIncoming.observation then menu.strategicIncoming.observation[field] = value end
end
function menu.strategicObservationCommit()
    if not menu.strategicIncoming then return end
    local row = menu.strategicIncoming.observation
    menu.strategicIncoming.observation = nil
    if not row or not row.kind or row.time == nil or not row.sector or not row.sectorid or not row.subject or row.amount == nil or row.severity == nil or row.detail == nil then return end
    menu.strategicIncoming.observations[#menu.strategicIncoming.observations + 1] = {
        kind = tostring(row.kind), time = tonumber(row.time) or 0, sector = tostring(row.sector), sectorid = tostring(row.sectorid),
        subject = tostring(row.subject), amount = tonumber(row.amount) or 0, severity = tonumber(row.severity) or 0, detail = tostring(row.detail),
    }
end
function menu.strategicRecordBegin()
    if menu.strategicIncoming then menu.strategicIncoming.record = {} end
end
function menu.strategicRecordValue(index, value)
    if menu.strategicIncoming and menu.strategicIncoming.record then menu.strategicIncoming.record[index] = value end
end
function menu.strategicRecordCommit()
    if not menu.strategicIncoming then return end
    local row = menu.strategicIncoming.record
    menu.strategicIncoming.record = nil
    if not row then return end
    local bucket = tostring(row[1] or "")
    local target = menu.strategicIncoming.records[bucket]
    if bucket == "carrierwings" then
        local group, damage = tonumber(row[3]), tonumber(row[5])
        local key = menu.carrierDraftKey(row[2], group)
        if type(row[2]) ~= "string" or row[2] == "" or not group or group % 1 ~= 0 or group < 1 or group > 10
            or not damage or damage % 1 ~= 0 or damage < 1 or damage > 100 or not wingAssignments[row[4]]
            or row[6] ~= wingAssignments[row[4]] or menu.strategicIncoming.wingKeys[key] or #target >= 100 then
            menu.strategicIncoming.wingInvalid = true
            return
        end
        row[3], row[5] = group, damage
        menu.strategicIncoming.wingKeys[key] = true
    end
    if target and row[2] ~= nil and row[3] ~= nil and row[4] ~= nil and row[5] ~= nil then target[#target + 1] = row end
end

function menu.strategicSnapshotComplete()
    if not menu.strategicIncoming then return end
    local incoming = menu.strategicIncoming
    if incoming.wingInvalid == false then
        local counts = {}
        for _, row in ipairs(incoming.records.carrierwings or {}) do counts[row[2]] = (counts[row[2]] or 0) + 1 end
        for _, row in ipairs(incoming.records.carriers or {}) do
            if tonumber(row[4]) ~= (counts[row[2]] or 0) then incoming.wingInvalid = true end
            counts[row[2]] = nil
        end
        if next(counts) then incoming.wingInvalid = true end
    end
    menu.strategicAssets = menu.strategicIncoming.assets
    menu.strategicObservations = menu.strategicIncoming.observations
    menu.strategicRecords = menu.strategicIncoming.records
    menu.carrierWingEvidenceValid = menu.strategicIncoming.wingInvalid == false
    menu.strategicIncoming = nil
    menu.strategicSnapshotStatus = tostring(#menu.strategicAssets) .. " ASSET(S) | " .. tostring(#menu.strategicObservations) .. " OBSERVATION(S)"
    if menu.frame then rebuild(false) end
end
function menu.carrierAutomation(_, value)
    if type(value) ~= "table" then return end
    local carrier = bridgeComponent64(value[1])
    local group = tonumber(value[2])
    local assignment = tostring(value[3] or "defence")
    local action = tostring(value[4] or "RECALL")
    local success = false
    if carrier and group and group >= 1 and group <= 10 then
        local oldassignment = ffi.string(C.GetSubordinateGroupAssignment(carrier, group))
        local olddock = C.ShouldSubordinateGroupDockAtCommander(carrier, group)
        local oldresupply = C.ShouldSubordinateGroupResupplyAtFleet(carrier, group)
        if action == "LAUNCH" then C.SetSubordinateGroupAssignment(carrier, group, assignment) end
        C.SetSubordinateGroupResupplyAtFleet(carrier, group, true)
        C.SetSubordinateGroupDockAtCommander(carrier, group, action ~= "LAUNCH")
        local newassignment = ffi.string(C.GetSubordinateGroupAssignment(carrier, group))
        local newdock = C.ShouldSubordinateGroupDockAtCommander(carrier, group)
        local newresupply = C.ShouldSubordinateGroupResupplyAtFleet(carrier, group)
        success = newassignment == (action == "LAUNCH" and assignment or oldassignment) and newdock == (action ~= "LAUNCH") and newresupply == true
        if not success then
            C.SetSubordinateGroupAssignment(carrier, group, oldassignment)
            C.SetSubordinateGroupDockAtCommander(carrier, group, olddock)
            C.SetSubordinateGroupResupplyAtFleet(carrier, group, oldresupply)
        end
    end
    AddUITriggeredEvent(menu.name, "carrier_automation_readback", { tostring(value[5] or ""), group or 0, action, assignment, success and "CONFIRMED" or "BLOCKED" })
    DebugError("[FOC][B058][CARRIER_AUTOMATION] carrier=" .. tostring(value[1]) .. " group=" .. tostring(group) .. " action=" .. action .. " assignment=" .. assignment .. " readback=" .. (success and "CONFIRMED" or "BLOCKED"))
end
function menu.carrierAutomationBegin() menu.carrierAutomationIncoming = {} end
function menu.carrierAutomationValue(index, value)
    if menu.carrierAutomationIncoming then menu.carrierAutomationIncoming[index] = value end
end
function menu.carrierAutomationCommit()
    local row = menu.carrierAutomationIncoming
    menu.carrierAutomationIncoming = nil
    if not row or row[1] == nil or tonumber(row[2]) == nil or row[3] == nil or row[4] == nil or row[5] == nil then return end
    menu.carrierAutomation(nil, row)
end
function menu.onRowChanged() end
function menu.onSelectElement() end
function menu.viewCreated() end

local function init()
    Menus = Menus or {}
    for _, entry in ipairs(Menus) do if entry.name == menu.name then return end end
    table.insert(Menus, menu)
    if Helper and Helper.registerMenu then
        Helper.registerMenu(menu)
    else
        DebugError("[FOC][B048][LUA_ERROR] Helper.registerMenu unavailable")
    end
    RegisterEvent(menu.name .. ".draft.key", draftKeyReceived)
    RegisterEvent(menu.name .. ".shipyard.ready", menu.shipyardReady)
    RegisterEvent(menu.name .. ".draft.result", draftResultReceived)
    RegisterEvent(menu.name .. ".draft.state", draftStateReceived)
    RegisterEvent(menu.name .. ".draft.complete", draftSaveComplete)
    RegisterEvent(menu.name .. ".action.result", actionResultReceived)
    RegisterEvent(menu.name .. ".action.state", actionStateReceived)
    RegisterEvent(menu.name .. ".action.complete", actionComplete)
    RegisterEvent(menu.name .. ".activity.id", liveActivityID)
    RegisterEvent(menu.name .. ".activity.time", liveActivityTime)
    RegisterEvent(menu.name .. ".activity.kind", liveActivityKind)
    RegisterEvent(menu.name .. ".activity.state", liveActivityState)
    RegisterEvent(menu.name .. ".activity.subject", liveActivitySubject)
    RegisterEvent(menu.name .. ".activity.detail", liveActivityDetail)
    RegisterEvent(menu.name .. ".activity.severity", liveActivitySeverity)
    RegisterEvent(menu.name .. ".activity.now", liveActivityNow)
    RegisterEvent(menu.name .. ".activity.row.commit", liveActivityCommit)
    RegisterEvent(menu.name .. ".activity.target", menu.activityTarget)
    RegisterEvent(menu.name .. ".activity.targetid", menu.activityTargetID)
    RegisterEvent(menu.name .. ".activity.sector", menu.activitySector)
    RegisterEvent(menu.name .. ".activity.snapshot.begin", menu.activitySnapshotBegin)
    RegisterEvent(menu.name .. ".activity.snapshot.complete", menu.activitySnapshotComplete)
    RegisterEvent(menu.name .. ".structural.snapshot.begin", menu.structuralSnapshotBegin)
    RegisterEvent(menu.name .. ".roadmap.begin", menu.roadmapBegin)
    RegisterEvent(menu.name .. ".roadmap.force.begin", menu.roadmapForceBegin)
    RegisterEvent(menu.name .. ".roadmap.force.id", menu.roadmapForceID)
    RegisterEvent(menu.name .. ".roadmap.force.name", menu.roadmapForceName)
    RegisterEvent(menu.name .. ".roadmap.force.priority", menu.roadmapForcePriority)
    RegisterEvent(menu.name .. ".roadmap.force.zone", menu.roadmapForceZone)
    RegisterEvent(menu.name .. ".roadmap.force.coverage", menu.roadmapForceCoverage)
    RegisterEvent(menu.name .. ".roadmap.force.rotation", menu.roadmapForceRotation)
    RegisterEvent(menu.name .. ".roadmap.force.active", menu.roadmapForceActive)
    RegisterEvent(menu.name .. ".roadmap.force.reserve", menu.roadmapForceReserve)
    RegisterEvent(menu.name .. ".roadmap.force.member", menu.roadmapForceMember)
    RegisterEvent(menu.name .. ".roadmap.force.commit", menu.roadmapForceCommit)
    RegisterEvent(menu.name .. ".roadmap.template.row", menu.roadmapTemplateRow)
    RegisterEvent(menu.name .. ".roadmap.policy", menu.roadmapPolicy)
    RegisterEvent(menu.name .. ".roadmap.complete", menu.roadmapComplete)
    RegisterEvent(menu.name .. ".structural.snapshot.row.begin", menu.structuralSnapshotRowBegin)
    RegisterEvent(menu.name .. ".structural.snapshot.commander", menu.structuralSnapshotCommander)
    RegisterEvent(menu.name .. ".structural.snapshot.key", menu.structuralSnapshotKey)
    RegisterEvent(menu.name .. ".structural.snapshot.label", menu.structuralSnapshotLabel)
    RegisterEvent(menu.name .. ".structural.snapshot.member", menu.structuralSnapshotMember)
    RegisterEvent(menu.name .. ".structural.snapshot.row.commit", menu.structuralSnapshotRowCommit)
    RegisterEvent(menu.name .. ".structural.snapshot.complete", menu.structuralSnapshotComplete)
    RegisterEvent(menu.name .. ".maintenance.snapshot.begin", menu.maintenanceSnapshotBegin)
    RegisterEvent(menu.name .. ".maintenance.repairrow.idcode", menu.maintenanceRepairRowID)
    RegisterEvent(menu.name .. ".maintenance.repairrow.name", menu.maintenanceRepairRowName)
    RegisterEvent(menu.name .. ".maintenance.repairrow.hull", menu.maintenanceRepairRowHull)
    RegisterEvent(menu.name .. ".maintenance.repairrow.scope", menu.maintenanceRepairRowScope)
    RegisterEvent(menu.name .. ".maintenance.repairrow.fleet", menu.maintenanceRepairRowFleet)
    RegisterEvent(menu.name .. ".maintenance.repairrow.threshold", menu.maintenanceRepairRowThreshold)
    RegisterEvent(menu.name .. ".maintenance.repairrow.protected", menu.maintenanceRepairRowProtected)
    RegisterEvent(menu.name .. ".maintenance.repairrow.playercontrolled", menu.maintenanceRepairRowPlayerControlled)
    RegisterEvent(menu.name .. ".maintenance.repairrow.commit", menu.maintenanceRepairRowCommit)
    for _, field in ipairs({ "commander", "fleet", "status" }) do
        local capturedField = field
        RegisterEvent(menu.name .. ".maintenance.meta." .. field, function(_, value) menu.maintenanceMetaValue(capturedField, value) end)
    end
    for _, field in ipairs({ "fleetunit", "index", "name", "state", "signature", "detail", "ready" }) do
        local capturedField = field
        RegisterEvent(menu.name .. ".maintenance.lost." .. field, function(_, value) menu.maintenanceLostValue(capturedField, value) end)
    end
    RegisterEvent(menu.name .. ".maintenance.lost.commit", menu.maintenanceLostCommit)
    RegisterEvent(menu.name .. ".maintenance.snapshot.complete", menu.maintenanceSnapshotComplete)
    RegisterEvent(menu.name .. ".maintenance.repair.ship", function(_, value) menu.maintenanceRepairOpenValue("ship", value) end)
    RegisterEvent(menu.name .. ".maintenance.repair.facility", function(_, value) menu.maintenanceRepairOpenValue("facility", value) end)
    RegisterEvent(menu.name .. ".maintenance.repair.complete", menu.maintenanceRepairOpenComplete)
    RegisterEvent(menu.name .. ".maintenance.losteditor.fleetunit", menu.maintenanceLostEditorValue)
    RegisterEvent(menu.name .. ".maintenance.losteditor.complete", menu.maintenanceLostEditorComplete)
    RegisterEvent(menu.name .. ".academy.snapshot.begin", academySnapshotBegin)
    RegisterEvent(menu.name .. ".academy.snapshot.id", academySnapshotID)
    RegisterEvent(menu.name .. ".academy.snapshot.name", academySnapshotName)
    RegisterEvent(menu.name .. ".academy.snapshot.origin", academySnapshotOrigin)
    RegisterEvent(menu.name .. ".academy.snapshot.originid", academySnapshotOriginID)
    RegisterEvent(menu.name .. ".academy.snapshot.piloting", academySnapshotPiloting)
    RegisterEvent(menu.name .. ".academy.snapshot.morale", academySnapshotMorale)
    RegisterEvent(menu.name .. ".academy.snapshot.seminar", academySnapshotSeminar)
    RegisterEvent(menu.name .. ".academy.snapshot.seminarcount", academySnapshotSeminarCount)
    RegisterEvent(menu.name .. ".academy.snapshot.valid", academySnapshotValid)
    RegisterEvent(menu.name .. ".academy.snapshot.track", academySnapshotTrack)
    RegisterEvent(menu.name .. ".academy.snapshot.boarding", academySnapshotBoarding)
    RegisterEvent(menu.name .. ".academy.snapshot.row.commit", academySnapshotRowCommit)
    RegisterEvent(menu.name .. ".academy.snapshot.complete", academySnapshotComplete)
    RegisterEvent(menu.name .. ".protected.snapshot.begin", protectedSnapshotBegin)
    RegisterEvent(menu.name .. ".protected.snapshot.id", protectedSnapshotID)
    RegisterEvent(menu.name .. ".protected.snapshot.complete", protectedSnapshotComplete)
    RegisterEvent(menu.name .. ".storyoverride.snapshot.begin", storyOverrideSnapshotBegin)
    RegisterEvent(menu.name .. ".storyoverride.snapshot.id", storyOverrideSnapshotID)
    RegisterEvent(menu.name .. ".storyoverride.snapshot.complete", storyOverrideSnapshotComplete)
    RegisterEvent(menu.name .. ".storyanswered.snapshot.begin", menu.storyAnsweredSnapshotBegin)
    RegisterEvent(menu.name .. ".storyanswered.snapshot.id", menu.storyAnsweredSnapshotID)
    RegisterEvent(menu.name .. ".storyanswered.snapshot.complete", menu.storyAnsweredSnapshotComplete)
    RegisterEvent(menu.name .. ".vacancy.snapshot.begin", vacancySnapshotBegin)
    RegisterEvent(menu.name .. ".vacancy.snapshot.component", vacancySnapshotComponent)
    RegisterEvent(menu.name .. ".vacancy.snapshot.name", vacancySnapshotName)
    RegisterEvent(menu.name .. ".vacancy.snapshot.idcode", vacancySnapshotIDCode)
    RegisterEvent(menu.name .. ".vacancy.snapshot.sector", vacancySnapshotSector)
    RegisterEvent(menu.name .. ".vacancy.snapshot.row.commit", vacancySnapshotRowCommit)
    RegisterEvent(menu.name .. ".vacancy.snapshot.complete", vacancySnapshotComplete)
    RegisterEvent(menu.name .. ".marine.snapshot.begin", marineTargetSnapshotBegin)
    RegisterEvent(menu.name .. ".marine.snapshot.component", marineTargetSnapshotComponent)
    RegisterEvent(menu.name .. ".marine.snapshot.name", marineTargetSnapshotName)
    RegisterEvent(menu.name .. ".marine.snapshot.idcode", marineTargetSnapshotIDCode)
    RegisterEvent(menu.name .. ".marine.snapshot.sector", marineTargetSnapshotSector)
    RegisterEvent(menu.name .. ".marine.snapshot.relationship", marineTargetSnapshotRelationship)
    RegisterEvent(menu.name .. ".marine.snapshot.people", marineTargetSnapshotPeople)
    RegisterEvent(menu.name .. ".marine.snapshot.capacity", marineTargetSnapshotCapacity)
    RegisterEvent(menu.name .. ".marine.snapshot.marines", marineTargetSnapshotMarines)
    RegisterEvent(menu.name .. ".marine.snapshot.row.commit", marineTargetSnapshotRowCommit)
    RegisterEvent(menu.name .. ".marine.snapshot.complete", marineTargetSnapshotComplete)
    RegisterEvent(menu.name .. ".store.snapshot.begin", storeSnapshotBegin)
    RegisterEvent(menu.name .. ".store.snapshot.balance", storeSnapshotBalance)
    for tier = 1, 5 do
        local capturedTier = tier
        RegisterEvent(menu.name .. ".store.snapshot.pilot." .. tostring(capturedTier), function(_, value) storePilotTier(capturedTier, value) end)
        RegisterEvent(menu.name .. ".store.snapshot.marine." .. tostring(capturedTier), function(_, value) storeMarineTier(capturedTier, value) end)
    end
    RegisterEvent(menu.name .. ".store.snapshot.complete", storeSnapshotComplete)
    for _, field in ipairs({ "token", "state", "result" }) do
        local capturedField = field
        RegisterEvent(menu.name .. ".carrier.reply." .. field, function(_, value) menu.carrierReplyValue(capturedField, value) end)
    end
    RegisterEvent(menu.name .. ".carrier.reply.complete", menu.carrierReplyComplete)
    RegisterEvent(menu.name .. ".strategic.snapshot.begin", menu.strategicSnapshotBegin)
    RegisterEvent(menu.name .. ".strategic.asset.begin", menu.strategicAssetBegin)
    for _, field in ipairs({ "kind", "component", "idcode", "name", "purpose", "sector", "order", "commander", "hull", "shield" }) do
        local capturedField = field
        RegisterEvent(menu.name .. ".strategic.asset." .. field, function(_, value) menu.strategicAssetValue(capturedField, value) end)
    end
    RegisterEvent(menu.name .. ".strategic.asset.commit", menu.strategicAssetCommit)
    RegisterEvent(menu.name .. ".strategic.observation.begin", menu.strategicObservationBegin)
    for _, field in ipairs({ "kind", "time", "sector", "sectorid", "subject", "amount", "severity", "detail" }) do
        local capturedField = field
        RegisterEvent(menu.name .. ".strategic.observation." .. field, function(_, value) menu.strategicObservationValue(capturedField, value) end)
    end
    RegisterEvent(menu.name .. ".strategic.observation.commit", menu.strategicObservationCommit)
    RegisterEvent(menu.name .. ".strategic.record.begin", menu.strategicRecordBegin)
    for index, field in ipairs({ "bucket", "p2", "p3", "p4", "p5", "p6" }) do
        local capturedIndex = index
        RegisterEvent(menu.name .. ".strategic.record." .. field, function(_, value) menu.strategicRecordValue(capturedIndex, value) end)
    end
    RegisterEvent(menu.name .. ".strategic.record.commit", menu.strategicRecordCommit)
    RegisterEvent(menu.name .. ".strategic.snapshot.complete", menu.strategicSnapshotComplete)
    RegisterEvent(menu.name .. ".carrier.automation.begin", menu.carrierAutomationBegin)
    for index, field in ipairs({ "carrier", "group", "assignment", "action", "id" }) do
        local capturedIndex = index
        RegisterEvent(menu.name .. ".carrier.automation." .. field, function(_, value) menu.carrierAutomationValue(capturedIndex, value) end)
    end
    RegisterEvent(menu.name .. ".carrier.automation.commit", menu.carrierAutomationCommit)
end

init()
