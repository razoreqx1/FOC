local ffi = require("ffi")

ffi.cdef[[
typedef uint64_t UniverseID;
uint32_t GetAllFactionShips(UniverseID* result, uint32_t resultlen, const char* factionid);
UniverseID GetPlayerOccupiedShipID(void);
bool IsComponentOperational(UniverseID componentid);
float GetTextHeight(const char*const text, const char*const fontname, const float fontsize, const float wordwrapwidth);
]]

local C = ffi.C
local MAX_SHIPS_PER_SAMPLE = 500
local MAX_FLEETS_DISPLAYED = 100
local HISTORY_LIMIT = 64
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
    homeSectorByFleet = {},
    ordersByFleet = {},
    draftsByFleet = {},
    pendingDraftSaves = {},
    draftReadback = { key = nil, result = nil, state = nil },
    notice = nil,
    previews = { dispatch = nil, personnel = nil, global = nil, patrol = nil },
    academy = { rows = {}, vacancies = {}, selectedRecruitID = nil, selectedVacancyID = nil, previewRecruitReady = false, previewAssignReady = false },
    academyIncoming = nil,
    vacancyIncoming = nil,
    protectedIncoming = nil,
    protectedShipIDs = {},
    protectedShipCount = 0,
    pendingActionKind = nil,
    pendingHomeSelection = nil,
    restoreFleetKey = nil,
    selectedFleet = 1,
    showNonCombat = false,
    showFleetAdvanced = false,
    lastActivePatrolFleet = nil,
    renderedPage = nil,
    restoreTopRow = nil,
    closeInProgress = false,
    listPages = {},
    listContentHeight = nil,
    phase = { readiness = "overview", fleets = "registry", response = "rules", settings = "automation" },
    plan = {
        authority = "PREVIEW PLAN", fleetRole = "PATROL GROUP", naming = "FOC | ROLE | HOME | 01",
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
local rebuild

local tabs = {
    { id = "command", label = "COMMAND" },
    { id = "fleets", label = "FLEETS" },
    { id = "readiness", label = "READINESS" },
    { id = "academy", label = "TRAINING ACADEMY" },
    { id = "doctrine", label = "DOCTRINE" },
    { id = "response", label = "FLEET RESPONSE" },
    { id = "activity", label = "ACTIVITY" },
    { id = "settings", label = "SETTINGS" },
}

local guides = {
    command = "Preview, approve, or stop bounded FOC planning. Unknown evidence always blocks mutation.",
    fleets = "Choose one fleet, configure its Home and response rules, then send it directly from this page.",
    readiness = "Missing and unknown evidence are blockers. No unknown value is counted as ready.",
    academy = "Recruit up to 25 station-based trainees, then promote and assign a skill-ordered batch to proven captain vacancies.",
    doctrine = "Configure home, coverage, patrol, protection, and fleet authority for the selected stable fleet.",
    response = "Configure FOC Fleet Response scope, safeguards, dispatch limits, and return behavior.",
    activity = "Review this session's bounded FOC samples and player-requested refreshes.",
    settings = "Configure global planning mode and review hard scan, mutation, cooldown, and audit bounds.",
}

local automationModes = { "PREVIEW PLAN", "APPLY APPROVED PLAN", "FULL AUTOMATION" }
local fleetRoles = { "PATROL GROUP", "DEFENSE GROUP", "INTERCEPT GROUP", "RESCUE GROUP", "CONVOY SUPPORT GROUP", "RESERVE GROUP" }
local coverageRanges = { "HOME SECTOR ONLY", "ONE GATE", "TWO GATES", "THREE GATES", "FOUR GATES", "FIVE GATES", "CUSTOM SECTOR LIST" }
local distressScopes = { "PLAYER OWNED ONLY", "PLAYER AND ALLIED", "FRIENDLY OR NEUTRAL", "IGNORE NON-PLAYER" }
local patrolPatterns = { "LOOP", "OUT AND BACK", "RANDOM WITHIN PATROL AREA" }
local patrolSectorChoices = { "ALL SAFE SECTORS IN RANGE", "PLAYER-OWNED SECTORS ONLY", "CHOOSE SECTORS MYSELF" }
local yesNoOptions = { "YES", "NO" }
local urgencyOptions = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
local damageOptions = { 100, 90, 80, 70, 60, 50, 40, 30, 20, 10 }

local function cycle(current, values)
    for i, value in ipairs(values) do if value == current then return values[(i % #values) + 1] end end
    return values[1]
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function safeText(value, fallback)
    if value == nil or tostring(value) == "" then return fallback or "UNKNOWN" end
    return tostring(value)
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

local function selectedAcademyRecruit()
    local selectedID = tostring(menu.academy.selectedRecruitID or "")
    for _, recruit in ipairs(menu.academy.rows) do
        if tostring(recruit.id) == selectedID then return recruit end
    end
    return nil
end

local function selectedAcademyVacancy(vacancies)
    local selectedID = tostring(menu.academy.selectedVacancyID or "")
    for _, vacancy in ipairs(vacancies or {}) do
        if tostring(vacancy.key or "") == selectedID then return vacancy end
    end
    return nil
end

local function needsAction(value)
    local text = string.upper(tostring(value or ""))
    return text:find("BLOCKED", 1, true) ~= nil or text:find("ACTION REQUIRED", 1, true) ~= nil or
        text:find("NOT SENT", 1, true) ~= nil or text:find("NOT APPLIED", 1, true) ~= nil or
        text:find("NOT SAVED", 1, true) ~= nil or text:find("NEEDS ATTENTION", 1, true) ~= nil
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

local function bridgeComponent64(value)
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
        fleetRole = "PATROL GROUP", coverage = "HOME SECTOR ONLY", sectorChoice = "ALL SAFE SECTORS IN RANGE",
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
            orders.fleetRole = safeText(row[9], orders.fleetRole)
            orders.coverage = safeText(row[10], orders.coverage)
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

local function menuByName(name)
    for _, entry in ipairs(Menus or {}) do
        if entry.name == name then return entry end
    end
    return nil
end

local function returnFromHomeMap(value)
    local pending = menu.pendingHomeSelection
    local sector64 = type(value) == "table" and toComponent64(value[1]) or nil
    local position = type(value) == "table" and value[2] or nil
    if pending and pending.fleetKey and sector64 and type(position) == "table" then
        menu.restoreFleetKey = pending.fleetKey
        local sectorName = componentName(sector64, "UNKNOWN SECTOR")
        local sectorKey = stableSectorKey(sector64, sectorName)
        if not sectorKey then
            menu.pendingHomeSelection = nil
            menu.plan.lastResult = "HOME POINT NOT CHANGED - SECTOR IDENTITY IS UNKNOWN"
            DebugError("[FOC][B020][HOME_MAP_INVALID] reason=STABLE_SECTOR_IDENTITY_UNKNOWN mutation=NONE")
            rebuild(false)
            return
        end
        menu.homeSectorByFleet[pending.fleetKey] = {
            id = sectorKey,
            text = sectorName,
            position = { tonumber(position[1]) or 0, tonumber(position[2]) or 0, tonumber(position[3]) or 0 },
        }
        markFleetOrdersChanged(pending.fleetKey, ordersForFleet(pending.fleetKey))
        menu.plan.lastResult = "HOME POINT CHOSEN - DRAFT NOT YET SAVED - NO ORDERS SENT"
        DebugError("[FOC][B020][HOME_MAP_SELECTED] fleet=" .. pending.fleetAudit .. " sector=" .. sectorName .. " sector_key=" .. sectorKey .. " mutation=NONE")
    else
        menu.plan.lastResult = "HOME POINT NOT CHANGED - MAP RETURN WAS INVALID - NO ORDERS SENT"
        DebugError("[FOC][B020][HOME_MAP_INVALID] mutation=NONE")
    end
    menu.pendingHomeSelection = nil
    local mapMenu = menuByName("MapMenu")
    if mapMenu then
        Helper.closeMenuAndOpenNewMenu(mapMenu, menu.name, { 0, 0, menu.param[3], menu.param[4], menu.param[5], menu.plan.authority, menu.plan.lastResult, nil, nil, menu.restoreFleetKey })
        if mapMenu.cleanup then mapMenu.cleanup() end
    end
end

local function installInteractHomeHook()
    local interactMenu = menuByName("InteractMenu")
    if not interactMenu or not interactMenu.prepareActions or interactMenu.focHomeHookInstalled then return interactMenu ~= nil end
    local originalPrepareActions = interactMenu.prepareActions
    interactMenu.prepareActions = function(...)
        local result = originalPrepareActions(...)
        if menu.pendingHomeSelection and interactMenu.insertInteractionContent and interactMenu.offsetcomponent and interactMenu.offset then
            interactMenu.insertInteractionContent("guidance", {
                active = true,
                type = "foc_home_point",
                text = "SET AS FOC HOME POINT",
                script = function()
                    local offsetcomponent = tostring(interactMenu.offsetcomponent)
                    local offset = interactMenu.offset
                    local selectedValue = {
                        offsetcomponent,
                        { tonumber(offset.x) or 0, tonumber(offset.y) or 0, tonumber(offset.z) or 0 },
                    }
                    interactMenu.onCloseElement("close")
                    returnFromHomeMap(selectedValue)
                end,
            })
        end
        return result
    end
    interactMenu.focHomeHookInstalled = true
    DebugError("[FOC][B020][INTERACT_HOME_HOOK] installed=true mutation=NONE")
    return true
end

local function chooseHomeOnMap(selected)
    local key = fleetKey(selected)
    if not key then
        menu.plan.lastResult = "HOME POINT NOT CHANGED - FLEET IDENTITY IS UNKNOWN"
        rebuild(false)
        return
    end
    menu.pendingHomeSelection = { fleetKey = key, fleetAudit = fleetAuditSubject(selected, key) }
    local focus = selected.commander.object
    if not installInteractHomeHook() then
        menu.pendingHomeSelection = nil
        menu.plan.lastResult = "HOME POINT NOT CHANGED - FOC COULD NOT OPEN X4'S SAFE RIGHT-CLICK CHOICE. NOTHING CHANGED."
        menu.plan.lastState = "ACTION_REQUIRED_HOME"
        menu.notice = menu.plan.lastResult
        rebuild(false)
        return
    end
    menu.plan.lastResult = "MAP OPEN - RIGHT-CLICK THE HOME POINT AND CHOOSE SET AS FOC HOME POINT"
    Helper.closeMenuAndOpenNewMenu(menu, "MapMenu", { 0, 0, true, focus })
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
    local ok, result = pcall(GetSubordinates, ship)
    if ok and type(result) == "table" then return result end
    return {}
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
    local name, fleetname, sector, sectorID, hull, shield, assignment, primarypurpose = GetComponentData(
        ship, "name", "fleetname", "sector", "sectorid", "hullpercent", "shieldpercent", "assignment", "primarypurpose"
    )
    local idcode = componentIDCode(ship)
    local pilot, captainState = pilotEvidence(ship)
    local order = "UNKNOWN"
    if pilot then
        local ok, command = pcall(GetComponentData, ship, "aicommand")
        if ok and command and command ~= "" then order = tostring(command) end
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
        isMission = isProtectedShipID(idcode),
        captainState = captainState,
        captain = pilot and componentName(pilot, "UNKNOWN") or (captainState == "MISSING" and "NO CAPTAIN" or "UNKNOWN"),
        order = order,
        operational = operational == true,
        playerOccupied = tostring(ship) == tostring(C.GetPlayerOccupiedShipID()),
    }
end

local function classifyFleet(fleet)
    if fleet.commander.captainState == "MISSING" then return "CRITICAL", "Commander has no captain." end
    if fleet.commander.captainState == "UNKNOWN" then return "UNKNOWN", "Commander captain state is unavailable." end
    if not fleet.commander.operational then return "CRITICAL", "Commander is not operational." end
    if fleet.commander.hull and fleet.commander.hull < 50 then return "CRITICAL", "Commander hull is below 50%." end
    if fleet.damaged > 0 or fleet.missingCaptains > 0 then return "DEGRADED", "One or more fleet ships need attention." end
    if fleet.unknown > 0 then return "UNKNOWN", "One or more readiness values are unknown." end
    return "READY", "No first-rollout blocker was observed."
end

local function sampleFleets(reason)
    local buffer = ffi.new("UniverseID[?]", MAX_SHIPS_PER_SAMPLE)
    local returned = tonumber(C.GetAllFactionShips(buffer, MAX_SHIPS_PER_SAMPLE, "player")) or 0
    returned = math.min(returned, MAX_SHIPS_PER_SAMPLE)
    local fleets = {}
    local missingCaptainIssues = {}
    local unknownCaptainIssues = {}
    local counts = { ready = 0, degraded = 0, critical = 0, unknown = 0, missingCaptains = 0, unknownCaptains = 0, damaged = 0 }
    for index = 0, returned - 1 do
        local ship = toComponent64(buffer[index])
        if ship then
        local sampledIDCode = componentIDCode(ship)
        if not isProtectedShipID(sampledIDCode) then
        local _, sampledCaptainState = pilotEvidence(ship)
        if sampledCaptainState ~= "PRESENT" then
            if sampledCaptainState == "MISSING" then
                counts.missingCaptains = counts.missingCaptains + 1
            else
                counts.unknownCaptains = counts.unknownCaptains + 1
            end
            local shipName, sector = GetComponentData(ship, "name", "sector")
            local issue = {
                    state = sampledCaptainState,
                    name = safeText(shipName, "Unnamed ship"),
                    idcode = sampledIDCode,
                    sector = safeText(sector, "UNKNOWN"),
                }
            if sampledCaptainState == "MISSING" then table.insert(missingCaptainIssues, issue)
            else table.insert(unknownCaptainIssues, issue) end
        end
        local commander = nil
        local commanderOK, commanderValue = pcall(GetCommander, ship)
        if commanderOK then commander = commanderValue end
        local subordinates = directSubordinates(ship)
        local commanderEvidence = shipEvidence(ship)
        if #fleets < MAX_FLEETS_DISPLAYED and (not commander or commander == 0 or commander == "") and #subordinates > 0 then
            local record = {
                commander = commanderEvidence,
                members = {},
                shipCount = 1,
                missingCaptains = 0,
                damaged = 0,
                unknown = 0,
                missionProtected = commanderEvidence.isMission,
            }
            local memberLimit = math.min(#subordinates, 100)
            for memberIndex = 1, memberLimit do
                local member64 = toComponent64(subordinates[memberIndex])
                local member = member64 and shipEvidence(member64) or nil
                if member then
                table.insert(record.members, member)
                record.shipCount = record.shipCount + 1
                if member.captainState == "MISSING" then record.missingCaptains = record.missingCaptains + 1 end
                if member.hull and member.hull < 80 then record.damaged = record.damaged + 1 end
                if member.isMission then record.missionProtected = true end
                if not member.hull or not member.shield or member.captainState == "UNKNOWN" then record.unknown = record.unknown + 1 end
                end
            end
            record.status, record.reason = classifyFleet(record)
            if not record.missionProtected then
                counts[string.lower(record.status)] = (counts[string.lower(record.status)] or 0) + 1
                counts.damaged = counts.damaged + record.damaged
                table.insert(fleets, record)
            end
        end
        end
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
        shipsExamined = returned,
        capped = returned >= MAX_SHIPS_PER_SAMPLE,
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
    DebugError("[FOC][B020][SAMPLE] reason=" .. sample.reason .. " ships_examined=" .. tostring(returned) .. " fleets=" .. tostring(#fleets) .. " protected=" .. tostring(menu.protectedShipCount) .. " cap=" .. tostring(MAX_SHIPS_PER_SAMPLE) .. " mutation=NONE")
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

local function actionRow(tableWidget, label, value, handler, active, color)
    local row = tableWidget:addRow(true)
    row[1]:createText(label, { color = neutralColor })
    local properties = { active = active == true }
    if color == warningColor then properties.bgColor = requiredActionBackground
    elseif color == criticalColor then properties.bgColor = failedActionBackground
    elseif color == passColor then properties.bgColor = confirmedActionBackground
    elseif color == headingColor then properties.bgColor = normalActionBackground
    elseif color == activeTabBackground then properties.bgColor = activeTabBackground
    elseif color then properties.bgColor = availableActionBackground end
    row[2]:setColSpan(3):createButton(properties):setText(safeText(value), { halign = "center" })
    if active == true then row[2].handlers.onClick = handler end
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
    row[1]:setColSpan(2):createButton({ active = leftActive }):setText(leftText, { halign = "center" })
    if leftActive then row[1].handlers.onClick = leftHandler end
    local mapped = rightColor == warningColor and requiredActionBackground or rightColor == passColor and confirmedActionBackground or normalActionBackground
    row[3]:setColSpan(2):createButton({ active = rightActive, bgColor = mapped }):setText(rightText, { halign = "center" })
    if rightActive then row[3].handlers.onClick = rightHandler end
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

local function requestFleetDraftSave(selected, key, orders, home)
    if menu.pendingDraftSaves[key] then
        menu.plan.lastResult = "DRAFT SAVE ALREADY PENDING - WAITING FOR PERSISTENT READBACK"
        menu.notice = menu.plan.lastResult
        DebugError("[FOC][B020][DRAFT_SAVE_SUPPRESSED] key=" .. tostring(key or "UNKNOWN") .. " reason=PENDING_READBACK mutation=NONE")
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
    DebugError("[FOC][B020][DRAFT_SAVE_REQUEST] fleet=" .. fleetAuditSubject(selected, key) .. " home_key=" .. tostring(home.id) .. " schema=4 readback=PENDING mutation=NONE")
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
    DebugError("[FOC][B020][FLEET_PATROL_REQUEST] fleet=" .. fleetAuditSubject(selected, key) .. " home_key=" .. tostring(home.id) .. " replace_selected=1 automation_selected=1 readback=PENDING")
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
    DebugError("[FOC][B020][DRAFT_SAVE_READBACK] key=" .. tostring(key or "UNKNOWN") .. " state=" .. state .. " result=" .. result .. " mutation=NONE")
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
    actionReadback = { result = nil, state = nil }
    menu.pendingActionKind = nil
    if menu.frame then sampleFleets("NATIVE READBACK"); rebuild(false) end
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
        DebugError("[FOC][B020][COLLECTION_REJECTED] collection=ACADEMY expected=" .. tostring(incoming and incoming.expected or "NONE") .. " received=" .. tostring(incoming and #incoming.rows or 0) .. " cache=PRESERVED")
        return
    end
    loadAcademyRows(incoming.rows)
    DebugError("[FOC][B020][COLLECTION_COMMIT] collection=ACADEMY rows=" .. tostring(#incoming.rows) .. " cache=REPLACED")
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
        DebugError("[FOC][B020][COLLECTION_REJECTED] collection=PROTECTED expected=" .. tostring(incoming and incoming.expected or "NONE") .. " received=" .. tostring(incoming and #incoming.rows or 0) .. " cache=PRESERVED")
        if menu.plan.lastState == "REFRESH_PENDING" then
            menu.plan.lastState = "BLOCKED"
            menu.plan.lastResult = "REFRESH BLOCKED - PROTECTED SHIP SNAPSHOT WAS INCOMPLETE | PRIOR PROTECTION CACHE PRESERVED"
            menu.notice = menu.plan.lastResult
        end
        if menu.frame and not menu.pendingActionKind then rebuild(false) end
        return
    end
    loadProtectedShipIDs(incoming.rows)
    DebugError("[FOC][B020][COLLECTION_COMMIT] collection=PROTECTED rows=" .. tostring(#incoming.rows) .. " cache=REPLACED")
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
        DebugError("[FOC][B020][COLLECTION_REJECTED] collection=VACANCY expected=" .. tostring(incoming and incoming.expected or "NONE") .. " received=" .. tostring(incoming and #incoming.rows or 0) .. " cache=PRESERVED")
        return
    end
    loadVacancyRows(incoming.rows)
    DebugError("[FOC][B020][COLLECTION_COMMIT] collection=VACANCY rows=" .. tostring(#incoming.rows) .. " cache=REPLACED identity=NATIVE_COMPONENT")
    if menu.frame and not menu.pendingActionKind and menu.plan.lastState ~= "REFRESH_PENDING" then rebuild(false) end
end

local function previewGlobalPlan()
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

local function previewPatrolPlan(selected, orders, home)
    local result
    local state
    if not selected or not orders then
        result = "PATROL PREVIEW BLOCKED - SELECT A FLEET | NO ORDERS SENT"
        state = "PREVIEW_BLOCKED"
    elseif selected.missionProtected then
        result = "PATROL PREVIEW BLOCKED - QUEST / MISSION SHIPS ARE NEVER IN FOC SCOPE | NO ORDERS SENT"
        state = "PREVIEW_BLOCKED"
    elseif selected.commander.primarypurpose ~= "fight" and not orders.nonCombatOverride then
        result = "PATROL PREVIEW BLOCKED - NON-COMBAT FLEET REQUIRES EXPLICIT OVERRIDE | SUPPLY ORDER PROTECTED | NO ORDERS SENT"
        state = "PREVIEW_BLOCKED"
    elseif not home then
        result = "PATROL PREVIEW BLOCKED - CHOOSE THIS FLEET'S HOME POINT | NO ORDERS SENT"
        state = "PREVIEW_BLOCKED"
    else
        result = "PATROL PREVIEW COMPLETE - " .. selected.commander.fleetname .. " | HOME " .. home.text .. " | RANGE " .. orders.coverage .. " | PATTERN " .. orders.patrolPattern .. " | NO ORDERS SENT"
        state = "PREVIEW_COMPLETE"
    end
    menu.previews.patrol = result
    auditAction("PREVIEW_PATROL", selected and selected.commander.idcode or "NONE", result, state)
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

local function renderSlice(total, pageKey, options)
    local pageSize, pageCount, page = calculateRenderBudget(total, pageKey, options)
    local first = (page - 1) * pageSize + 1
    local last = math.min(total, first + pageSize - 1)
    return first, last, page, pageCount, pageSize
end

rebuild = function(resetScroll)
    if resetScroll then menu.restoreTopRow = nil end
    menu.refresh()
end

local function addPager(tableWidget, pageKey, total, options)
    local first, last, page, pageCount, pageSize = renderSlice(total, pageKey, options)
    if pageCount > 1 then
        local row = tableWidget:addRow(true, { fixed = true })
        row[1]:createButton({ active = page > 1 }):setText("PREVIOUS", { halign = "center" })
        row[1].handlers.onClick = function() menu.listPages[pageKey] = math.max(1, page - 1); rebuild(true) end
        row[2]:setColSpan(2):createText("PAGE " .. tostring(page) .. " / " .. tostring(pageCount) .. " | " .. tostring(total) .. " RECORDS", { halign = "center" })
        row[4]:createButton({ active = page < pageCount }):setText("NEXT", { halign = "center" })
        row[4].handlers.onClick = function() menu.listPages[pageKey] = math.min(pageCount, page + 1); rebuild(true) end
    end
    return first, last, page, pageCount, pageSize
end

local function createHeader(frame, width)
    local titleHeight = Helper.scaleY(42)
    local tabHeight = Helper.scaleY(38)
    local headerHeight = titleHeight + tabHeight
    local header = frame:addTable(9, { tabOrder = 1, x = Helper.borderSize, y = Helper.borderSize, width = width - 2 * Helper.borderSize, borderEnabled = false })
    local title = header:addRow(true, { fixed = true })
    local screenTitle = menu.page == "fleets" and "FLEET ORDERS" or "PLAN CONTROL"
    local buildLabel = safeText(menu.param and menu.param[4], "FOC Build UNKNOWN"):gsub("^FOC%s+", ""):upper()
    title[1]:setColSpan(8):createText("FLEET OPERATIONS COMMAND  |  " .. buildLabel .. "  |  " .. screenTitle, { font = Helper.headerFont, fontsize = Helper.standardFontSize + 4 })
    title[9]:createButton({ active = true }):setText("CLOSE", { halign = "center" })
    title[9].handlers.onClick = function() menu.onCloseElement("close") end
    local tabRow = header:addRow(true, { fixed = true })
    for index, tab in ipairs(tabs) do
        local properties = { active = true }
        if menu.page == tab.id then properties.bgColor = activeTabBackground end
        tabRow[index]:createButton(properties):setText(tab.label, { halign = "center" })
        tabRow[index].handlers.onClick = function()
            menu.page = tab.id
            menu.activeTab = tab.id
            rebuild(true)
        end
    end
    tabRow[9]:createButton({ active = true }):setText("REFRESH", { halign = "center" })
    tabRow[9].handlers.onClick = function()
        menu.notice = "REFRESH REQUESTED - WAITING FOR MD QUEST-PROTECTION SNAPSHOT"
        menu.plan.lastResult = menu.notice
        menu.plan.lastState = "REFRESH_PENDING"
        AddUITriggeredEvent(menu.name, "refresh", nil)
        rebuild(true)
    end
    header.properties.maxVisibleHeight = headerHeight
    return headerHeight
end

local function pageGuide(tableWidget)
    section(tableWidget, "START HERE")
    textRow(tableWidget, "Purpose", guides[menu.page], headingColor)
    textRow(tableWidget, "Authority", menu.plan.authority .. " - preview never mutates; apply routes require approval, revalidation, readback, and bounded authority.", passColor)
    if menu.sample and menu.sample.capped then
        textRow(tableWidget, "Sampling bound", "The native result reached the 500-ship cap. Results are partial and are not represented as complete.", warningColor)
    end
    if menu.notice then textRow(tableWidget, "Last action", menu.notice, needsAction(menu.notice) and warningColor or passColor) end
end

local function commandPage(tableWidget)
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
    local first, last = addPager(tableWidget, "command.attention", #attention, { fixedRows = 22 + commandGuidanceRows, contentPixels = menu.listContentHeight, maximum = 20 })
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
    local stopped = menu.plan.status == "STOPPED" and menu.plan.authority == "PREVIEW PLAN"
    actionRow(tableWidget, "Emergency", stopped and "FOC AUTOMATION ALREADY STOPPED" or "STOP FOC AUTOMATION", function() menu.plan.authority = "PREVIEW PLAN"; menu.plan.status = "STOPPED"; auditAction("STOP_AUTOMATION", "GLOBAL", "FOC AUTOMATION STOPPED - PERSISTENT READBACK REQUIRED", "STOPPED") end, not stopped, warningColor)
end

local function fleetSelectorPane(tableWidget)
    section(tableWidget, "CHOOSE A FLEET")
    textRow(tableWidget, "", "Combat fleets are shown by default. Reveal non-combat fleets only to review or override one deliberately.", headingColor)
    actionRow(tableWidget, "Scope", menu.showNonCombat and "HIDE NON-COMBAT FLEETS" or "SHOW NON-COMBAT FLEETS", function() menu.showNonCombat = not menu.showNonCombat; menu.listPages["fleets.registry"] = 1; rebuild(true) end, true, warningColor)
    local visibleFleets = {}
    for index, fleet in ipairs(menu.sample.fleets) do
        if menu.showNonCombat or fleet.commander.primarypurpose == "fight" then table.insert(visibleFleets, { index = index, fleet = fleet }) end
    end
    if not menu.showNonCombat and menu.sample.fleets[menu.selectedFleet] and menu.sample.fleets[menu.selectedFleet].commander.primarypurpose ~= "fight" and visibleFleets[1] then menu.selectedFleet = visibleFleets[1].index end
    local first, last, _, pageCount = addPager(tableWidget, "fleets.registry", #visibleFleets, { fixedRows = 5, contentPixels = menu.listContentHeight, maximum = 17 })
    local selectedRow = nil
    local rowsBeforeFleets = 3 + (pageCount > 1 and 1 or 0)
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
            row[1].handlers.onClick = function() menu.selectedFleet = index; rebuild(true) end
            if index == menu.selectedFleet then selectedRow = rowsBeforeFleets + (visibleIndex - first + 1) end
        end
    end
    if selectedRow then pcall(tableWidget.setSelectedRow, tableWidget, selectedRow) end
    if menu.sample.capped then textRow(tableWidget, "LIMIT", "The 500-ship sample is partial.", warningColor) end
end

local function fleetOrdersPane(tableWidget)
    local selected = menu.sample.fleets[menu.selectedFleet]
    if selected then
        local selectedFleetKey = fleetKey(selected)
        section(tableWidget, selected.commander.fleetname .. "  |  EDITING THIS FLEET")
        textRow(tableWidget, "Flagship", selected.commander.name .. " [" .. selected.commander.idcode .. "]", headingColor)
        textRow(tableWidget, "Current location", selected.commander.sector .. "  |  " .. tostring(selected.shipCount) .. " ship(s)", neutralColor)
        textRow(tableWidget, "Captain / condition", selected.commander.captain .. " - " .. selected.commander.captainState .. "  |  Hull " .. percent(selected.commander.hull) .. "  |  Shields " .. percent(selected.commander.shield), statusColor(selected.status))
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
        if selected.missionProtected then
            textRow(tableWidget, "Quest protection", "MISSION / QUEST FLEET - FOC WILL NEVER CHANGE THIS FLEET. NO OVERRIDE IS AVAILABLE.", failureColor)
        elseif selected.commander.primarypurpose ~= "fight" then
            textRow(tableWidget, "Reaction-force scope", "NON-COMBAT COMMANDER (" .. string.upper(selected.commander.primarypurpose) .. ") - SUPPLY OR LOGISTICS ORDERS ARE PROTECTED BY DEFAULT.", warningColor)
            actionRow(tableWidget, "Override", orders.nonCombatOverride and "OVERRIDE ACTIVE - DO THIS ANYWAY" or "OVERRIDE - DO THIS ANYWAY", function()
                orders.nonCombatOverride = not orders.nonCombatOverride
                markFleetOrdersChanged(selectedFleetKey, orders)
                rebuild(false)
            end, true, warningColor)
        end

        section(tableWidget, "1  NORMAL PATROL")
        dropdownRow(tableWidget, "Fleet job", fleetRoles, orders.fleetRole, function(value) orders.fleetRole = tostring(value); markFleetOrdersChanged(selectedFleetKey, orders) end)
        actionRow(tableWidget, "Home sector", homeSectorName, function() chooseHomeOnMap(selected) end, true, homeSector and headingColor or warningColor)
        actionRow(tableWidget, "Choose home", "CHOOSE HOME POINT ON MAP", function() chooseHomeOnMap(selected) end, true, activeTabBackground)
        textRow(tableWidget, "Home point", homePointText(homeSector), homeSector and headingColor or warningColor)
        textRow(tableWidget, "How to choose", "Open the map and move to any sector you have discovered. Right-click the exact spot the fleet should use as home. Choose SET AS FOC HOME POINT. FOC saves the sector and spot, then returns here. No orders are sent.", headingColor)
        if menu.plan.lastState == "ACTION_REQUIRED_HOME" then
            actionRequired(tableWidget,
                "FOC could not open the safe X4 Home-point choice.",
                "The required native right-click menu was not available.",
                "Close other map or interaction menus, return to Fleets, and press CHOOSE HOME POINT ON MAP again.",
                "fleets", "TRY FLEETS AGAIN")
        end
        dropdownRow(tableWidget, "Patrol distance", coverageRanges, orders.coverage, function(value) orders.coverage = tostring(value); markFleetOrdersChanged(selectedFleetKey, orders) end)
        dropdownRow(tableWidget, "Patrol sectors", patrolSectorChoices, orders.sectorChoice, function(value) orders.sectorChoice = tostring(value); markFleetOrdersChanged(selectedFleetKey, orders) end)
        dropdownRow(tableWidget, "Patrol pattern", patrolPatterns, orders.patrolPattern, function(value) orders.patrolPattern = tostring(value); markFleetOrdersChanged(selectedFleetKey, orders) end)

        section(tableWidget, "2  DISTRESS CALLS")
        dropdownRow(tableWidget, "Help my ships", yesNoOptions, orders.respondShips, function(value) orders.respondShips = tostring(value); markFleetOrdersChanged(selectedFleetKey, orders) end)
        dropdownRow(tableWidget, "Help my stations", yesNoOptions, orders.respondStations, function(value) orders.respondStations = tostring(value); markFleetOrdersChanged(selectedFleetKey, orders) end)
        dropdownRow(tableWidget, "Help anyone else", distressScopes, orders.distress, function(value) orders.distress = tostring(value); markFleetOrdersChanged(selectedFleetKey, orders) end)
        dropdownRow(tableWidget, "Minimum urgency", urgencyOptions, orders.distressUrgency, function(value) orders.distressUrgency = tonumber(value) or 5; markFleetOrdersChanged(selectedFleetKey, orders) end, " / 10")
        textRow(tableWidget, "Urgency scale", "FOC derives urgency from damage: 1 is light damage; 10 is critical damage.", neutralColor)
        dropdownRow(tableWidget, "Help ships below", damageOptions, orders.shipDamage, function(value) orders.shipDamage = tonumber(value) or 70; markFleetOrdersChanged(selectedFleetKey, orders) end, "% hull")
        dropdownRow(tableWidget, "Help stations below", damageOptions, orders.stationDamage, function(value) orders.stationDamage = tonumber(value) or 70; markFleetOrdersChanged(selectedFleetKey, orders) end, "% hull")
        dropdownRow(tableWidget, "Return to patrol", yesNoOptions, orders.returnHome, function(value) orders.returnHome = tostring(value); markFleetOrdersChanged(selectedFleetKey, orders) end)

        section(tableWidget, "3  READY TO SEND")
        local route = tableWidget:addRow(false)
        route[1]:createText("HOME", { halign = "center", color = passColor })
        route[2]:createText("PATROL AREA", { halign = "center", color = headingColor })
        route[3]:createText("DISTRESS CALL", { halign = "center", color = warningColor })
        route[4]:createText("RETURN", { halign = "center", color = passColor })
        local routeValues = tableWidget:addRow(false)
        routeValues[1]:createText(homeSectorName, { halign = "center" })
        routeValues[2]:createText(orders.coverage .. "\n" .. orders.patrolPattern, { halign = "center", wordwrap = true })
        routeValues[3]:createText("Urgency " .. tostring(orders.distressUrgency) .. "+\nShip " .. tostring(orders.shipDamage) .. "% | Station " .. tostring(orders.stationDamage) .. "%", { halign = "center", wordwrap = true })
        routeValues[4]:createText(orders.returnHome == "YES" and "RETURN TO PATROL" or "STAY ON RESPONSE", { halign = "center", wordwrap = true })
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
        textRow(tableWidget, "Fleet status", patrolStatus, activeConfirmed and passColor or warningColor)
        textRow(tableWidget, "Hard safety", "Player control, mission/story protection, missing pilot or Home, non-combat scope, and critical non-cancelable orders still block the send.", passColor)

        section(tableWidget, "ADVANCED CONTROLS - OPTIONAL")
        actionRow(tableWidget, "Advanced", menu.showFleetAdvanced and "HIDE ADVANCED CONTROLS" or "SHOW ADVANCED CONTROLS", function() menu.showFleetAdvanced = not menu.showFleetAdvanced; rebuild(false) end, true, headingColor)
        if menu.showFleetAdvanced then
        textRow(tableWidget, "Route status", orders.routePreview or "OPTIONAL PREVIEW - NO ORDERS SENT.", orders.routePreview and headingColor or warningColor)
        local pendingDraft = menu.pendingDraftSaves[selectedFleetKey]
        buttonPairRow(tableWidget, pendingDraft and "SAVE PENDING - WAIT FOR READBACK" or "SAVE AS DRAFT", function()
            menu.plan.status = "DRAFT"
            if not homeSector then
                menu.plan.lastResult = "DRAFT NOT SAVED - CHOOSE A HOME POINT ON THE MAP"
                rebuild(false)
                return
            end
            requestFleetDraftSave(selected, selectedFleetKey, orders, homeSector)
        end, "CHECK ROUTE - NO ORDERS", function()
            if not homeSector then
                orders.routePreview = "BLOCKED: Choose a Home point on the map first. NO ORDERS SENT."
                rebuild(false)
                return
            end
            orders.routePreview = "PREVIEW ONLY - NO ORDERS SENT. CHECKED: " .. homeSector.text .. " > " .. orders.coverage .. " > DISTRESS " .. tostring(orders.distressUrgency) .. "+ > " .. (orders.returnHome == "YES" and "RETURN TO PATROL" or "STAY ON RESPONSE") .. ". Use SEND THIS FLEET ON PATROL when ready."
            auditAction("PREVIEW_ROUTE", selectedFleetAudit .. " home=" .. homeSector.text .. " home_key=" .. homeSector.id, orders.routePreview, "PREVIEW_COMPLETE")
        end, activeTabBackground, not pendingDraft, true)
        textRow(tableWidget, "Draft status", savedDraft and "DRAFT SAVED IN GAME STATE - NO ORDERS WERE SENT" or pendingDraft and "SAVE REQUEST SENT - WAITING FOR PERSISTENT READBACK" or "NOT SAVED - PRESS SAVE AS DRAFT", savedDraft and passColor or warningColor)
        actionRow(tableWidget, "Automation lock", orders.locked and "LOCKED - FOC CANNOT CHANGE THIS FLEET" or "UNLOCKED - APPROVED PLANS MAY CHANGE THIS FLEET", function() orders.locked = not orders.locked; markFleetOrdersChanged(selectedFleetKey, orders); rebuild(false) end, true, warningColor)
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
    local vacancies = academy.vacancies
    if not selectedAcademyVacancy(vacancies) then academy.selectedVacancyID = vacancies[1] and vacancies[1].key or nil end
    local recruit = selectedAcademyRecruit()
    local vacancy = selectedAcademyVacancy(vacancies)

    local function rejectLocal(message)
        menu.plan.lastState = "BLOCKED"
        menu.plan.lastResult = message
        menu.notice = message
        academy.previewPair = nil
        rebuild(false)
    end

    section(tableWidget, "TRAINING ACADEMY")
    textRow(tableWidget, "Purpose", "Maintain a station-based reserve of up to 25 pilot trainees without removing marines or service crew from deployed ships.", headingColor)
    textRow(tableWidget, "Capacity", tostring(#academy.rows) .. " / 25 retained trainees", #academy.rows < 25 and warningColor or passColor)
    textRow(tableWidget, "Recruitment safety", "Operational player-owned stations only. Mission/story personnel, managers, existing captains, shipboard crew, and marines are never selected.", passColor)
    actionRow(tableWidget, "Recruitment", "PREVIEW RECRUITMENT", function()
        academy.previewRecruitReady = false
        auditAction("ACADEMY_PREVIEW_RECRUIT", "CAPACITY_25", "RECRUITMENT PREVIEW REQUESTED - NO PERSONNEL CHANGED", "ACADEMY_PREVIEW_PENDING")
    end, #academy.rows < 25, headingColor)
    actionRow(tableWidget, "Recruitment", "APPROVE RECRUITMENT TO CAPACITY", function()
        academy.previewRecruitReady = false
        auditAction("ACADEMY_RECRUIT", "CAPACITY_25", "ACADEMY RECRUITMENT REQUEST SENT - NATIVE READBACK REQUIRED", "ACADEMY_RECRUIT_PENDING")
    end, menu.plan.lastState == "ACADEMY_RECRUIT_READY" and #academy.rows < 25, warningColor)

    section(tableWidget, "BULK PROMOTE AND ASSIGN")
    textRow(tableWidget, "Batch rule", "Immediately processes at most 25 retained trainees, highest current piloting skill first. The complete batch seminar requirement is checked before anything changes.", headingColor)
    textRow(tableWidget, "Native safety", "Every trainee and ship is revalidated. Each captain must reach five stars and match the ship's native assigned-pilot readback before that Academy record is removed.", passColor)
    actionRow(tableWidget, "Bulk approval", "PROMOTE AND ASSIGN NEXT 25 CAPTAINS", function()
        if menu.pendingActionKind then
            rejectLocal("BULK ASSIGNMENT BLOCKED - ANOTHER FOC TRANSACTION IS STILL PENDING | NOTHING CHANGED")
            return
        end
        if #academy.rows == 0 or #academy.vacancies == 0 then
            rejectLocal("BULK ASSIGNMENT BLOCKED - RECRUIT TRAINEES AND REQUIRE AT LEAST ONE PROVEN CAPTAIN VACANCY | NOTHING CHANGED")
            return
        end
        academy.previewPair = nil
        auditAction("ACADEMY_BULK_ASSIGN", "SKILL_DESCENDING_BOUND_25", "BULK CAPTAIN REQUEST SENT - COMPLETE SEMINAR PREFLIGHT AND NATIVE READBACK REQUIRED", "ACADEMY_BULK_PENDING")
    end, #academy.rows > 0 and #academy.vacancies > 0 and menu.pendingActionKind == nil, warningColor)

    section(tableWidget, "SELECT SHIP AND CREW")
    if #vacancies == 0 then
        textRow(tableWidget, "1. Destination ship", "No proven captain vacancy is available in the current bounded sample.", passColor)
    else
        local options = {}
        for _, issue in ipairs(vacancies) do
            options[#options + 1] = { id = issue.key, text = issue.name .. " [" .. issue.idcode .. "] - " .. issue.sector, icon = "", displayremoveoption = false }
        end
        local row = tableWidget:addRow(true)
        row[1]:createText("1. Destination ship", { color = neutralColor })
        local dropdown = row[2]:setColSpan(3):createDropDown(options, { active = true, startOption = academy.selectedVacancyID, height = Helper.standardButtonHeight })
        row[2].handlers.onDropDownConfirmed = function(_, value)
            academy.selectedVacancyID = tostring(value or "")
            academy.previewAssignReady = false
            academy.previewPair = nil
            rebuild(false)
        end
    end

    if #academy.rows == 0 then
        textRow(tableWidget, "2. Trainee crew", "No retained trainees. Preview and approve recruitment first.", warningColor)
    else
        local options = {}
        for _, rowData in ipairs(academy.rows) do
            local rating = rowData.piloting and string.format("%.1f / 5", rowData.piloting / 3) or "UNKNOWN"
            options[#options + 1] = { id = tostring(rowData.id), text = rowData.name .. " | PILOTING " .. rating .. " | " .. rowData.origin, icon = "", displayremoveoption = false }
        end
        local row = tableWidget:addRow(true)
        row[1]:createText("2. Trainee crew", { color = neutralColor })
        local dropdown = row[2]:setColSpan(3):createDropDown(options, { active = true, startOption = academy.selectedRecruitID, height = Helper.standardButtonHeight })
        row[2].handlers.onDropDownConfirmed = function(_, value)
            academy.selectedRecruitID = tostring(value or "")
            academy.previewAssignReady = false
            academy.previewPair = nil
            rebuild(false)
        end
    end

    recruit = selectedAcademyRecruit()
    vacancy = selectedAcademyVacancy(vacancies)
    local canTrain = recruit and recruit.valid and recruit.piloting and recruit.piloting < 15 and recruit.seminarCount > 0
    local crewRow = tableWidget:addRow(true)
    local crewText = recruit and (recruit.name .. " | PILOTING " .. (recruit.piloting and string.format("%.1f / 5", recruit.piloting / 3) or "UNKNOWN") .. " | " .. recruit.seminar .. " x" .. tostring(recruit.seminarCount)) or "NO TRAINEE SELECTED"
    crewRow[1]:setColSpan(2):createText(crewText, { color = recruit and headingColor or warningColor })
    crewRow[3]:setColSpan(2):createButton({ active = canTrain == true, bgColor = canTrain and requiredActionBackground or availableActionBackground }):setText("TRAIN ONE SESSION", { halign = "center" })
    if canTrain == true then
        crewRow[3].handlers.onClick = function()
            local current = selectedAcademyRecruit()
            if not current or not current.valid or not current.piloting or current.piloting >= 15 or current.seminarCount <= 0 then
                rejectLocal("TRAINING BLOCKED - SELECTED TRAINEE OR APPLICABLE SEMINAR IS NO LONGER AVAILABLE | NOTHING CHANGED")
                return
            end
            auditAction("ACADEMY_TRAIN", tostring(current.id), "TRAINING REQUEST SENT - ONE SEMINAR MAXIMUM - INVENTORY AND SKILL READBACK REQUIRED", "ACADEMY_TRAIN_PENDING")
        end
    end

    section(tableWidget, "PREVIEW AND TRANSFER")
    textRow(tableWidget, "Selected pair", recruit and vacancy and (recruit.name .. " -> " .. vacancy.name .. " [" .. vacancy.idcode .. "]") or "SELECT ONE DESTINATION SHIP AND ONE TRAINEE", recruit and vacancy and headingColor or warningColor)
    actionRow(tableWidget, "Assignment", "PREVIEW SELECTED ASSIGNMENT", function()
        local currentRecruit = selectedAcademyRecruit()
        local currentVacancy = selectedAcademyVacancy(academy.vacancies)
        if not currentRecruit or not currentRecruit.valid or not currentVacancy then
            rejectLocal("ASSIGNMENT PREVIEW BLOCKED - SELECT ONE VALID TRAINEE AND ONE PROVEN CAPTAIN VACANCY | NOTHING CHANGED")
            return
        end
        local shipLuaID = componentLuaID(currentVacancy.component)
        if not shipLuaID then
            rejectLocal("ASSIGNMENT PREVIEW BLOCKED - SELECTED SHIP IDENTITY IS NO LONGER VALID | NOTHING CHANGED")
            return
        end
        academy.previewPair = tostring(currentRecruit.id) .. ":" .. currentVacancy.key
        auditAction("ACADEMY_PREVIEW_ASSIGN", tostring(currentRecruit.id), "ASSIGNMENT PREVIEW REQUESTED - NO PERSONNEL CHANGED", "ACADEMY_ASSIGN_PREVIEW_PENDING", shipLuaID)
    end, recruit and recruit.valid and vacancy ~= nil, headingColor)
    local pair = recruit and vacancy and (tostring(recruit.id) .. ":" .. vacancy.key) or nil
    actionRow(tableWidget, "Assignment", "TRANSFER SELECTED CREW TO SELECTED SHIP", function()
        local currentRecruit = selectedAcademyRecruit()
        local currentVacancy = selectedAcademyVacancy(academy.vacancies)
        local currentPair = currentRecruit and currentVacancy and (tostring(currentRecruit.id) .. ":" .. currentVacancy.key) or nil
        if not currentRecruit or not currentRecruit.valid or not currentVacancy or currentPair ~= academy.previewPair or menu.plan.lastState ~= "ACADEMY_ASSIGN_READY" then
            rejectLocal("TRANSFER BLOCKED - THE SELECTED CREW-TO-SHIP PAIR MUST PASS A FRESH PREVIEW | NOTHING CHANGED")
            return
        end
        local shipLuaID = componentLuaID(currentVacancy.component)
        if not shipLuaID then
            rejectLocal("TRANSFER BLOCKED - SELECTED SHIP IDENTITY IS NO LONGER VALID | NOTHING CHANGED")
            return
        end
        auditAction("ACADEMY_ASSIGN", tostring(currentRecruit.id), "CAPTAIN TRANSFER REQUEST SENT - EXACT PILOT READBACK REQUIRED", "ACADEMY_ASSIGN_PENDING", shipLuaID)
        academy.previewPair = nil
    end, pair and academy.previewPair == pair and menu.plan.lastState == "ACADEMY_ASSIGN_READY", warningColor)
    textRow(tableWidget, "Last result", menu.plan.lastResult, needsAction(menu.plan.lastResult) and warningColor or passColor)
end

local function previewPage(tableWidget, title, lines)
    section(tableWidget, title)
    for _, line in ipairs(lines) do textRow(tableWidget, line[1], line[2], line[3]) end
end

local function doctrinePage(tableWidget)
    local selected = menu.sample.fleets[menu.selectedFleet]
    local orders = selected and ordersForFleet(selected) or nil
    section(tableWidget, "HOME, COVERAGE, AND PATROL")
    textRow(tableWidget, "Stable fleet", selected and (selected.commander.name .. " [" .. selected.commander.idcode .. "]") or "SELECT A FLEET TO CONTINUE", selected and headingColor or warningColor)
    local homeSector = selected and homeSectorForFleet(selected) or nil
    actionRow(tableWidget, "Home sector", homeSector and homeSector.text or "CHOOSE ON FLEETS TAB", function() menu.page = "fleets"; menu.phase.fleets = "registry"; rebuild(true) end, selected ~= nil, headingColor)
    actionRow(tableWidget, "Coverage range", orders and orders.coverage or "BLOCKED - SELECT A FLEET", function() orders.coverage = cycle(orders.coverage, coverageRanges); markFleetOrdersChanged(fleetKey(selected), orders); rebuild(false) end, selected ~= nil, headingColor)
    textRow(tableWidget, "Sector controls", "Included sectors: DRAFT | Excluded sectors: DRAFT | Owned stations prioritized: YES | Return point: HOME ANCHOR", neutralColor)
    textRow(tableWidget, "Route scoring", "Gate distance, owned assets, traffic, distress history, threat, and available resupply. Missing map or threat evidence blocks automatic routing.", passColor)
    textRow(tableWidget, "Chase limit", "Coverage boundary; pursuit outside coverage: DISABLED", warningColor)
    textRow(tableWidget, "Protections", "Player control, manual orders, mission/story ships, emergency actions, commander changes, and never-touch locks block mutation.", passColor)
    actionRow(tableWidget, "Doctrine", "PREVIEW EFFECTIVE PATROL PLAN", function() previewPatrolPlan(selected, orders, homeSector) end, selected ~= nil, headingColor)
    textRow(tableWidget, "Preview result", menu.previews.patrol or "Press PREVIEW EFFECTIVE PATROL PLAN to build a non-mutating patrol summary.", menu.previews.patrol and (menu.previews.patrol:find("BLOCKED") and warningColor or passColor) or warningColor)
    actionRow(tableWidget, "Doctrine profile", "CHOOSE A FLEET TO COPY OR EDIT", function() menu.page = "fleets"; menu.activeTab = "fleets"; rebuild(true) end, true, warningColor)
    if not selected or not homeSector or (menu.previews.patrol and menu.previews.patrol:find("BLOCKED")) then
        actionRequired(tableWidget,
            "FOC did not build an approvable patrol plan.",
            not selected and "No fleet is selected." or "This fleet does not have a confirmed Home point.",
            "Open Fleets, choose the fleet, set its Home point on the map, save the draft, then return here and preview again.",
            "fleets", "OPEN FLEETS")
    end
end

local function responsePage(tableWidget)
    local selected = menu.sample.fleets[menu.selectedFleet]
    local orders = selected and ordersForFleet(selected) or nil
    section(tableWidget, "FLEET RESPONSE RULES")
    actionRow(tableWidget, "Distress scope", orders and orders.distress or "BLOCKED - SELECT A FLEET", function() orders.distress = cycle(orders.distress, distressScopes); markFleetOrdersChanged(fleetKey(selected), orders); rebuild(false) end, selected ~= nil, headingColor)
    textRow(tableWidget, "Ownership", "My ships: YES | My stations: YES | Allied ships: " .. (orders and orders.distress == "PLAYER AND ALLIED" and "YES" or "NO") .. " | Friendly/neutral: " .. (orders and orders.distress == "FRIENDLY OR NEUTRAL" and "YES" or "NO"), neutralColor)
    textRow(tableWidget, "Eligibility", "Minimum severity: HIGH | Maximum threat: MATCHED | Minimum readiness: READY | Incident age: 120 seconds", neutralColor)
    textRow(tableWidget, "Dispatch bounds", "Maximum fleets per incident: 1 | Reinforcements: NO | Pursuit outside coverage: NO | one mutation per cycle", passColor)
    textRow(tableWidget, "Abort conditions", "Player control, manual order, mission/story protection, readiness loss, unknown route/threat, home loss, stale incident, or coverage exit.", passColor)
    textRow(tableWidget, "Maintenance", "Repair below 80% hull | resupply evidence required | return home and verify back-on-post", neutralColor)
    actionRow(tableWidget, "Current orders", orders and orders.manualOverride and "PRESERVE CURRENT ORDERS - FOC BLOCKED" or "ALLOW FOC TO CANCEL / REPLACE ELIGIBLE ORDERS", function() orders.manualOverride = not orders.manualOverride; markFleetOrdersChanged(fleetKey(selected), orders); rebuild(false) end, selected ~= nil, warningColor)
    section(tableWidget, "DISPATCH DECISION")
    textRow(tableWidget, "Selected fleet", selected and selected.commander.name or "NONE", selected and headingColor or warningColor)
    textRow(tableWidget, "Decision evidence", "Record distressed identity/source/location/age/ownership, eligibility, selected fleet or refusal, requested action, native readback, blocker, and next state.", passColor)
    actionRow(tableWidget, "Response", "PREVIEW DISPATCH", function() previewDispatchPlan(selected, orders) end, selected ~= nil, headingColor)
    textRow(tableWidget, "Preview result", menu.previews.dispatch or "Press PREVIEW DISPATCH to evaluate the selected fleet against current incident evidence.", menu.previews.dispatch and (menu.previews.dispatch:find("BLOCKED") and warningColor or passColor) or warningColor)
    actionRow(tableWidget, "Response", "APPROVE ONE DISPATCH", function()
        if not menu.previews.dispatch or menu.previews.dispatch:find("BLOCKED") then
            auditAction("APPROVE_DISPATCH", selected and selected.commander.idcode or "NONE", "DISPATCH NOT SENT - THERE IS NO CURRENT APPROVABLE INCIDENT PREVIEW. NOTHING CHANGED.", "ACTION_REQUIRED_DISPATCH")
        elseif not selected or selected.missionProtected or (selected.commander.primarypurpose ~= "fight" and not orders.nonCombatOverride) then
            auditAction("APPROVE_DISPATCH", selected and selected.commander.idcode or "NONE", "DISPATCH NOT SENT - MISSION PROTECTION OR NON-COMBAT OVERRIDE BLOCKED THIS FLEET. NOTHING CHANGED.", "ACTION_REQUIRED_DISPATCH")
        elseif selected.commander.playerOccupied or selected.status ~= "READY" then
            auditAction("APPROVE_DISPATCH", selected and selected.commander.idcode or "NONE", "DISPATCH NOT SENT - THE SELECTED FLEET IS NOT READY OR IS PLAYER-CONTROLLED. NOTHING CHANGED.", "ACTION_REQUIRED_DISPATCH")
        else
            auditAction("APPROVE_DISPATCH", selected.commander.idcode, "DISPATCH REQUEST SENT - WAITING FOR NATIVE INCIDENT/ORDER READBACK", "DISPATCH_PENDING")
        end
    end, selected ~= nil, warningColor)
    if menu.plan.lastState == "ACTION_REQUIRED_DISPATCH" or (menu.previews.dispatch and menu.previews.dispatch:find("BLOCKED")) then
        actionRequired(tableWidget,
            "FOC did not dispatch the selected fleet.",
            "There is no fresh, eligible distress incident and verified route for this fleet.",
            "Open Fleets, confirm the fleet Home and distress settings, save its draft, then return when an active incident appears and preview again.",
            "fleets", "OPEN FLEETS")
    end
end

local function settingsPage(tableWidget)
    section(tableWidget, "GLOBAL AUTOMATION")
    dropdownRow(tableWidget, "Master mode", automationModes, menu.plan.authority, function(value)
        menu.plan.authority = tostring(value)
        menu.plan.status = "DRAFT"
        auditAction("MODE_CHANGE", "GLOBAL", "MASTER MODE CHANGED TO " .. menu.plan.authority .. " - NO PLAN WAS APPLIED", "AUTHORITY_CHANGED")
        return false
    end)
    local modeMeaning = menu.plan.authority == "PREVIEW PLAN" and "PREVIEW ONLY - NO ORDERS CAN BE SENT."
        or menu.plan.authority == "APPLY APPROVED PLAN" and "ARMED - THIS TOGGLE SENDS NOTHING. Return to Command and press APPLY APPROVED PLAN - SEND ORDERS."
        or "FULL AUTOMATION AUTHORIZED - the bounded scheduler may send eligible orders automatically."
    textRow(tableWidget, "Mode meaning", modeMeaning, menu.plan.authority == "PREVIEW PLAN" and warningColor or passColor)
    actionRow(tableWidget, "Plan", "PREVIEW CURRENT PLAN", previewGlobalPlan, true, headingColor)
    local stopped = menu.plan.status == "STOPPED" and menu.plan.authority == "PREVIEW PLAN"
    actionRow(tableWidget, "Emergency", stopped and "FOC AUTOMATION ALREADY STOPPED" or "STOP FOC AUTOMATION", function() menu.plan.authority = "PREVIEW PLAN"; menu.plan.status = "STOPPED"; auditAction("STOP_AUTOMATION", "GLOBAL", "FOC AUTOMATION STOPPED - PERSISTENT READBACK REQUIRED", "STOPPED") end, not stopped, warningColor)
    textRow(tableWidget, "Planner duties", "Inventory ships/personnel; fill proven vacancies; preserve locks; identify grouped ships; choose commanders/roles/names/homes; spread coverage; route patrols; retain reserve; warn on gaps, overlap, and overextension.", neutralColor)
    textRow(tableWidget, "Replacement boundary", "Destroyed-member replacement may create a recommendation only. No purchase, construction, credit spend, or staffing guess is authorized.", passColor)
    textRow(tableWidget, "Rebalance threshold", "25% minimum modeled benefit; 30 second cooldown; duplicate suppression; bounded backoff; maximum one native mutation per cycle.", neutralColor)
    section(tableWidget, "HARD PERFORMANCE AND SAFETY LIMITS")
    textRow(tableWidget, "Ship sample cap", tostring(MAX_SHIPS_PER_SAMPLE), neutralColor)
    textRow(tableWidget, "Fleet display cap", tostring(MAX_FLEETS_DISPLAYED), neutralColor)
    textRow(tableWidget, "Member cap per fleet", "100", neutralColor)
    textRow(tableWidget, "History limit", tostring(HISTORY_LIMIT), neutralColor)
    textRow(tableWidget, "Scheduler", "No per-frame scan or mutation. Open/refresh inventory is bounded; automation requests are cooldown guarded.", passColor)
    textRow(tableWidget, "Runtime status", "RUNTIME ACCEPTANCE REQUIRED", warningColor)
end

local function activityPage(tableWidget)
    section(tableWidget, "BOUNDED SESSION ACTIVITY")
    local first, last = addPager(tableWidget, "activity.history", #menu.history, { fixedRows = 8, rowUnits = 3, contentPixels = menu.listContentHeight, maximum = 8 })
    for index = first, last do
        local sample = menu.history[index]
        if sample then
        local row = tableWidget:addRow(false)
        row[1]:createText("SAMPLE " .. tostring(index))
        row[2]:createText(sample.reason)
        row[3]:createText("Ships: " .. tostring(sample.shipsExamined))
        row[4]:createText("Fleets: " .. tostring(sample.fleetCount) .. " | Missing captains: " .. tostring(sample.missingCaptains) .. " | State: " .. tostring(sample.state or "SAMPLED") .. "\n" .. safeText(sample.result, "No additional result recorded."), { wordwrap = true, color = needsAction(sample.result) and warningColor or passColor })
        end
    end
end

local function configureColumns(tableWidget, width)
    local columnWidth = math.floor((width - 4 * Helper.borderSize) / 4)
    tableWidget:setColWidth(1, columnWidth, false)
    tableWidget:setColWidth(2, columnWidth, false)
    tableWidget:setColWidth(3, columnWidth, false)
    tableWidget:setDefaultCellProperties("text", { fontsize = Helper.standardFontSize })
end

function menu.create()
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
        fleetOrdersPane(ordersTable)
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
    pageGuide(tableWidget)
    if menu.page == "command" then commandPage(tableWidget)
    elseif menu.page == "readiness" then readinessPage(tableWidget)
    elseif menu.page == "academy" then academyPage(tableWidget)
    elseif menu.page == "doctrine" then doctrinePage(tableWidget)
    elseif menu.page == "response" then responsePage(tableWidget)
    elseif menu.page == "activity" then activityPage(tableWidget)
    else settingsPage(tableWidget) end
    if menu.restoreTopRow then pcall(tableWidget.setTopRow, tableWidget, menu.restoreTopRow) end
    menu.restoreTopRow = nil
    menu.frame:display()
    menu.renderedPage = menu.page
end

function menu.refresh(preserveScroll)
    if preserveScroll ~= false and menu.mainTable and menu.mainTable.id then
        local ok, top = pcall(GetTopRow, menu.mainTable.id)
        if ok then menu.restoreTopRow = top end
    end
    menu.create()
end

function menu.onShowMenu()
    menu.param = menu.param or {}
    menu.param[1] = tonumber(menu.param[1]) or 0
    menu.param[2] = tonumber(menu.param[2]) or 0
    if menu.param[6] == "PREVIEW PLAN" or menu.param[6] == "APPLY APPROVED PLAN" or menu.param[6] == "FULL AUTOMATION" then menu.plan.authority = menu.param[6] end
    if menu.param[7] and tostring(menu.param[7]) ~= "" then menu.plan.lastResult = tostring(menu.param[7]) end
    if menu.param[8] and tostring(menu.param[8]) ~= "" then menu.plan.lastState = tostring(menu.param[8]) end
    if menu.plan.lastState == "STOPPED" then menu.plan.status = "STOPPED" end
    local authoritativeDraftRows = type(menu.param[9]) == "table"
    if authoritativeDraftRows then
        menu.ordersByFleet = {}
        menu.homeSectorByFleet = {}
        menu.draftsByFleet = {}
        menu.pendingDraftSaves = {}
    end
    local restoredDrafts = restorePersistentDrafts(menu.param[9])
    loadAcademyRows(menu.param[11])
    loadProtectedShipIDs(menu.param[12])
    loadVacancyRows(menu.param[13])
    if authoritativeDraftRows and restoredDrafts > 0 then
        menu.notice = "RESTORED " .. tostring(restoredDrafts) .. " SAVED FLEET DRAFT(S) FROM THE GAME SAVE"
        DebugError("[FOC][B020][DRAFT_RESTORE] schema=3_or_4 ownership=MD_NATIVE_OBJECT restored=" .. tostring(restoredDrafts) .. " mutation=NONE")
    elseif authoritativeDraftRows then
        DebugError("[FOC][B020][DRAFT_RESTORE] schema=3_or_4 ownership=MD_NATIVE_OBJECT restored=0 reason=NO_SAVED_DRAFTS mutation=NONE")
    end
    if menu.pendingHomeSelection then
        menu.pendingHomeSelection = nil
        menu.plan.lastResult = "HOME POINT NOT CHANGED - MAP CLOSED WITHOUT CHOOSING SET AS FOC HOME POINT"
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
    menu.create()
end

function menu.onCloseElement(reason, layer)
    if menu.frame == nil or menu.closeInProgress then return end
    menu.closeInProgress = true
    AddUITriggeredEvent(menu.name, "closed", { reason = reason or "close" })
    Helper.closeMenu(menu, reason or "close", layer)
    menu.frame = nil
    menu.closeInProgress = false
end

function menu.onUpdate() end
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
        DebugError("[FOC][B020][LUA_ERROR] Helper.registerMenu unavailable")
    end
    RegisterEvent(menu.name .. ".draft.key", draftKeyReceived)
    RegisterEvent(menu.name .. ".draft.result", draftResultReceived)
    RegisterEvent(menu.name .. ".draft.state", draftStateReceived)
    RegisterEvent(menu.name .. ".draft.complete", draftSaveComplete)
    RegisterEvent(menu.name .. ".action.result", actionResultReceived)
    RegisterEvent(menu.name .. ".action.state", actionStateReceived)
    RegisterEvent(menu.name .. ".action.complete", actionComplete)
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
    RegisterEvent(menu.name .. ".academy.snapshot.row.commit", academySnapshotRowCommit)
    RegisterEvent(menu.name .. ".academy.snapshot.complete", academySnapshotComplete)
    RegisterEvent(menu.name .. ".protected.snapshot.begin", protectedSnapshotBegin)
    RegisterEvent(menu.name .. ".protected.snapshot.id", protectedSnapshotID)
    RegisterEvent(menu.name .. ".protected.snapshot.complete", protectedSnapshotComplete)
    RegisterEvent(menu.name .. ".vacancy.snapshot.begin", vacancySnapshotBegin)
    RegisterEvent(menu.name .. ".vacancy.snapshot.component", vacancySnapshotComponent)
    RegisterEvent(menu.name .. ".vacancy.snapshot.name", vacancySnapshotName)
    RegisterEvent(menu.name .. ".vacancy.snapshot.idcode", vacancySnapshotIDCode)
    RegisterEvent(menu.name .. ".vacancy.snapshot.sector", vacancySnapshotSector)
    RegisterEvent(menu.name .. ".vacancy.snapshot.row.commit", vacancySnapshotRowCommit)
    RegisterEvent(menu.name .. ".vacancy.snapshot.complete", vacancySnapshotComplete)
end

init()
