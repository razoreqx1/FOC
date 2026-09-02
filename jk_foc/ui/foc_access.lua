-- Fleet Operations Command standalone access adapter.
-- Registers on at most one active DockedMenu owner plus one final reconciliation.
-- It never scans fleets, mutates ships, or owns persistent game state.

local access = {
    callbackID = "foc_b002_standalone_access",
    menu = nil,
    registeredMenus = {},
    attempts = 0,
    maxAttempts = 30,
    finalReconcileScheduled = false,
}

local function signalFOC()
    DebugError("[FOC][B025][ACCESS] stage=OPEN_EVENT_RAISED")
    AddUITriggeredEvent("FOC_Access", "open", nil)
end

local function openFOC()
    if access.menu and type(access.menu.onCloseElement) == "function" then
        access.menu.onCloseElement("close")
    elseif access.menu and Helper and type(Helper.closeMenu) == "function" then
        Helper.closeMenu(access.menu, "close")
    end
    if Helper and type(Helper.addDelayedOneTimeCallbackOnUpdate) == "function" then
        Helper.addDelayedOneTimeCallbackOnUpdate(signalFOC, true, getElapsedTime() + 0.1)
    else
        signalFOC()
    end
end

local function addFOCAction(tableHeader)
    local row = tableHeader:addRow(true, { fixed = true })
    row[1]:setColSpan(11):createButton({
        helpOverlayID = "foc_open",
        helpOverlayText = " ",
        helpOverlayHighlightOnly = true,
        uiTriggerID = "foc_open",
    }):setText("OPEN FLEET OPERATIONS COMMAND", { halign = "center" })
    row[1].handlers.onClick = openFOC
end

local function registerOnMenu(targetMenu, owner)
    if not targetMenu then return false end
    if access.registeredMenus[targetMenu] then
        access.menu = targetMenu
        return true
    end
    if type(targetMenu.registerCallback) ~= "function" then return false end
    targetMenu.registerCallback("display_on_after_main_interactions", addFOCAction, access.callbackID)
    access.registeredMenus[targetMenu] = true
    access.menu = targetMenu
    DebugError("[FOC][B025][ACCESS] stage=CALLBACK_REGISTERED owner=" .. tostring(owner) .. " attempts=" .. tostring(access.attempts + 1))
    return true
end

local function reconcileFinalOwner()
    local finalMenu = Helper.getMenu("DockedMenu")
    local registered = registerOnMenu(finalMenu, "FINAL_ACTIVE_MENU")
    DebugError("[FOC][B025][ACCESS] stage=FINAL_RECONCILE registered=" .. tostring(registered) .. " recurring_watchdog=0")
end

local function scheduleFinalReconcile()
    if access.finalReconcileScheduled then return end
    access.finalReconcileScheduled = true
    if Helper and type(Helper.addDelayedOneTimeCallbackOnUpdate) == "function" then
        Helper.addDelayedOneTimeCallbackOnUpdate(reconcileFinalOwner, true, getElapsedTime())
    else
        reconcileFinalOwner()
    end
end

local function init()
    local activeMenu = Helper.getMenu("DockedMenu")
    if registerOnMenu(activeMenu, "INITIAL_ACTIVE_MENU") then
        scheduleFinalReconcile()
        return
    end
    access.attempts = access.attempts + 1
    if access.attempts < access.maxAttempts and Helper and type(Helper.addDelayedOneTimeCallbackOnUpdate) == "function" then
        Helper.addDelayedOneTimeCallbackOnUpdate(init, true, getElapsedTime() + 1)
    else
        DebugError("[FOC][B025][ACCESS_BLOCKED] DockedMenu callback unavailable; retries=" .. tostring(access.attempts))
    end
end

init()
