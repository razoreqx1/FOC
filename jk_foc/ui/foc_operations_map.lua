local ffi = require("ffi")

ffi.cdef[[
typedef uint64_t UniverseID;
typedef struct { float x; float y; float z; float yaw; float pitch; float roll; } UIPosRot;
typedef struct { UIPosRot offset; float cameradistance; } HoloMapState;
UniverseID AddHoloMap(const char* texturename, float x0, float x1, float y0, float y1, float aspectx, float aspecty);
void ClearSelectedMapComponents(UniverseID holomapid);
UniverseID GetContextByClass(UniverseID componentid, const char* classname, bool includeself);
void GetMapState(UniverseID holomapid, HoloMapState* state);
UniverseID GetMapPositionOnEcliptic2(UniverseID holomapid, UIPosRot* position, bool adaptiveecliptic, UniverseID eclipticsectorid, UIPosRot eclipticoffset);
UniverseID GetPickedMapComponent(UniverseID holomapid);
bool IsKnownToPlayer(UniverseID componentid);
bool IsComponentClass(UniverseID componentid, const char* classname);
void RemoveHoloMap(void);
void SetMapFocus(UniverseID holomapid, bool value);
void SetMapPicking(UniverseID holomapid, bool enable);
void SetMapRelativeMousePosition(UniverseID holomapid, bool valid, float x, float y);
void SetMapRenderAllGateConnections(UniverseID holomapid, bool value);
void SetMapRenderAllOrderQueues(UniverseID holomapid, bool value);
void SetMapRenderCivilianShips(UniverseID holomapid, bool value);
void SetMapRenderEclipticLines(UniverseID holomapid, bool value);
void SetMapRenderResourceInfo(UniverseID holomapid, bool value);
void SetMapRenderSelectionLines(UniverseID holomapid, bool value);
void SetMapRenderTradeOffers(UniverseID holomapid, bool value);
void SetSelectedMapComponent(UniverseID holomapid, UniverseID componentid);
void ShowUniverseMap2(UniverseID holomapid, bool setoffset, bool showzone, bool forcebuildershipicons, UniverseID startsectorid, UIPosRot startpos);
void StartPanMap(UniverseID holomapid);
void StartRotateMap(UniverseID holomapid);
bool StopPanMap(UniverseID holomapid);
bool StopRotateMap(UniverseID holomapid);
void ZoomMap(UniverseID holomapid, float zoomstep);
]]

local C = ffi.C
local menu = {
    name = "FOC_OperationsMap",
    holomap = 0,
    map = nil,
    activatemap = nil,
    leftdown = nil,
    rightdown = nil,
    panningmap = nil,
    rotatingmap = nil,
    noupdate = false,
    dropdownActive = false,
    closeInProgress = false,
    inputTraceCount = 0,
    stateTraceCount = 0,
    cleanupCount = 0,
    analysisFilter = "OVERVIEW",
    pirateObservations = {},
    patrolTraversals = {},
    strategicObservations = {},
    gateEdges = {},
    routeRects = {},
    routeScan = nil,
    routeCenters = {},
    routeDirtyAt = nil,
    hoverCandidate = nil,
    hoverCandidateAt = 0,
    hoveredSectorName = nil,
    hoveredSectorID = nil,
    nextHoverAt = 0,
    notice = "DRAG TO PAN | RIGHT-DRAG TO ROTATE | WHEEL TO ZOOM | CLICK A KNOWN MAP ITEM",
}

local config = {
    mapLayer = 6,
    overlayLayer = 5,
    inputTraceLimit = 48,
    stateTraceLimit = 16,
    maxObservationRows = 4,
    hoverInterval = 0.08,
    hoverDebounce = 0.12,
    routeGridX = 65,
    routeGridY = 37,
    routeSamplesPerUpdate = 36,
    maxRouteStrokes = 120,
}

local cyan = { r = 95, g = 205, b = 235, a = 100 }
local green = { r = 90, g = 220, b = 125, a = 100 }
local amber = { r = 255, g = 190, b = 70, a = 100 }
local red = { r = 255, g = 75, b = 75, a = 100 }
local neutral = { r = 185, g = 195, b = 205, a = 100 }
local yellow = { r = 255, g = 224, b = 80, a = 92 }
local filterOptions = {
    { id = "OVERVIEW", text = "OVERVIEW", icon = "", displayremoveoption = false },
    { id = "COMBAT HOTSPOTS", text = "COMBAT HOTSPOTS", icon = "", displayremoveoption = false },
    { id = "PIRATE ACTIVITY", text = "PIRATE ACTIVITY", icon = "", displayremoveoption = false },
    { id = "TRADE ROUTE RISK", text = "TRADE ROUTE RISK", icon = "", displayremoveoption = false },
    { id = "HEAVY PATROL ROUTES", text = "HEAVY PATROL ROUTES", icon = "", displayremoveoption = false },
    { id = "LOGISTICS PRESSURE", text = "LOGISTICS PRESSURE", icon = "", displayremoveoption = false },
    { id = "ECONOMIC HOTSPOTS", text = "ECONOMIC HOTSPOTS", icon = "", displayremoveoption = false },
    { id = "EMPIRE TROUBLE SPOTS", text = "EMPIRE TROUBLE SPOTS", icon = "", displayremoveoption = false },
    { id = "HISTORICAL TRENDS", text = "HISTORICAL TRENDS", icon = "", displayremoveoption = false },
}

local function safeText(value, fallback)
    if value == nil or tostring(value) == "" then return fallback or "UNKNOWN" end
    return tostring(value)
end

local function clippedText(value, fallback, limit)
    local text = safeText(value, fallback)
    local maximum = tonumber(limit) or 120
    if #text > maximum then return text:sub(1, maximum - 3) .. "..." end
    return text
end

local function safeComponent64(value)
    if value == nil or value == 0 then return nil end
    local raw = tostring(value)
    if raw == "" or raw:match("^0+[uUlL]*$") or raw:match("^0[xX]0+[uUlL]*$") then return nil end
    if not raw:match("^%d+[uUlL]*$") then return nil end
    local ok, converted = pcall(ConvertStringTo64Bit, raw)
    if not ok or converted == nil or converted == 0 then return nil end
    local validOK, valid = pcall(IsValidComponent, converted)
    if not validOK or not valid then return nil end
    return converted
end

local function componentName(component64)
    local converted = safeComponent64(component64)
    if not converted then return nil end
    local idOK, luaID = pcall(ConvertStringToLuaID, tostring(converted))
    if not idOK or luaID == nil or luaID == 0 or tostring(luaID) == "" then return nil end
    local nameOK, name = pcall(GetComponentData, luaID, "name")
    if not nameOK or name == nil or tostring(name) == "" then return nil end
    return tostring(name)
end

local function resolveMapPosition(x, y)
    if menu.holomap == 0 or x == nil or y == nil then return nil end
    C.SetMapRelativeMousePosition(menu.holomap, true, x, y)
    local position = ffi.new("UIPosRot")
    local eclipticoffset = ffi.new("UIPosRot")
    local positionComponent = safeComponent64(C.GetMapPositionOnEcliptic2(menu.holomap, position, false, 0, eclipticoffset))
    local sector64 = positionComponent and safeComponent64(C.GetContextByClass(positionComponent, "sector", true)) or nil
    if not sector64 then return nil end
    local knownOK, known = pcall(C.IsKnownToPlayer, sector64)
    if not knownOK or not known then return nil end
    local name = componentName(sector64)
    if not name then return nil end
    return {
        sector = sector64, id = tostring(sector64), name = name,
        position = { tonumber(position.x) or 0, tonumber(position.y) or 0, tonumber(position.z) or 0 },
    }
end

local function routeKey(a, b)
    a, b = tostring(a or ""), tostring(b or "")
    if a == "" or b == "" or a == b then return nil end
    return a < b and (a .. ":" .. b) or (b .. ":" .. a)
end

local function hideRouteRects()
    for _, rect in ipairs(menu.routeRects or {}) do pcall(HideRect, rect) end
    menu.routeRects = {}
end

local function routeMetrics()
    local result = {}
    local cutoff = (tonumber(menu.gameTime) or 0) - (tonumber(menu.window) or 60) * 60
    if menu.analysisFilter == "PIRATE ACTIVITY" then
        local bySector = {}
        for _, entry in ipairs(menu.pirateObservations or {}) do
            if (tonumber(entry.time) or 0) >= cutoff then
                bySector[tostring(entry.sector)] = (bySector[tostring(entry.sector)] or 0) + (entry.severity == "RED_DAMAGE" and 3 or 1)
            end
        end
        for _, edge in ipairs(menu.gateEdges or {}) do
            local score = (bySector[tostring(edge.from)] or 0) + (bySector[tostring(edge.to)] or 0)
            local key = routeKey(edge.from, edge.to)
            if key and score > 0 then result[key] = { from = tostring(edge.from), to = tostring(edge.to), score = score } end
        end
    elseif menu.analysisFilter == "HEAVY PATROL ROUTES" then
        for _, entry in ipairs(menu.patrolTraversals or {}) do
            if (tonumber(entry.time) or 0) >= cutoff then
                local key = routeKey(entry.from, entry.to)
                if key then
                    result[key] = result[key] or { from = tostring(entry.from), to = tostring(entry.to), score = 0 }
                    result[key].score = result[key].score + 1
                end
            end
        end
    else
        local wanted = {
            ["COMBAT HOTSPOTS"] = { COMBAT = true, LOSS = true },
            ["TRADE ROUTE RISK"] = { TRADE_RISK = true, CONVOY_ATTACK = true, CONVOY_LOSS = true, CONVOY_SEPARATION = true },
            ["LOGISTICS PRESSURE"] = { LOGISTICS = true, SUPPLY_BLOCKED = true, SUPPLY_FAILED = true },
            ["ECONOMIC HOTSPOTS"] = { TRADE_COMPLETE = true, PRODUCTION = true },
            ["EMPIRE TROUBLE SPOTS"] = { COMBAT = true, LOSS = true, TRADE_RISK = true, CONVOY_ATTACK = true, CONVOY_LOSS = true, LOGISTICS = true, SUPPLY_BLOCKED = true, SUPPLY_FAILED = true },
            ["HISTORICAL TRENDS"] = { COMBAT = true, LOSS = true, TRADE_RISK = true, LOGISTICS = true, TRADE_COMPLETE = true, PRODUCTION = true },
        }
        local accepted, bySector = wanted[menu.analysisFilter] or {}, {}
        local priorCutoff = cutoff - (tonumber(menu.window) or 60) * 60
        for _, entry in ipairs(menu.strategicObservations or {}) do
            local when, sector = tonumber(entry.time) or 0, tostring(entry.sectorid or "")
            if accepted[tostring(entry.kind)] and sector ~= "" and when >= priorCutoff then
                local state = bySector[sector] or { current = 0, prior = 0 }
                local weight = math.max(1, tonumber(entry.severity) or tonumber(entry.amount) or 1)
                if when >= cutoff then state.current = state.current + weight else state.prior = state.prior + weight end
                bySector[sector] = state
            end
        end
        for _, edge in ipairs(menu.gateEdges or {}) do
            local left, right = bySector[tostring(edge.from)] or { current = 0, prior = 0 }, bySector[tostring(edge.to)] or { current = 0, prior = 0 }
            local score = left.current + right.current
            if menu.analysisFilter == "HISTORICAL TRENDS" then score = math.max(0, score - left.prior - right.prior) end
            local key = routeKey(edge.from, edge.to)
            if key and score > 0 then result[key] = { from = tostring(edge.from), to = tostring(edge.to), score = score } end
        end
    end
    return result
end

local function drawRouteStrokes()
    hideRouteRects()
    local metrics = routeMetrics()
    local ordered = {}
    local sectorScores = {}
    for _, entry in pairs(metrics) do ordered[#ordered + 1] = entry end
    for _, entry in ipairs(ordered) do
        sectorScores[entry.from] = math.max(sectorScores[entry.from] or 0, entry.score)
        sectorScores[entry.to] = math.max(sectorScores[entry.to] or 0, entry.score)
    end
    table.sort(ordered, function(a, b) return a.score > b.score end)
    local drawn = 0
    for _, entry in ipairs(ordered) do
        local from, to = menu.routeCenters[entry.from], menu.routeCenters[entry.to]
        if from and to and drawn < config.maxRouteStrokes then
            local color
            if menu.analysisFilter == "ECONOMIC HOTSPOTS" then color = entry.score >= 6 and green or entry.score >= 3 and cyan or yellow
            elseif menu.analysisFilter == "LOGISTICS PRESSURE" then color = entry.score >= 6 and amber or yellow
            else color = entry.score >= 6 and red or entry.score >= 3 and amber or yellow end
            local ok, rect = pcall(Helper.drawLine, { x = from.x, y = from.y }, { x = to.x, y = to.y }, entry.score >= 6 and 7 or 5, 1, color, true)
            if ok and rect then menu.routeRects[#menu.routeRects + 1] = rect; drawn = drawn + 1 end
        end
    end
    -- B060: fixed red plus signs removed; they were not sector boundaries.
end

local function startRouteScan(delay)
    hideRouteRects()
    menu.routeCenters = {}
    menu.routeScan = nil
    menu.routeDirtyAt = getElapsedTime() + (tonumber(delay) or 0.15)
end

local function beginRouteScan()
    if menu.analysisFilter == "OVERVIEW" or menu.holomap == 0 then return end
    local points = {}
    for yi = 0, config.routeGridY - 1 do
        local y = menu.mapY1 - (menu.mapY1 - menu.mapY0) * yi / (config.routeGridY - 1)
        for xi = 0, config.routeGridX - 1 do
            local x = menu.mapX0 + (menu.mapX1 - menu.mapX0) * xi / (config.routeGridX - 1)
            points[#points + 1] = { x = x, y = y }
        end
    end
    menu.routeScan = { points = points, index = 1, accum = {} }
end

local function updateRouteScan(realX, realY)
    local scan = menu.routeScan
    if not scan then return end
    local last = math.min(#scan.points, scan.index + config.routeSamplesPerUpdate - 1)
    for index = scan.index, last do
        local point = scan.points[index]
        local resolved = resolveMapPosition(point.x, point.y)
        if resolved then
            local px = (point.x - menu.mapX0) / (menu.mapX1 - menu.mapX0) * menu.rendertargetWidth
            local py = (menu.mapY1 - point.y) / (menu.mapY1 - menu.mapY0) * menu.rendertargetHeight
            local acc = scan.accum[resolved.id] or { x = 0, y = 0, count = 0 }
            acc.x, acc.y, acc.count = acc.x + px, acc.y + py, acc.count + 1
            scan.accum[resolved.id] = acc
        end
    end
    scan.index = last + 1
    if realX and realY then C.SetMapRelativeMousePosition(menu.holomap, true, realX, realY) end
    if scan.index > #scan.points then
        for id, acc in pairs(scan.accum) do
            if acc.count > 0 then menu.routeCenters[id] = { x = acc.x / acc.count, y = acc.y / acc.count } end
        end
        menu.routeScan = nil
        drawRouteStrokes()
    end
end

local function traceInput(kind, detail)
    menu.inputTraceCount = (menu.inputTraceCount or 0) + 1
    if menu.inputTraceCount <= config.inputTraceLimit then
        DebugError("[FOC][B050][MAP_INPUT] seq=" .. tostring(menu.inputTraceCount) .. " kind=" .. tostring(kind) .. " holomap=" .. tostring(menu.holomap ~= 0) .. " " .. tostring(detail or ""))
    elseif menu.inputTraceCount == config.inputTraceLimit + 1 then
        DebugError("[FOC][B050][MAP_INPUT] trace_limit=" .. tostring(config.inputTraceLimit) .. " further_input_records_suppressed=1")
    end
end

local function readMapState()
    if menu.holomap == 0 then return nil end
    local state = ffi.new("HoloMapState")
    C.GetMapState(menu.holomap, state)
    return {
        x = tonumber(state.offset.x) or 0, y = tonumber(state.offset.y) or 0, z = tonumber(state.offset.z) or 0,
        yaw = tonumber(state.offset.yaw) or 0, pitch = tonumber(state.offset.pitch) or 0, roll = tonumber(state.offset.roll) or 0,
        distance = tonumber(state.cameradistance) or 0,
    }
end

local function traceMapState(kind)
    if (menu.stateTraceCount or 0) >= config.stateTraceLimit then return end
    local current = readMapState()
    if not current then return end
    menu.stateTraceCount = (menu.stateTraceCount or 0) + 1
    local previous = menu.lastMapState or current
    DebugError(string.format(
        "[FOC][B050][MAP_STATE] seq=%d kind=%s offset=%.3f,%.3f,%.3f rotation=%.3f,%.3f,%.3f distance=%.3f delta=%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f",
        menu.stateTraceCount, tostring(kind), current.x, current.y, current.z, current.yaw, current.pitch, current.roll, current.distance,
        current.x - previous.x, current.y - previous.y, current.z - previous.z,
        current.yaw - previous.yaw, current.pitch - previous.pitch, current.roll - previous.roll, current.distance - previous.distance))
    menu.lastMapState = current
end

local function scheduleMapState(kind)
    menu.pendingStateTrace = { kind = kind, due = getElapsedTime() + 0.05 }
    startRouteScan(0.18)
end

function menu.checkCameraSettled(now)
    if menu.holomap == 0 or now < (menu.nextCameraCheck or 0) then return end
    menu.nextCameraCheck = now + 0.1
    local pose = readMapState()
    if not pose then return end
    local prior = menu.overlayCameraPose
    local changed = prior == nil
    if prior then
        for _, key in ipairs({ "x", "y", "z", "yaw", "pitch", "roll", "distance" }) do
            if pose[key] ~= prior[key] then changed = true; break end
        end
    end
    if changed then
        menu.overlayCameraPose = pose
        startRouteScan(0.35)
    end
end

local function applyMapFilters()
    if menu.holomap == 0 then return end
    C.SetMapPicking(menu.holomap, true)
    C.SetMapRenderAllGateConnections(menu.holomap, true)
    C.SetMapRenderEclipticLines(menu.holomap, true)
    C.SetMapRenderSelectionLines(menu.holomap, true)
    C.SetMapRenderAllOrderQueues(menu.holomap, false)
    C.SetMapRenderCivilianShips(menu.holomap, false)
    C.SetMapRenderTradeOffers(menu.holomap, false)
    C.SetMapRenderResourceInfo(menu.holomap, false)
end

local function selectedIntel()
    local selected = safeText(menu.hoveredSectorName or menu.selectedSectorName, "")
    for _, entry in ipairs(menu.intel or {}) do
        if type(entry) == "table" and safeText(entry.name, ""):lower() == selected:lower() then return entry end
    end
    return nil
end

local function selectedFilterEvidence()
    local sectorID = tostring(menu.hoveredSectorID or menu.selectedSectorID or "")
    local cutoff = (tonumber(menu.gameTime) or 0) - (tonumber(menu.window) or 60) * 60
    local count, redCount = 0, 0
    if menu.analysisFilter == "PIRATE ACTIVITY" then
        for _, entry in ipairs(menu.pirateObservations or {}) do
            if tostring(entry.sector) == sectorID and (tonumber(entry.time) or 0) >= cutoff then
                count = count + 1
                if entry.severity == "RED_DAMAGE" then redCount = redCount + 1 end
            end
        end
        return tostring(count) .. " PIRATE ATTACK OBSERVATION(S) | " .. tostring(redCount) .. " WITH DAMAGE"
    elseif menu.analysisFilter == "HEAVY PATROL ROUTES" then
        for _, entry in ipairs(menu.patrolTraversals or {}) do
            if (tostring(entry.from) == sectorID or tostring(entry.to) == sectorID) and (tonumber(entry.time) or 0) >= cutoff then count = count + 1 end
        end
        return tostring(count) .. " OBSERVED ENROLLED-FLEET GATE TRAVERSAL(S)"
    elseif menu.analysisFilter ~= "OVERVIEW" then
        local current, prior, affected, details = 0, 0, {}, {}
        local priorCutoff = cutoff - (tonumber(menu.window) or 60) * 60
        local accepted = {
            ["COMBAT HOTSPOTS"] = { COMBAT = true, LOSS = true },
            ["TRADE ROUTE RISK"] = { TRADE_RISK = true, CONVOY_ATTACK = true, CONVOY_LOSS = true, CONVOY_SEPARATION = true },
            ["LOGISTICS PRESSURE"] = { LOGISTICS = true, SUPPLY_BLOCKED = true, SUPPLY_FAILED = true },
            ["ECONOMIC HOTSPOTS"] = { TRADE_COMPLETE = true, PRODUCTION = true },
            ["EMPIRE TROUBLE SPOTS"] = { COMBAT = true, LOSS = true, TRADE_RISK = true, CONVOY_ATTACK = true, CONVOY_LOSS = true, LOGISTICS = true, SUPPLY_BLOCKED = true, SUPPLY_FAILED = true },
            ["HISTORICAL TRENDS"] = { COMBAT = true, LOSS = true, TRADE_RISK = true, LOGISTICS = true, TRADE_COMPLETE = true, PRODUCTION = true },
        }
        for _, entry in ipairs(menu.strategicObservations or {}) do
            local when = tonumber(entry.time) or 0
            if tostring(entry.sectorid or "") == sectorID and (accepted[menu.analysisFilter] or {})[tostring(entry.kind)] and when >= priorCutoff then
                if when >= cutoff then current = current + 1 else prior = prior + 1 end
                affected[tostring(entry.subject or "UNKNOWN")] = true
                if #details < 2 and tostring(entry.detail or "") ~= "" then details[#details + 1] = tostring(entry.detail) end
            end
        end
        local subjects = 0
        for _ in pairs(affected) do subjects = subjects + 1 end
        local direction = current > prior and "INCREASING" or current < prior and "DECREASING" or (current + prior >= 2 and "STEADY" or "INSUFFICIENT EVIDENCE")
        return tostring(current) .. " CURRENT / " .. tostring(prior) .. " PRIOR OBS | " .. tostring(subjects) .. " AFFECTED | " .. direction .. (#details > 0 and (" | " .. table.concat(details, "; ")) or "")
    end
    return "OVERVIEW | ROUTES WITHOUT FILTER EVIDENCE REMAIN NEUTRAL"
end

local function joined(values, fallback)
    local result = {}
    for index, value in ipairs(type(values) == "table" and values or {}) do
        if index > 6 then break end
        local text = clippedText(value, "", 36)
        if text ~= "" then result[#result + 1] = text end
    end
    return #result > 0 and clippedText(table.concat(result, ", "), fallback, 180) or fallback
end

local function createOverlay()
    Helper.removeAllWidgetScripts(menu, config.overlayLayer)
    menu.overlayFrame = Helper.createFrameHandle(menu, {
        layer = config.overlayLayer, standardButtons = {}, width = Helper.viewWidth,
        height = Helper.viewHeight, x = 0, y = 0,
    })

    local top = menu.overlayFrame:addTable(8, {
        tabOrder = 1, x = Helper.frameBorder, y = Helper.frameBorder,
        width = Helper.viewWidth - 2 * Helper.frameBorder, borderEnabled = false,
        maxVisibleHeight = Helper.viewHeight - 2 * Helper.frameBorder,
    })
    local row = top:addRow(true, { fixed = true })
    row[1]:setColSpan(4):createText("FOC HISTORICAL INTELLIGENCE MAP  |  BUILD 072", { font = Helper.headerFont, fontsize = Helper.standardFontSize + 3, color = cyan })
    row[5]:createText("ANALYSIS", { halign = "right", color = cyan })
    row[6]:createDropDown(filterOptions, { startOption = menu.analysisFilter }):setTextProperties({ halign = "center" })
    row[6].handlers.onDropDownActivated = function()
        menu.noupdate = true
        menu.dropdownActive = true
    end
    row[6].handlers.onDropDownConfirmed = function(_, id)
        menu.noupdate = false
        menu.dropdownActive = false
        menu.analysisFilter = tostring(id or "OVERVIEW")
        menu.notice = menu.analysisFilter .. " FILTER ACTIVE | COLORS ARE FOC ANALYSIS, NOT FACTION OWNERSHIP"
        startRouteScan(0.05)
        menu.refreshOverlay = true
    end
    row[6].handlers.onDropDownDeactivated = function()
        menu.noupdate = false
        menu.dropdownActive = false
    end
    row[7]:createButton({ active = menu.holomap ~= 0 }):setText("RESET VIEW", { halign = "center" })
    row[7].handlers.onClick = function()
        if menu.holomap ~= 0 then
            local startpos = ffi.new("UIPosRot")
            C.ClearSelectedMapComponents(menu.holomap)
            C.ShowUniverseMap2(menu.holomap, true, false, false, 0, startpos)
            C.SetMapFocus(menu.holomap, false)
            applyMapFilters()
            menu.selectedSectorName = nil
            menu.selectedSectorID = nil
            menu.hoveredSectorName = nil
            menu.hoveredSectorID = nil
            menu.notice = "MAP VIEW RESET TO THE DISCOVERED UNIVERSE"
            scheduleMapState("RESET")
            startRouteScan(0.2)
            menu.refreshOverlay = true
        end
    end
    row[8]:createButton({ active = true }):setText("BACK TO FOC", { halign = "center" })
    row[8].handlers.onClick = function() menu.onCloseElement("back") end

    local panelWidth = math.floor(Helper.viewWidth * 0.30)
    local panelY = Helper.scaleY(96)
    local panel = menu.overlayFrame:addTable(2, {
        tabOrder = 2, x = Helper.viewWidth - panelWidth - Helper.frameBorder, y = panelY,
        width = panelWidth, borderEnabled = true, reserveScrollBar = false,
        maxVisibleHeight = Helper.viewHeight - panelY - Helper.frameBorder,
    })
    panel:setColWidth(1, math.floor(panelWidth * 0.34), false)
    local intel = selectedIntel()
    local score = intel and (tonumber(intel.score) or 0) or 0
    local level = score >= 10 and "CRITICAL" or score >= 4 and "HIGH" or score > 0 and "ELEVATED" or "QUIET"
    local riskColor = score >= 10 and red or score > 0 and amber or green

    local prow = panel:addRow(true, { fixed = true })
    if menu.request then
        prow[1]:setColSpan(2):createText("MARK LOCATION | " .. safeText(menu.request.kind, "FOC REQUEST"), { font = Helper.headerFont, color = amber, halign = "center" })
    else
        prow[1]:setColSpan(2):createButton({active=true}):setText("HOTSPOTS / FLEET TEMPLATES", {halign="center"})
        prow[1].handlers.onClick=function()
            if not menu.overlayFrame or menu.request then return end
            for _,parent in ipairs(Menus or {}) do if parent.name=="FOC_Menu" and parent.openAdvisorFromMap then parent.openAdvisorFromMap(menu); return end end
        end
    end
    prow = panel:addRow(false, { fixed = true })
    prow[1]:setColSpan(2):createText(safeText(menu.hoveredSectorName or menu.selectedSectorName, "MOVE OVER A KNOWN SECTOR CELL"), { color = intel and riskColor or neutral, halign = "center" })
    prow = panel:addRow(false, { fixed = true })
    prow[1]:createText("FILTER")
    prow[2]:createText(menu.analysisFilter, { color = cyan })
    prow = panel:addRow(false, { fixed = true })
    prow[1]:createText("FILTER EVIDENCE")
    prow[2]:createText(selectedFilterEvidence(), { color = menu.analysisFilter == "OVERVIEW" and neutral or amber, wordwrap = true })
    prow = panel:addRow(false, { fixed = true })
    prow[1]:createText("BASE FOC RISK")
    prow[2]:createText(intel and (level .. " | SCORE " .. tostring(score)) or "NO FOC SECTOR EVIDENCE", { color = intel and riskColor or neutral })
    prow = panel:addRow(false, { fixed = true })
    prow[1]:setColSpan(2):createText("FILTER COLORS MARK EVIDENCE ROUTES AND SECTORS; THEY DO NOT REUSE FACTION COLORS", { color = menu.analysisFilter == "OVERVIEW" and neutral or amber, wordwrap = true })
    prow = panel:addRow(false, { fixed = true })
    prow[1]:createText("FLEET PRESENCE")
    prow[2]:createText(intel and joined(intel.fleets, "NONE OBSERVED") or "UNKNOWN", { color = intel and cyan or neutral, wordwrap = true })
    prow = panel:addRow(false, { fixed = true })
    prow[1]:createText("SAVED HOMES")
    prow[2]:createText(intel and joined(intel.homes, "NONE SAVED") or "UNKNOWN", { color = intel and green or neutral, wordwrap = true })
    prow = panel:addRow(false, { fixed = true })
    prow[1]:createText("READINESS")
    prow[2]:createText(intel and (tostring(tonumber(intel.critical) or 0) .. " CRITICAL | " .. tostring(tonumber(intel.degraded) or 0) .. " DEGRADED") or "UNKNOWN", { color = intel and riskColor or neutral })
    prow = panel:addRow(false, { fixed = true })
    prow[1]:createText("UNLOCATED")
    prow[2]:createText(tostring(menu.unlocated or 0) .. " THREAT OBSERVATION(S) NOT FABRICATED", { color = (menu.unlocated or 0) > 0 and amber or green, wordwrap = true })
    if intel then
        for index = 1, math.min(config.maxObservationRows, #(intel.events or {})) do
            local event = intel.events[index]
            prow = panel:addRow(false, { fixed = true })
            prow[1]:setColSpan(2):createText(tostring(index) .. ". " .. clippedText(event.kind, "ACTIVITY", 24) .. " | " .. clippedText(event.state, "RECORDED", 30) .. " | " .. clippedText(event.subject, "FOC", 40) .. "\n" .. clippedText(event.detail, "No detail recorded.", 120), { color = event.severity == "RED_DAMAGE" and red or amber, wordwrap = true })
        end
    end
    prow = panel:addRow(false, { fixed = true })
    prow[1]:setColSpan(2):createText("PLAYER-DISCOVERED SPACE ONLY | CIVILIAN SHIPS, ORDER QUEUES, TRADE, AND RESOURCE OVERLAYS HIDDEN", { color = green, wordwrap = true })
    prow = panel:addRow(false, { fixed = true })
    prow[1]:setColSpan(2):createText(menu.notice, { color = cyan, halign = "center", wordwrap = true })
    menu.overlayFrame:display()
end

local function createMapFrame()
    Helper.removeAllWidgetScripts(menu, config.mapLayer)
    menu.mapFrame = Helper.createFrameHandle(menu, {
        layer = config.mapLayer, standardButtons = { back = true, close = true },
        width = Helper.viewWidth, height = Helper.viewHeight, x = 0, y = 0,
    })
    menu.rendertargetWidth = Helper.viewWidth
    menu.rendertargetHeight = Helper.viewHeight
    menu.mapFrame:addRenderTarget({ width = menu.rendertargetWidth, height = menu.rendertargetHeight, x = 0, y = 0, scaling = false, alpha = 100, clear = false })
    menu.mapFrame:display()
end

function menu.cleanup()
    menu.overlayCameraPose, menu.nextCameraCheck = nil, nil
    hideRouteRects()
    menu.cleanupCount = (menu.cleanupCount or 0) + 1
    if menu.holomap ~= 0 and menu.panningmap then C.StopPanMap(menu.holomap) end
    if menu.holomap ~= 0 and menu.rotatingmap then C.StopRotateMap(menu.holomap) end
    if menu.holomap ~= 0 then C.RemoveHoloMap() end
    menu.holomap = 0
    menu.map = nil
    menu.activatemap = nil
    menu.leftdown = nil
    menu.rightdown = nil
    menu.panningmap = nil
    menu.rotatingmap = nil
    menu.pendingStateTrace = nil
    menu.routeScan = nil
    menu.routeDirtyAt = nil
    menu.routeCenters = {}
    menu.lastMapState = nil
    menu.noupdate = false
    menu.dropdownActive = false
    DebugError("[FOC][B050][MAP_CLEANUP] count=" .. tostring(menu.cleanupCount) .. " holomap=0 route_rects=0")
end

function menu.onShowMenu()
    menu.overlayCameraPose, menu.nextCameraCheck = nil, nil
    menu.param = menu.param or {}
    menu.param[1] = tonumber(menu.param[1]) or 0
    menu.param[2] = tonumber(menu.param[2]) or 0
    menu.intel = type(menu.param[3]) == "table" and menu.param[3] or {}
    menu.unlocated = tonumber(menu.param[4]) or 0
    menu.window = tonumber(menu.param[5]) or 60
    menu.request = type(menu.param[6]) == "table" and menu.param[6] or nil
    menu.pirateObservations = type(menu.param[7]) == "table" and menu.param[7] or {}
    menu.patrolTraversals = type(menu.param[8]) == "table" and menu.param[8] or {}
    menu.gateEdges = type(menu.param[9]) == "table" and menu.param[9] or {}
    menu.gameTime = tonumber(menu.param[10]) or 0
    menu.strategicObservations = type(menu.param[11]) == "table" and menu.param[11] or {}
    menu.analysisFilter = "OVERVIEW"
    menu.selectedSectorName = nil
    menu.selectedSectorID = nil
    menu.hoveredSectorName = nil
    menu.hoveredSectorID = nil
    menu.hoverCandidate = nil
    menu.hoverCandidateAt = 0
    menu.nextHoverAt = 0
    menu.routeCenters = {}
    menu.routeRects = {}
    menu.routeScan = nil
    menu.routeDirtyAt = nil
    menu.inputTraceCount = 0
    menu.stateTraceCount = 0
    menu.cleanupCount = 0
    menu.closeInProgress = false
    menu.dropdownActive = false
    menu.notice = menu.request and "MARK MODE | CLICK THE EXACT POINT | DRAG PANS | ESCAPE CANCELS | NO ORDER IS SENT" or "MOVE OVER A CELL FOR INTELLIGENCE | DRAG TO PAN | RIGHT-DRAG TO ROTATE | WHEEL TO ZOOM"
    DebugError("[FOC][B050][MAP_OPEN] helper_slots=" .. tostring(menu.param[1]) .. "," .. tostring(menu.param[2]) .. " intel=" .. tostring(#menu.intel) .. " pirate=" .. tostring(#menu.pirateObservations) .. " patrol=" .. tostring(#menu.patrolTraversals) .. " edges=" .. tostring(#menu.gateEdges) .. " request=" .. tostring(menu.request and menu.request.kind or "NONE") .. " unlocated=" .. tostring(menu.unlocated) .. " window=" .. tostring(menu.window))
    createMapFrame()
    createOverlay()
end

local function updateHover(curtime, x, y)
    if menu.holomap == 0 or menu.panningmap or menu.rotatingmap or menu.routeScan or menu.dropdownActive or curtime < (menu.nextHoverAt or 0) then return end
    menu.nextHoverAt = curtime + config.hoverInterval
    local resolved = resolveMapPosition(x, y)
    local candidate = resolved and resolved.id or ""
    if candidate ~= tostring(menu.hoverCandidate or "") then
        menu.hoverCandidate = candidate
        menu.hoverCandidateName = resolved and resolved.name or nil
        menu.hoverCandidateAt = curtime
        return
    end
    if curtime - (menu.hoverCandidateAt or curtime) < config.hoverDebounce then return end
    local newID = candidate ~= "" and candidate or nil
    if tostring(menu.hoveredSectorID or "") ~= tostring(newID or "") then
        menu.hoveredSectorID = newID
        menu.hoveredSectorName = newID and menu.hoverCandidateName or nil
        if menu.hoveredSectorName then
            menu.notice = "HOVER " .. menu.hoveredSectorName .. " | " .. menu.analysisFilter .. " INTELLIGENCE"
        elseif not menu.request then
            menu.notice = "NO KNOWN SECTOR CELL UNDER POINTER"
        end
        menu.refreshOverlay = true
        DebugError("[FOC][B050][MAP_HOVER] sector=" .. tostring(menu.hoveredSectorName or "NONE") .. " filter=" .. menu.analysisFilter .. " overlay_refresh=1")
    end
end

menu.updateInterval = 0.01
function menu.onUpdate()
    local curtime = getElapsedTime()
    if menu.mapFrame then menu.mapFrame:update() end
    if menu.overlayFrame then menu.overlayFrame:update() end
    local mouseX, mouseY
    if menu.map and menu.holomap ~= 0 then
        mouseX, mouseY = GetRenderTargetMousePosition(menu.map)
        C.SetMapRelativeMousePosition(menu.holomap, (mouseX and mouseY) ~= nil, mouseX or 0, mouseY or 0)
    end
    if menu.activatemap then
        local x0, x1, y0, y1 = Helper.getRelativeRenderTargetSize(menu, config.mapLayer, menu.map)
        local texture = GetRenderTargetTexture(menu.map)
        if texture then
            menu.mapX0, menu.mapX1, menu.mapY0, menu.mapY1 = x0, x1, y0, y1
            menu.holomap = C.AddHoloMap(texture, x0, x1, y0, y1, menu.rendertargetWidth / menu.rendertargetHeight, 1)
            C.SetMapFocus(menu.holomap, false)
            if menu.holomap ~= 0 then
                local startpos = ffi.new("UIPosRot")
                C.ClearSelectedMapComponents(menu.holomap)
                C.ShowUniverseMap2(menu.holomap, true, false, false, 0, startpos)
                applyMapFilters()
                menu.notice = "MAP READY | NATIVE INPUT FOCUS INITIALIZED"
                DebugError("[FOC][B050][MAP_READY] holomap=1 focus_initialized=1 focus_value=false picking=1 civilian=0 orders=0 trade=0 resources=0 hover=ecliptic route_overlay=owned_rects")
                traceMapState("READY")
                startRouteScan(0.2)
                menu.refreshOverlay = true
            else
                DebugError("[FOC][B050][MAP_CREATE_FAILED] holomap=0")
            end
            menu.activatemap = false
        end
    end
    if menu.panningmap and menu.panningmap.isclick and menu.leftdown then
        local offset = table.pack(GetLocalMousePosition())
        if (menu.leftdown.time + 0.5 < curtime) or Helper.comparePositions(menu.leftdown.position, offset, 5) then menu.panningmap.isclick = false end
    end
    if menu.leftdown then
        local offset = table.pack(GetLocalMousePosition())
        if not menu.leftdown.wasmoved and Helper.comparePositions(menu.leftdown.position, offset, 5) then menu.leftdown.wasmoved = true end
        if menu.leftdown.wasmoved and menu.leftdown.time + 0.1 < curtime and menu.panningmap then menu.leftdown.dynpos = offset end
    end
    if menu.rightdown then
        local offset = table.pack(GetLocalMousePosition())
        if not menu.rightdown.wasmoved and Helper.comparePositions(menu.rightdown.position, offset, 5) then menu.rightdown.wasmoved = true end
        if menu.rightdown.wasmoved and menu.rightdown.time + 0.1 < curtime and menu.rotatingmap then menu.rightdown.dynpos = offset end
    end
    if menu.pendingStateTrace and menu.pendingStateTrace.due <= curtime then
        local kind = menu.pendingStateTrace.kind
        menu.pendingStateTrace = nil
        traceMapState(kind)
    end
    menu.checkCameraSettled(curtime)
    if menu.routeDirtyAt and menu.routeDirtyAt <= curtime and not menu.panningmap and not menu.rotatingmap and not menu.dropdownActive then
        menu.routeDirtyAt = nil
        beginRouteScan()
    end
    updateRouteScan(mouseX, mouseY)
    updateHover(curtime, mouseX, mouseY)
    if menu.refreshOverlay and not menu.dropdownActive then
        menu.refreshOverlay = nil
        createOverlay()
    end
end

function menu.viewCreated(layer, ...)
    if layer == config.mapLayer then
        menu.map = ...
        menu.activatemap = true
        DebugError("[FOC][B050][MAP_VIEW_CREATED] layer=" .. tostring(layer) .. " rendertarget=" .. tostring(menu.map ~= nil))
    end
end

local function menuByName(name)
    for _, entry in ipairs(Menus or {}) do if entry.name == name then return entry end end
    return nil
end

function menu.onRenderTargetSelect()
    traceInput("LEFT_CLICK", "leftdown=" .. tostring(menu.leftdown ~= nil))
    if menu.holomap == 0 then menu.leftdown = nil; return end
    local offset = table.pack(GetLocalMousePosition())
    if (not menu.leftdown) or ((menu.leftdown.time + 0.5 > getElapsedTime()) and not Helper.comparePositions(menu.leftdown.position, offset, 5)) then
        local x, y = GetRenderTargetMousePosition(menu.map)
        local resolved = resolveMapPosition(x, y)
        if menu.request and menu.request.kind == "ASSAULT_TARGET" then
            local picked = safeComponent64(C.GetPickedMapComponent(menu.holomap))
            local parent = menuByName("FOC_Menu")
            local isobject = picked and C.IsComponentClass(picked, "object")
            local isplayerowned = false
            if picked then
                local luaok, luaid = pcall(ConvertStringToLuaID, tostring(picked))
                if luaok and luaid then
                    local dataok, owned = pcall(GetComponentData, luaid, "isplayerowned")
                    isplayerowned = dataok and owned == true
                end
            end
            local pickedname = picked and componentName(picked) or nil
            if picked and isobject and not isplayerowned and pickedname and parent and parent.operationsMapTargetSelected then
                DebugError("[FOC][B056][MAP_TARGET] component=" .. tostring(picked) .. " name=" .. pickedname .. " known_pick=1 player_owned=0 callback=FOC_Menu")
                menu.leftdown = nil
                parent.operationsMapTargetSelected(menu, menu.request, { tostring(picked), pickedname })
                return
            end
            menu.notice = "TARGET NOT MARKED - CLICK A KNOWN NON-PLAYER OBJECT ICON"
            DebugError("[FOC][B056][MAP_TARGET_BLOCKED] picked=" .. tostring(picked or 0) .. " object=" .. tostring(isobject == true) .. " player_owned=" .. tostring(isplayerowned))
        elseif resolved and menu.request then
            local parent = menuByName("FOC_Menu")
            if parent and parent.operationsMapLocationSelected then
                DebugError("[FOC][B050][MAP_MARK] kind=" .. tostring(menu.request.kind or "UNKNOWN") .. " sector=" .. resolved.name .. " position=" .. tostring(resolved.position[1]) .. "," .. tostring(resolved.position[2]) .. "," .. tostring(resolved.position[3]) .. " callback=FOC_Menu mutation=REQUEST_SCOPED")
                menu.leftdown = nil
                parent.operationsMapLocationSelected(menu, menu.request, { resolved.sector, resolved.position })
                return
            end
            menu.notice = "LOCATION NOT MARKED - FOC RETURN HANDLER IS UNAVAILABLE"
            DebugError("[FOC][B050][MAP_MARK_BLOCKED] reason=PARENT_HANDLER_UNAVAILABLE mutation=NONE")
        elseif resolved then
            menu.selectedSectorName = resolved.name
            menu.selectedSectorID = resolved.id
            C.SetSelectedMapComponent(menu.holomap, resolved.sector)
            menu.notice = "SELECTED " .. resolved.name .. " | FOC INTELLIGENCE UPDATED"
            DebugError("[FOC][B050][MAP_SELECTION] source=ECLIPTIC_CELL sector_valid=1 known=1 sector=" .. resolved.name .. " overlay_refresh=1")
        else
            C.ClearSelectedMapComponents(menu.holomap)
            menu.selectedSectorName = nil
            menu.selectedSectorID = nil
            menu.notice = "NO KNOWN SECTOR RESOLVED AT THIS POSITION"
            DebugError("[FOC][B050][MAP_SELECTION] source=ECLIPTIC_CELL sector_valid=0 known=0 overlay_refresh=1")
        end
        menu.refreshOverlay = true
    end
    menu.leftdown = nil
end

function menu.onRenderTargetMouseDown(modified)
    traceInput("LEFT_DOWN", "modified=" .. tostring(modified or "NONE"))
    if menu.holomap == 0 then return end
    local position = table.pack(GetLocalMousePosition())
    menu.leftdown = { time = getElapsedTime(), position = position, dynpos = position }
    if modified ~= "shift" then
        C.StartPanMap(menu.holomap)
        menu.panningmap = { isclick = true }
        menu.noupdate = true
    end
end

function menu.onRenderTargetMouseUp()
    traceInput("LEFT_UP", "panning=" .. tostring(menu.panningmap ~= nil))
    if menu.holomap ~= 0 and menu.panningmap then
        C.StopPanMap(menu.holomap)
        scheduleMapState("PAN_END")
    end
    menu.panningmap = nil
    menu.noupdate = false
end

function menu.onRenderTargetRightMouseDown()
    traceInput("RIGHT_DOWN")
    if menu.holomap == 0 then return end
    local position = table.pack(GetLocalMousePosition())
    menu.rightdown = { time = getElapsedTime(), position = position, dynpos = position }
    C.StartRotateMap(menu.holomap)
    menu.rotatingmap = true
    menu.noupdate = true
end

function menu.onRenderTargetRightMouseUp()
    traceInput("RIGHT_UP", "rotating=" .. tostring(menu.rotatingmap ~= nil))
    if menu.holomap ~= 0 and menu.rotatingmap then
        C.StopRotateMap(menu.holomap)
        scheduleMapState("ROTATE_END")
    end
    menu.rightdown = nil
    menu.rotatingmap = nil
    menu.noupdate = false
end

function menu.onRenderTargetCombinedScrollDown(step)
    local amount = tonumber(step) or 1
    traceInput("WHEEL_DOWN", "step=" .. tostring(amount))
    if menu.holomap ~= 0 then C.ZoomMap(menu.holomap, amount); scheduleMapState("WHEEL_DOWN") end
end

function menu.onRenderTargetCombinedScrollUp(step)
    local amount = tonumber(step) or 1
    traceInput("WHEEL_UP", "step=" .. tostring(amount))
    if menu.holomap ~= 0 then C.ZoomMap(menu.holomap, -amount); scheduleMapState("WHEEL_UP") end
end

function menu.onCloseElement(reason, layer)
    if ((layer == nil) or layer == config.mapLayer or layer == config.overlayLayer) and not menu.closeInProgress then
        menu.closeInProgress = true
        DebugError("[FOC][B050][MAP_CLOSE] reason=" .. tostring(reason or "close") .. " layer=" .. tostring(layer or "NONE") .. " input_records=" .. tostring(math.min(menu.inputTraceCount or 0, config.inputTraceLimit)) .. " state_records=" .. tostring(menu.stateTraceCount or 0))
        Helper.closeMenu(menu, reason or "close")
        menu.cleanup()
    end
end

function menu.onRowChanged() end
function menu.onSelectElement() end

local function init()
    Menus = Menus or {}
    for _, entry in ipairs(Menus) do if entry.name == menu.name then return end end
    table.insert(Menus, menu)
    Helper.registerMenu(menu)
end

init()
