-- B060: exact MD-owned order preview. This module never changes native orders.
local P = { mode = 'SAVED', rows = {}, token = 0, request = 0, message = 'Preview to see exactly which orders will be sent.' }
FOC_Plan = P
function P.changed() if P.onChange then P.onChange() end end
function P.preview()
    if P.pending then return end
    P.started = getElapsedTime()
    P.request = P.request + 1
    P.operation, P.wire, P.incoming = 'preview', nil, nil
    P.token, P.pending = 0, true
    P.message = 'Reading saved FOC fleets and their current orders...'
    AddUITriggeredEvent('FOC_Menu', 'order_preview', { P.mode, P.request })
end
function P.apply()
    if P.pending or P.token <= 0 then return end
    local token = P.token
    P.started = getElapsedTime()
    P.request = P.request + 1
    P.operation, P.wire, P.incoming = 'apply', nil, nil
    P.token, P.pending = 0, true
    P.message = 'Sending only the reviewed orders; waiting for individual results...'
    AddUITriggeredEvent('FOC_Menu', 'order_apply', { token, P.request })
end
function P.begin(_, value)
    if type(value) ~= 'table' then P.incoming = nil; return end
    local token, count = tonumber(value[1]), tonumber(value[2])
    if not token or token < 0 or token % 1 ~= 0 or not count or count < 0 or count > 100 or count % 1 ~= 0 then P.incoming = nil; return end
    P.incoming = { token = token, count = count, message = tostring(value[3] or ''), rows = {}, ids = {} }
end
function P.row(_, value)
    local incoming = P.incoming
    if not incoming or type(value) ~= 'table' then return end
    local id = tostring(value[1] or '')
    if id == '' or incoming.ids[id] or #incoming.rows >= incoming.count then incoming.bad = true; return end
    local row = {}
    for i = 1, 6 do if type(value[i]) ~= 'string' then incoming.bad = true; return end; row[i] = value[i] end
    incoming.ids[id] = true
    incoming.rows[#incoming.rows + 1] = row
end
function P.complete(_, token)
    local incoming = P.incoming
    P.incoming, P.pending, P.token, P.started = nil, false, 0, nil
    P.wire = nil
    if not incoming or incoming.bad or incoming.token ~= tonumber(token) or #incoming.rows ~= incoming.count then
        P.message = 'Incomplete preview received. Previous rows retained; preview again before sending.'
    else
        P.rows, P.token, P.message = incoming.rows, incoming.token, incoming.message
    end
    P.changed()
end
function P.rejected(_, message)
    P.token, P.pending, P.message, P.started = 0, false, tostring(message), nil
    P.wire, P.incoming = nil, nil
    P.changed()
end
function P.tick()
    if P.started and getElapsedTime() - P.started > 20 then
        P.rejected(nil, 'Readback timed out. Check Activity for any sent orders, then preview again. No automatic retry.')
    end
end
-- Scalar wire adapter; the validated row routine never sees raw native objects.
RegisterEvent('FOC_Plan.request', function(_, request)
    P.wireRequest = tonumber(request)
end)
RegisterEvent('FOC_Plan.begin', function(_, token)
    if P.pending and P.wire and P.wireRequest == P.request then
        P.wire.bad = true
        if P.incoming then P.incoming.bad = true end
        return
    end
    P.wire = nil
    P.incoming = nil
    if not P.pending or P.wireRequest ~= P.request then return end
    if P.operation == 'apply' and tonumber(token) ~= 0 then return end
    P.wire = { token = tonumber(token) }
end)
RegisterEvent('FOC_Plan.count', function(_, count)
    if P.wire then
        if P.wire.countSeen or P.wire.messageSeen then P.wire.bad = true end
        P.wire.countSeen = true
        P.wire.count = tonumber(count)
    end
end)
RegisterEvent('FOC_Plan.message', function(_, message)
    if P.wire then
        if P.wire.messageSeen or not P.wire.countSeen then P.wire.bad = true; return end
        P.wire.messageSeen = true
        P.begin(nil, { P.wire.token, P.wire.count, message })
    end
end)
RegisterEvent('FOC_Plan.rowbegin', function()
    if P.wire then
        if P.wire.row and P.incoming then P.incoming.bad = true end
        P.wire.row = {}
    end
end)
for i, field in ipairs({ 'id', 'name', 'wanted', 'home', 'reason', 'oldorder' }) do
    local index = i
    RegisterEvent('FOC_Plan.' .. field, function(_, value)
        if P.wire and P.wire.row then
            if P.wire.row[index] ~= nil and P.incoming then P.incoming.bad = true end
            P.wire.row[index] = value
        end
    end)
end
RegisterEvent('FOC_Plan.rowcommit', function()
    if P.wire then
        if not P.wire.row and P.incoming then P.incoming.bad = true end
        P.row(nil, P.wire.row); P.wire.row = nil
    end
end)
RegisterEvent('FOC_Plan.complete', function(_, token)
    if not P.pending or not P.wire or P.wireRequest ~= P.request then return end
    if (P.wire.row or P.wire.bad) and P.incoming then P.incoming.bad = true end
    P.complete(nil, token)
end)
RegisterEvent('FOC_Plan.rejected', P.rejected)
function P.draw(w, text, action, dropdown, pager, good, warning, normal, allowed)
    local modes = { 'USE EACH FLEET\'S SAVED ORDER', 'ALL FLEETS: PATROL THEIR HOME SECTOR', 'ALL FLEETS: GUARD THEIR HOME POINT' }
    local values = { 'SAVED', 'PATROL', 'GUARD HOME' }
    local selected = 1
    for i, value in ipairs(values) do if value == P.mode then selected = i end end
    dropdown(w, 'Orders to preview', modes, modes[selected], function(value)
        if P.pending then return end
        for i, label in ipairs(modes) do if label == value then P.mode = values[i] end end
        P.token = 0
        P.rows = {}
        P.message = 'Order choice changed. Preview again; no orders sent.'
    end)
    text(w, 'Who is included?', 'All saved FOC fleets, not every owned ship. Each fleet keeps its own Home. Locked, busy or protected fleets are left alone. This does not change saved doctrine.', normal)
    local ready, blocked = 0, 0
    for _, row in ipairs(P.rows) do if row[5] == 'READY' then ready = ready + 1 elseif row[5] ~= 'ACTIVE' then blocked = blocked + 1 end end
    text(w, 'Result', P.message, not P.pending and #P.rows > 0 and blocked == 0 and good or warning)
    action(w, 'Step 1', 'PREVIEW FLEET ORDERS - NOTHING WILL MOVE', P.preview, not P.pending, normal)
    action(w, 'Step 2', 'SEND THE ' .. tostring(ready) .. ' REVIEWED FLEET ORDERS', P.apply, allowed and not P.pending and P.token > 0 and ready > 0, warning)
    local first, last = pager(w, 'order.preview', #P.rows, { fixedRows = 32, rowUnits = 6, maximum = 4 })
    for i = first, last do
        local row = P.rows[i]
        text(w, string.sub(row[2], 1, 36) .. ' [' .. row[1] .. ']', (row[3] == 'Patrol' and 'Patrol sector: ' or 'Guard Home point: ') .. string.sub(row[4], 1, 100), normal)
        text(w, 'Current order', string.sub(row[6], 1, 100), normal)
        text(w, 'Will this fleet move?', row[5] == 'READY' and 'YES - on your approval' or row[5], (row[5] == 'READY' or row[5] == 'ACTIVE') and good or warning)
    end
end
