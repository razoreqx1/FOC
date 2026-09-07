-- FOC B057: background evidence adapter. MD owns policy, jobs and all mutations.
-- No update callback, menu-open cache, money transfer or equipment write here.
local ffi = require('ffi')
local C = ffi.C
FOCRecovery = { policy = { repair = nil, shelter = nil }, snapshots = {} }
local R = FOCRecovery

function R.finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

function R.id(value)
    if value == nil then return nil end
    local raw = tostring(value):gsub('ULL$', ''):gsub('LL$', '')
    if not raw:match('^%d+$') or not raw:find('[1-9]') then return nil end
    local ok, component = pcall(ConvertStringTo64Bit, raw)
    if not ok or component == nil or component == 0 then return nil end
    local valid, exists = pcall(IsValidComponent, component)
    if not valid or not exists then return nil end
    return component, raw
end

function R.encode(value)
    local kind = type(value)
    if kind == 'boolean' then return value and 'T' or 'F' end
    if kind == 'number' then
        assert(R.finite(value), 'nonfinite native evidence')
        return 'N' .. string.format('%.17g', value)
    end
    if kind == 'string' then return 'S' .. #value .. ':' .. value end
    assert(kind == 'table', 'incomplete native evidence')
    local keys, result = {}, {}
    for key in pairs(value) do
        assert(type(key) == 'string', 'snapshot key must be stable text')
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        result[#result + 1] = R.encode(key) .. R.encode(value[key])
    end
    return '{' .. table.concat(result) .. '}'
end

function R.count(value)
    local n = tonumber(value)
    assert(R.finite(n) and n >= 0 and n <= 2048 and n == math.floor(n), 'native enumeration exceeds bound')
    return n
end

function R.mod(kind, component, context, group, grouped)
    local present, values = Helper.getInstalledModInfo(kind, component, context, group, grouped)
    assert(type(present) == 'boolean' and type(values) == 'table', 'modification readback unavailable')
    return { present = present, values = values }
end

function R.modifications(ship)
    local result = { ship = R.mod('ship', ship), engine = R.mod('engine', ship) }
    -- Native mod menu uses the ship for engine mods, individual components for weapons.
    for _, kind in ipairs({ 'weapon', 'turret' }) do
        local n = R.count(C.GetNumUpgradeSlots(ship, '', kind))
        result[kind .. ':count'] = n
        for index = 1, n do
            local raw = C.GetUpgradeSlotCurrentComponent(ship, kind, index)
            if raw ~= 0 then
                local component, key = R.id(raw)
                assert(component, 'installed component disappeared')
                result[kind .. ':' .. index] = { id = key, mod = R.mod(kind, component) }
            else
                result[kind .. ':' .. index] = false
            end
        end
    end
    local n = R.count(C.GetNumShieldGroups(ship))
    local shields = ffi.new('ShieldGroup[?]', math.max(1, n))
    local actual = R.count(C.GetShieldGroups(shields, n, ship))
    assert(actual == n, 'shield enumeration changed')
    for index = 0, actual - 1 do
        local context, key = R.id(shields[index].context)
        assert(context, 'shield context unavailable')
        local group = ffi.string(shields[index].group)
        local identity = 'shield:' .. R.encode(key) .. R.encode(group)
        assert(result[identity] == nil, 'duplicate shield group')
        result[identity] = R.mod('shield', ship, context, group)
    end
    n = R.count(C.GetNumUpgradeGroups(ship, ''))
    local groups = ffi.new('UpgradeGroup2[?]', math.max(1, n))
    actual = R.count(C.GetUpgradeGroups2(groups, n, ship, ''))
    assert(actual == n, 'upgrade group enumeration changed')
    for index = 0, actual - 1 do
        local path, group = ffi.string(groups[index].path), ffi.string(groups[index].group)
        if path ~= '..' or group ~= '' then
            local context, key = R.id(groups[index].contextid)
            assert(context, 'turret context unavailable')
            local info = C.GetUpgradeGroupInfo2(ship, '', context, path, group, 'turret')
            if R.count(info.count) > 0 then
                local identity = 'turretgroup:' .. R.encode(key) .. R.encode(group)
                assert(result[identity] == nil, 'duplicate turret group')
                result[identity] = R.mod('turret', ship, context, group, true)
            end
        end
    end
    local paint = ffi.new('UIPaintMod')
    local present = C.GetInstalledPaintMod(ship, paint)
    assert(type(present) == 'boolean', 'paint readback unavailable')
    result.paint = present and { ware = ffi.string(paint.Ware), quality = tonumber(paint.Quality) } or false
    return R.encode(result)
end

function R.damage(ship)
    local n = R.count(C.GetNumSubComponents(ship))
    local buffer = ffi.new('UniverseID[?]', math.max(1, n))
    local actual = R.count(C.GetDamagedSubComponents(buffer, n, ship))
    assert(actual <= n, 'damaged enumeration overflow')
    local components, identities, hulls = {}, {}, {}
    for index = 0, actual - 1 do
        local component, key = R.id(buffer[index])
        assert(component and not identities[key], 'invalid damaged component')
        identities[key] = true
        components[#components + 1] = component
        local hull = GetComponentData(component, 'hullpercent')
        assert(R.finite(hull) and hull >= 0 and hull <= 100, 'component hull unavailable')
        hulls[key] = hull
    end
    local hull = GetComponentData(ship, 'hullpercent')
    assert(R.finite(hull) and hull >= 0 and hull <= 100, 'ship hull unavailable')
    local _, key = R.id(ship)
    if hull < 100 and not identities[key] then
        components[#components + 1] = ship
        hulls[key] = hull
    end
    return components, hull, R.encode(hulls)
end

function R.quote(ship, provider)
    assert(R.id(ship) and R.id(provider), 'quote object unavailable')
    local components, hull, damage = R.damage(ship)
    local discounts = GetComponentData(provider, 'repairdiscounts')
    assert(type(discounts) == 'table', 'repair discounts unavailable')
    local factor = 1
    for _, entry in ipairs(discounts) do
        assert(type(entry) == 'table' and R.finite(entry.amount), 'invalid repair discount')
        factor = factor - entry.amount / 100
    end
    assert(R.finite(factor) and factor >= 0, 'invalid repair price factor')
    local amount = 0
    for _, component in ipairs(components) do
        local price = tonumber(C.GetRepairPrice(component, provider))
        assert(R.finite(price) and price >= 0, 'repair price unavailable')
        amount = amount + price * factor
    end
    assert(R.finite(amount) and amount >= 0, 'repair price overflow')
    return { amount = amount, components = components, hull = hull, damage = damage, mods = R.modifications(ship) }
end

function R.complete(request)
    assert(type(request) == 'table' and R.finite(request.generation) and R.finite(request.token), 'invalid recovery token')
    local ship, shipkey = R.id(request.ship)
    assert(ship, 'recovery ship no longer exists')
    if request.operation == 'CHECK' then
        local components, hull = R.damage(ship)
        return { request.generation, request.token, ship, 0, #components, {}, (hull < 100 or #components > 0) and 'DAMAGED' or 'HEALTHY' }
    end
    local provider, providerkey = R.id(request.provider)
    assert(ship and provider, 'recovery object no longer exists')
    local key = request.generation .. ':' .. request.token
    if request.operation == 'QUOTE' then
        assert(not R.snapshots[key], 'duplicate quote request')
        local quote = R.quote(ship, provider)
        quote.ship, quote.provider = shipkey, providerkey
        R.snapshots[key] = quote
        return { request.generation, request.token, ship, provider, quote.amount, quote.components, 'QUOTED' }
    elseif request.operation == 'COMMIT' then
        local before = R.snapshots[key]
        assert(before and not before.committed and before.ship == shipkey and before.provider == providerkey, 'missing or consumed repair quote')
        local current = R.quote(ship, provider)
        assert(current.amount == before.amount and current.damage == before.damage and current.mods == before.mods, 'repair quote changed; no debit authorized')
        before.committed = true
        return { request.generation, request.token, ship, provider, current.amount, current.components, 'COMMITTED' }
    elseif request.operation == 'VERIFY' then
        local before = R.snapshots[key]
        assert(before and before.committed and before.ship == shipkey and before.provider == providerkey, 'missing original committed repair snapshot')
        local components, hull = R.damage(ship)
        local mods = R.modifications(ship)
        assert(mods == before.mods, 'equipment modification readback mismatch')
        assert(hull == 100 and #components == 0, 'repair outcome not complete')
        R.snapshots[key] = nil
        return { request.generation, request.token, ship, provider, 0, {}, 'VERIFIED' }
    end
    error('unknown recovery operation')
end

function R.begin()
    R.pending = {}
end
function R.commit()
    local request = R.pending
    R.pending = nil
    if not request then return end
    local ok, result = pcall(R.complete, request)
    if ok then
        AddUITriggeredEvent('FOC_Recovery', 'evidence', result)
    elseif R.finite(request.generation) and R.finite(request.token) then
        AddUITriggeredEvent('FOC_Recovery', 'failure', { request.generation, request.token, tostring(result):sub(1, 180) })
    end
end

RegisterEvent('FOC_Recovery.begin', R.begin)
for _, field in ipairs({ 'generation', 'token', 'ship', 'provider', 'operation' }) do
    RegisterEvent('FOC_Recovery.' .. field, function(_, value)
        if R.pending then R.pending[field] = value end
    end)
end
RegisterEvent('FOC_Recovery.commit', R.commit)
RegisterEvent('FOC_Recovery.reset', function() R.pending = nil; R.snapshots = {}; R.policy = { repair = nil, shelter = nil } end)
RegisterEvent('FOC_Recovery.forget', function(_, key) R.snapshots[tostring(key)] = nil end)
function R.readPolicy(kind, value)
    if value == 0 or value == 1 then
        local changed = R.policy[kind] ~= (value == 1)
        R.policy[kind] = value == 1
        if changed and R.onPolicy then R.onPolicy() end
    end
end
RegisterEvent('FOC_Recovery.repair', function(_, value) R.readPolicy('repair', value) end)
RegisterEvent('FOC_Recovery.shelter', function(_, value) R.readPolicy('shelter', value) end)

function R.render(widget, actionRow, textRow, normal, warning)
    if R.policy.repair == nil or R.policy.shelter == nil then
        AddUITriggeredEvent('FOC_Menu', 'recovery_policy', nil)
    end
    for _, entry in ipairs({ { 'repair', 'Combat repair and return' }, { 'shelter', 'Transport emergency docking' } }) do
        local kind, label = entry[1], entry[2]
        local value = R.policy[kind]
        actionRow(widget, label, value == nil and 'AWAITING SAVED POLICY' or (value and 'ON - CLICK TO DISABLE' or 'OFF - CLICK TO ENABLE'), function()
            if R.policy[kind] ~= value or value == nil then return end
            AddUITriggeredEvent('FOC_Recovery', 'policy', { kind, value and 1 or 0, value and 0 or 1 })
        end, value ~= nil, value and normal or warning)
    end
    textRow(widget, 'Recovery authority', 'Independent opt-ins. Repair may spend credits at NPC facilities; no upgrades. Shelter holds for tracked threats. STOP disables both. Capital piers are exposed.', warning)
end
