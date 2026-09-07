-- B058: explicit, bounded coverage analysis and composition planning. No orders or fees.
local ffi = require('ffi')
local A = { data = nil, draft = {}, page = 1, request = 0, templates = {}, status = 'Refresh to analyse recorded supply-ship attacks.' }
FOC_Advisor = A
local C = ffi.C

function A.number(value)
    local n = tonumber(value)
    if n and n == n and n > -math.huge and n < math.huge then return n end
end
function A.component(value)
    local s = tostring(value or ''):gsub('ULL$', ''):gsub('LL$', '')
    if not s:match('^%d+$') or s:match('^0+$') then return nil end
    local ok, id = pcall(ConvertStringTo64Bit, s)
    if not ok then return nil end
    local valid, exists = pcall(IsValidComponent, id)
    if valid and exists then return id end
end
function A.changed()
    if A.onChange then A.onChange() end
end
function A.go(step)
    A.step = step
    if A.resetDetailPage then A.resetDetailPage() end
end
function A.refresh()
    if A.saving then A.status = 'Save readback pending. Use RECHECK to reconcile first.'; return end
    A.request = A.request + 1
    A.pending = nil
    A.queue = nil
    if #A.draft==0 then A.selected=nil end
    A.coverage=nil
    A.go('AREAS')
    A.started = getElapsedTime()
    A.status = 'Reading current coverage and saved templates...'
    AddUITriggeredEvent('FOC_Advisor', 'refresh', A.request)
end
function A.rank(rows, metric)
    table.sort(rows, function(a, b)
        local av, bv = A.number(a[metric]), A.number(b[metric])
        if av ~= bv then
            if av == nil then return false end
            if bv == nil then return true end
            return av > bv
        end
        return tostring(a.macro or a.id) < tostring(b.macro or b.id)
    end)
    return rows
end
function A.commit()
    local p = A.pending
    A.pending = nil
    if not p or p.request ~= A.request then return end
    A.started = nil
    if p.invalid or p.row or p.count ~= p.expected or not A.number(p.time) then
        A.status = 'Incomplete analysis; previous evidence retained. Refresh again.'
        A.changed(); return
    end
    A.data = p
    A.templates = p.templates
    A.status = 'Analysis complete. Samples are recorded attacks, not unique battles or all supply traffic.'
    if A.saving then
        local match = false
        for _, t in ipairs(A.templates) do
            if t.name == A.saving.name and #t.entries == #A.saving.entries then
                local same = true
                for i, e in ipairs(t.entries) do
                    local want = A.saving.entries[i]
                    if e.macro ~= want.macro or e.amount ~= want.amount then same = false end
                end
                if same and tostring(t.home or '0') == A.saving.home then match = true end
            end
        end
        A.status = match and 'Template saved and read back. No ships ordered and no credits spent.' or 'Template save was not confirmed; your draft is retained.'
        A.saving = nil
        if match and A.step == 'DRAFT' then A.go('SAVED') end
    end
    A.changed()
end
RegisterEvent('FOC_Advisor.begin', function(_, request)
    A.pending = nil
    if tonumber(request) ~= A.request then return end
    A.pending = { request = tonumber(request), count = 0, observations = {}, yards = {}, templates = {}, byTemplate = {}, homes = {}, byHome = {} }
end)
RegisterEvent('FOC_Advisor.expected', function(_, value) if A.pending then A.pending.expected = tonumber(value) end end)
RegisterEvent('FOC_Advisor.clock', function(_, value) if A.pending then A.pending.time = tonumber(value) end end)
RegisterEvent('FOC_Advisor.row', function(_, kind) if A.pending then if A.pending.row then A.pending.invalid=true end; A.pending.row = { kind = kind } end end)
for _, field in ipairs({ 'id', 'name', 'sector', 'sectorname', 'time', 'owned', 'macro', 'amount', 'parent', 'attackerclass', 'home', 'homename' }) do
    RegisterEvent('FOC_Advisor.' .. field, function(_, value)
        if A.pending and A.pending.row then
            if A.pending.row[field]~=nil then A.pending.invalid=true end
            A.pending.row[field]=value
        end
    end)
end
RegisterEvent('FOC_Advisor.rowcommit', function()
    local p = A.pending
    if not p or not p.row then return end
    local r = p.row; p.row = nil; p.count = p.count + 1
    if p.count > 1120 then p.invalid = true; return end
    if r.kind == 'observation' then
        if not r.sector or not A.number(r.time) then p.invalid = true; return end
        if r.attackerclass ~= nil and not ({XS=true,S=true,M=true,L=true,XL=true,UNKNOWN=true})[r.attackerclass] then p.invalid=true; return end
        p.observations[#p.observations + 1] = r
    elseif r.kind == 'home' then
        local key=tostring(r.id or '')
        if key=='' or type(r.name)~='string' or r.name=='' or p.byHome[key] or #p.homes>=512 then p.invalid=true; return end
        p.byHome[key]=true; p.homes[#p.homes+1]=r
    elseif r.kind == 'yard' then
        if not r.id or not r.name then p.invalid = true; return end
        p.yards[#p.yards + 1] = r
    elseif r.kind == 'template' then
        local key = tostring(r.id)
        if not r.id or not r.name or p.byTemplate[key] then p.invalid = true; return end
        if r.home ~= nil then
            r.home=tostring(r.home):gsub('ULL$',''):gsub('LL$','')
            if not r.home:match('^%d+$') or type(r.homename)~='string' then p.invalid=true;return end
        end
        r.entries = {}; r.total=0; p.byTemplate[key] = r; p.templates[#p.templates + 1] = r
    elseif r.kind == 'entry' then
        local parent = p.byTemplate[tostring(r.parent)]
        local n = A.number(r.amount)
        if not parent or not r.macro or not n or n < 1 or n > 100 or n % 1 ~= 0 or #parent.entries >= 8 then p.invalid = true; return end
        parent.entries[#parent.entries + 1] = { macro = tostring(r.macro), amount = n }
        parent.total=parent.total+n; if parent.total>100 then p.invalid=true end
    else p.invalid = true end
end)
RegisterEvent('FOC_Advisor.complete', A.commit)
RegisterEvent('FOC_Advisor.failure', function(_, reason) A.pending = nil; A.started=nil; A.status = tostring(reason); A.changed() end)
-- A definitive refusal, unlike a timeout/partial snapshot, permits correcting this draft.
RegisterEvent('FOC_Advisor.save_rejected', function(_, request)
    if A.saving and tonumber(request)==A.request then
        A.saving=nil; A.pending=nil; A.started=nil; A.changed()
    end
end)
RegisterEvent('FOC_Advisor.coveragesector', function(_, id) A.coverageSector = tostring(id) end)
RegisterEvent('FOC_Advisor.coverage', function(_, text)
    if A.selected and tostring(A.selected.id) == A.coverageSector then A.coverage = tostring(text); A.changed() end
end)

function A.hotspots()
    local rows, byID = {}, {}
    if not A.data or not A.number(A.data.time) then return rows end
    for _, o in ipairs(A.data.observations) do
        local age = A.data.time - o.time
        if age >= 0 and age <= 3600 then
            local id = tostring(o.sector)
            local r = byID[id]
            if not r then r = { id = id, name = o.sectorname or 'Unknown sector', samples = 0, last = o.time }; byID[id] = r; rows[#rows + 1] = r end
            r.samples = r.samples + 1; r.last = math.max(r.last, o.time)
            local weight=({XS=1,S=2,M=3,L=4,XL=5})[o.attackerclass]
            if not weight then r.unknown=(r.unknown or 0)+1
            elseif weight>(r.threatWeight or 0) then r.threatWeight=weight; r.attackerclass=o.attackerclass end
        end
    end
    table.sort(rows, function(a,b) if a.samples ~= b.samples then return a.samples > b.samples end; if a.last ~= b.last then return a.last > b.last end; return a.id < b.id end)
    return rows
end
function A.chooseHotspot(row)
    local sector = A.component(row.id)
    if not sector then A.status = 'Sector no longer available. Refresh analysis.'; return end
    A.selected = row
    A.go('DETAIL')
    A.coverage = 'Checking available response fleets...'
    AddUITriggeredEvent('FOC_Advisor', 'coverage', sector)
end

function A.chooseHome(row)
    if A.saving or not A.data then return false end
    local found=false
    for _,home in ipairs(A.data.homes or {}) do if home==row then found=true; break end end
    if not found or not A.component(row.id) then A.status='Home selection changed. Refresh and choose again.'; return false end
    A.selected={id=row.id,name=row.name}
    A.status='Home selected: '..row.name..'. Review and save the fleet before ordering.'
    A.go('SHIPS')
    if not A.ships and not A.queue then A.catalogue() end
    return true
end

-- Native catalogue and generated medium-preset statistics; never queue a build task.
function A.eligibility(macro, yard, owned)
    local ok, allowed, reason = pcall(function()
        local ware=GetMacroData(macro,'ware')
        if type(ware)~='string' or ware=='' then return false,'Hull availability unknown' end
        local licence,blueprintOnly,research,limited=GetWareData(ware,'tradelicence','isblueprintsaleonly','productionresearchprecursors','islimited')
        if type(licence)~='string' or type(blueprintOnly)~='boolean' or type(limited)~='boolean' or (research~=nil and type(research)~='table') then return false,'Hull restrictions unavailable' end
        -- Do not promise a multi-ship fleet from limited/research unlocks. X4 must review these individually.
        if limited or (research and #research>0) then return false,'Special/limited hull: review individually in X4; excluded from fleet proposals' end
        if not owned and blueprintOnly then return false,'Blueprint sale only; NPC cannot sell this hull' end
        if not owned and licence~='' then
            local owner=GetComponentData(yard,'owner')
            if type(owner)~='string' or owner=='' or HasLicence('player',licence,owner)~=true then return false,'Required ship licence unavailable' end
        end
        return true
    end)
    if not ok then return false,'Hull availability could not be checked' end
    return allowed==true,reason
end
function A.metric(value)
    local n=A.number(value)
    return n and string.format('%.0f',n) or 'UNKNOWN'
end
function A.catalogue()
    if not A.data then A.status = 'Refresh analysis first.'; return end
    local ok, result = pcall(function()
        local rows, seen, owned = {}, {}, {}
        local n = tonumber(C.GetNumBlueprints('', '', ''))
        assert(n and n >= 0 and n <= 8192, 'Blueprint catalogue exceeds analysis bound')
        if n > 0 then
            local buffer = ffi.new('UIBlueprint[?]', n)
            local actual = tonumber(C.GetBlueprints(buffer, n, '', '', ''))
            assert(actual == n, 'Incomplete blueprint catalogue')
            for i=0,actual-1 do owned[ffi.string(buffer[i].macro)] = true end
        end
        for _, library in ipairs({ 'shiptypes_s', 'shiptypes_m', 'shiptypes_l', 'shiptypes_xl' }) do
            local list = GetLibrary(library)
            assert(type(list) == 'table', 'Ship catalogue unavailable')
            for _, entry in ipairs(list) do
                local macro = tostring(entry.id)
                if not seen[macro] and GetMacroData(macro, 'primarypurpose') == 'fight' then
                    seen[macro] = true
                    rows[#rows+1] = { macro = macro, name = GetMacroData(macro, 'name') or macro, owned = owned[macro] == true, class = library, route = 'No known compatible seller or owned yard found' }
                end
            end
        end
        assert(#rows <= 512, 'Combat catalogue exceeds 512-hull bound; no partial ranking produced')
        local yards = {}
        assert(#A.data.yards <= 128, 'Too many yards; refresh failed safely')
        for _, yard in ipairs(A.data.yards) do
            local id = A.component(yard.id)
            if id then
                local count = tonumber(C.GetNumContainerBuilderMacros(id))
                assert(count and count >= 0 and count <= 2048, 'Yard hull catalogue exceeds bound')
                local macros = {}
                if count > 0 then
                    local buf = ffi.new('const char*[?]', count)
                    local got = tonumber(C.GetContainerBuilderMacros(buf, count, id))
                    assert(got == count, 'Yard hull catalogue incomplete')
                    for i=0,got-1 do macros[ffi.string(buf[i])] = true end
                end
                yards[#yards+1] = { id = id, name = yard.name, owned = tonumber(yard.owned) == 1, macros = macros }
            end
        end
        table.sort(yards, function(a,b) if a.owned ~= b.owned then return a.owned end; return tostring(a.id)<tostring(b.id) end)
        for _, row in ipairs(rows) do
            for _, yard in ipairs(yards) do
                if yard.macros[row.macro] and (not yard.owned or row.owned) and C.CanGenerateValidLoadout(yard.id, row.macro) then
                    local allowed,reason=A.eligibility(row.macro,yard.id,yard.owned)
                    if allowed then
                        if not row.yard then row.yard=tostring(yard.id);row.route=(yard.owned and 'BUILD at ' or 'BUY from ')..yard.name end
                        if not yard.owned and not row.npcyard then row.npcyard=tostring(yard.id);row.npcname=yard.name end
                    elseif not row.yard then row.route=reason end
                end
            end
        end
        return rows
    end)
    if ok then A.ships = result; A.page = 1; A.queue = { index = 1 }; A.status = 'Comparing the catalogue once, one hull at a time. Leaving this workspace pauses the comparison.'
    else A.ships=nil;A.chosen=nil;A.queue=nil;A.status = 'Catalogue unavailable: ' .. tostring(result) end
    A.changed()
end
function A.analyse(row, quiet)
    local yard = A.component(row.yard)
    if not yard then A.status = 'No available yard for this hull. Refresh the catalogue.'; return end
    local ok, stats = pcall(function()
        assert(C.CanGenerateValidLoadout(yard, row.macro), 'Yard loadout no longer available')
        local loadout = Helper.getLoadoutHelper2(C.GenerateShipLoadout2, C.GenerateShipLoadoutCounts2, 'UILoadout2', yard, 0, row.macro, 0.5)
        -- Native prepareSoftwareData contract: nil would log an error for a preset containing software.
        local software = {}
        for _,kind in ipairs(Helper.upgradetypes) do
            if kind.supertype == 'software' then
                software[kind.type] = {}
                local n=tonumber(C.GetNumSoftwareSlots(0,row.macro))
                assert(n and n>=0 and n<=128,'Software slot bound exceeded')
                if n>0 then
                    local buf=ffi.new('SoftwareSlot[?]',n)
                    assert(tonumber(C.GetSoftwareSlots(buf,n,0,row.macro))==n,'Software slots changed')
                    for i=0,n-1 do software[kind.type][#software[kind.type]+1]={maxsoftware=ffi.string(buf[i].max),currentsoftware=ffi.string(buf[i].current)} end
                end
            end
        end
        local plan = Helper.convertLoadout(0, row.macro, loadout, software, 'UILoadout2')
        return Helper.callLoadoutFunction(plan, nil, function(value) return Helper.convertLoadoutStats(C.GetLoadoutStatistics5(0, row.macro, value)) end)
    end)
    Helper.ffiClearNewHelper()
    if ok and type(stats) == 'table' then
        row.speed = A.number(stats.ForwardSpeed); row.travel = A.number(stats.TravelSpeed)
        local gun, turret, grouped = A.number(stats.SustainedDPS), A.number(stats.TurretSustainedDPS), A.number(stats.GroupedTurretSustainedDPS)
        row.power = gun and turret and grouped and (gun + turret + grouped) or nil
        row.hull = A.number(stats.HullValue); row.shield = A.number(stats.ShieldValue)
        if not quiet then A.chosen = row end
        A.status = 'Medium-preset comparison only; final equipment, resources, price and delivery are confirmed in X4.'
    else A.status = 'Loadout analysis unavailable: ' .. tostring(stats) end
    if not quiet then A.changed() end
end
function A.tick()
    if FOC_Procurement then FOC_Procurement.tick() end
    if FOC_Construction then FOC_Construction.tick() end
    if FOC_NPC_Purchases then FOC_NPC_Purchases.tick() end
    if A.started and getElapsedTime() - A.started > 20 then
        A.started = nil; A.pending = nil
        A.status = 'Readback timed out. RECHECK saved templates before retrying a save; your draft is retained.'
        A.changed()
    end
    local q = A.queue
    if not q then return end
    local row = A.ships[q.index]
    if row then
        if row.yard then A.analyse(row, true) end
        q.index = q.index + 1
    else
        A.queue = nil; A.sort = 'SPEED'; A.rank(A.ships, 'speed')
        A.status = 'Catalogue comparison finished. Unknown statistics sort last. No purchase, equipment change or fleet order was made.'
        A.changed()
    end
end
function A.recommend()
    if A.saving or A.queue or not A.ships then return end
    if #A.draft > 0 then A.status = 'Clear the draft first; recommendations never overwrite your composition.'; return end
    local candidates, capitals, mediums = {}, {}, {}
    for _, r in ipairs(A.ships) do
        if r.yard and r.speed and r.speed > 0 and r.power and r.power > 0 then
            if r.class=='shiptypes_l' then capitals[#capitals+1]=r end
            if r.class=='shiptypes_m' then mediums[#mediums+1]=r end
            if r.class=='shiptypes_s' or r.class=='shiptypes_m' then candidates[#candidates+1]=r end
        end
    end
    local threat=A.selected and A.selected.attackerclass
    if threat=='L' or threat=='XL' then
        if #capitals==0 or #mediums==0 then A.status='Capital-threat proposal unavailable: an armed L leader and M escorts need known statistics and build/buy routes. No smaller fleet substituted.'; return end
        A.rank(capitals,'power'); A.rank(mediums,'speed')
        local leaders,escorts=1,5
        if threat=='XL' then leaders,escorts=2,8 end
        A.add(capitals[1],leaders); A.add(mediums[1],escorts)
        A.status='Proposal for recorded '..threat..' attackers: '..leaders..' '..capitals[1].name..' + '..escorts..' '..mediums[1].name..'. Strongest available L preset, fastest armed M escorts. Planning default, not a victory guarantee.'
        if (A.selected.unknown or 0)>0 then A.status=A.status..' Some attack records lack attacker class.' end
        return
    end
    if #candidates == 0 then A.status = 'No armed S/M preset with known speed and an acquisition route. Choose hulls manually.'; return end
    local maxSpeed, maxPower = 0, 0
    for _,r in ipairs(candidates) do maxSpeed=math.max(maxSpeed,r.speed);maxPower=math.max(maxPower,r.power) end
    for _,r in ipairs(candidates) do r.responseScore=0.6*r.speed/maxSpeed+0.4*r.power/maxPower end
    A.rank(candidates,'responseScore')
    A.add(candidates[1],4)
    A.status = 'Starter proposal: 4 '..candidates[1].name..'. Ranked 60% speed / 40% sustained firepower among available armed S/M presets. '..(threat and ('Largest recorded attacker: '..threat..'.') or 'Attacker class unknown; generic starter only.')..' Not a guarantee against capital threats.'
    if A.selected and (A.selected.unknown or 0)>0 then A.status=A.status..' Some attack records lack attacker class.' end
end
function A.add(row, amount)
    amount = A.number(amount)
    if not row or not row.macro or not amount or amount % 1 ~= 0 or amount < 1 then return false end
    local total = amount
    for _, entry in ipairs(A.draft) do total = total + entry.amount end
    if total<=100 then
        for _,entry in ipairs(A.draft) do if entry.macro==row.macro then entry.amount=entry.amount+amount;A.status='Updated this hull quantity in the draft. Save before ordering.';return true end end
    end
    if total > 100 or #A.draft >= 8 then A.status = 'Template limit: 100 ships and 8 entries.'; return false end
    A.draft[#A.draft+1] = { macro = row.macro, amount = amount }
    A.status = 'Added to draft only. Save when the composition is ready.'
    return true
end
function A.save()
    if A.saving or #A.draft == 0 then return end
    local home=A.selected and A.component(A.selected.id)
    if not home then A.status='Choose a Home sector before saving this fleet.';return end
    local entries, packet = {}, { A.request + 1, A.templateName or 'Response Fleet 1' }
    for _, e in ipairs(A.draft) do entries[#entries+1] = { macro=e.macro, amount=e.amount }; packet[#packet+1]=e.macro; packet[#packet+1]=e.amount end
    A.request = A.request + 1
    A.pending = nil
    packet[#packet+1]=home
    A.saving = { name = packet[2], entries = entries, home=tostring(home) }
    A.started = getElapsedTime()
    A.status = 'Saving template; waiting for complete readback...'
    AddUITriggeredEvent('FOC_Advisor', 'save_v2', packet)
end

function A.savedDraft()
    for _,t in ipairs(A.templates) do
        if t.name==(A.templateName or 'Response Fleet 1') and #t.entries==#A.draft then
            local same=true
            for i,e in ipairs(t.entries) do if e.macro~=A.draft[i].macro or e.amount~=A.draft[i].amount then same=false end end
            if same and A.selected and tostring(t.home or '0')==tostring(A.component(A.selected.id)) then return t end
        end
    end
end
function A.purchase(entry)
    if FOC_Procurement then return FOC_Procurement.prepare() end
    if A.saving or not A.openPurchase then return false end
    local template=A.savedDraft()
    local home=A.selected and A.component(A.selected.id)
    if not template or not home or not FOC_NPC_Purchases then A.status='Save this exact composition and choose its Home before buying.';return false end
    local current = false
    for _, e in ipairs(A.draft) do if e == entry then current = true end end
    if not current then A.status = 'Fleet draft changed. Review it again.'; return false end
    local row
    for _, candidate in ipairs(A.ships or {}) do if candidate.macro == entry.macro then row = candidate; break end end
    local yard = row and A.component(row.npcyard)
    if not yard then A.status = 'Compare ships again to find a current supplier.'; return false end
    local ok, available = pcall(function()
        local owner, trader = GetComponentData(yard, 'isplayerowned', 'shiptrader')
        return owner == false and trader ~= nil and trader ~= false and trader ~= 0 and A.eligibility(entry.macro,yard,false) and C.CanGenerateValidLoadout(yard, entry.macro)
    end)
    if not ok or not available then A.status = 'NPC supplier unavailable. Compare ships again; no order sent.'; return false end
    A.status = 'Purchase plan: '..tostring(entry.amount)..' x '..tostring(row.name)..'. Select this hull and quantity in X4, review equipment and price, then confirm. Returning here does not mark ships delivered.'
    local n=FOC_NPC_Purchases
    local quantity=entry.amount
    if n.snapshot and n.snapshot.approved==0 and n.snapshot.template==template.id and n.snapshot.home==tostring(home) then
        for _,r in ipairs(n.snapshot.rows) do if r.macro==entry.macro then quantity=quantity-1 end end
    end
    if quantity<1 then A.status='This hull already has captured purchases. Review them before buying more.';return false end
    local epoch=A.purchaseEpoch
    A.go('NPC')
    return n.start(template,home,yard,entry.macro,quantity,function()
        return A.purchaseContextActive and A.purchaseContextActive(epoch) and A.step=='NPC' and A.savedDraft()==template and A.selected and tostring(A.component(A.selected.id))==tostring(home) and A.component(yard)~=nil
    end,function() A.openPurchase(yard) end)
end

function A.loadTemplate(t)
    if A.saving then return false end
    local found=false
    for _,saved in ipairs(A.templates) do if saved==t then found=true end end
    if not found then A.status='Saved template changed. Refresh saved plans.';return false end
    local same=#A.draft==#t.entries
    for i,e in ipairs(A.draft) do if not t.entries[i] or e.macro~=t.entries[i].macro or e.amount~=t.entries[i].amount then same=false end end
    if A.selected and tostring(A.component(A.selected.id))~=tostring(t.home or '0') then same=false end
    if #A.draft>0 and not same then A.status='A different draft is open. Review it, then save or clear it before loading another fleet.';A.go('DRAFT');return false end
    A.draft={};for _,e in ipairs(t.entries) do A.draft[#A.draft+1]={macro=e.macro,amount=e.amount} end
    A.templateName=t.name
    if A.component(t.home) then
        A.selected={id=t.home,name=t.homename};A.status='Loaded '..t.name..'. Home: '..t.homename..'. No ships ordered.';A.go('DRAFT')
    else
        A.selected=nil;A.status='This older template has no saved Home. Choose a sector, then save it before ordering.';A.go('HOME')
    end
    return true
end

function A.render(w, realAction, realText, realDropdown, normal, warning, pager)
    if A.step == 'PROCUREMENT' and FOC_Procurement then
        return FOC_Procurement.render(w,realAction,realText,realDropdown,normal,warning)
    end
    if A.step == 'NPC' and FOC_NPC_Purchases and FOC_NPC_Purchases.render then
        return FOC_NPC_Purchases.render(w,realAction,realText,realDropdown,normal,warning)
    end
    -- Build descriptions first, then populate only the viewport/pool-budgeted slice.
    local rows = {}
    local function action(_, label, caption, handler, active, color)
        rows[#rows+1] = function() realAction(w, label, tostring(caption):sub(1,160), function() if active == false or (A.isCurrent and not A.isCurrent(w)) then return end; handler(); A.changed() end, active, color) end
    end
    local function text(_, label, caption, color)
        rows[#rows+1] = function() realText(w,label,tostring(caption):sub(1,240),color) end
    end
    local function dropdown(_, label, values, selected, handler)
        rows[#rows+1] = function() realDropdown(w,label,values,selected,function(value) if A.isCurrent and not A.isCurrent(w) then return false end; handler(value); A.changed(); return false end) end
    end
    local step = A.step or (A.selected and 'DETAIL' or 'AREAS')
    if step == 'DETAIL' and not A.selected then step = 'AREAS' end
    if step == 'DETAIL' then
        action(w, 'Selected area', A.selected.name..' - BACK TO HOTSPOTS', function() A.go('AREAS') end, true, normal)
        text(w, 'Need another fleet?', (A.coverage and A.coverage:match('^(.-) | ')) or 'Not assessed yet - waiting for current fleet evidence.', warning)
        text(w, 'Nearby fleet', A.coverage or 'Checking fleet distance...', normal)
        text(w, 'Suggested Home', A.selected.name..': choose a safe point near your supply route in Fleets > Choose Home. This is a suggested sector, not a checked safe location.', warning)
        action(w, 'View area', 'SHOW '..A.selected.name..' ON MAP', function() if A.openSector then A.openSector(A.selected.id) end end, A.openSector~=nil, normal)
        text(w,'Placement target','One ready patrol/guard fleet of at least four ships within two gates. This recommendation does not predict battle results or change response rules.',normal)
        action(w, 'Next: choose ships', 'COMPARE SHIPS FOR THIS AREA', function() A.go('SHIPS'); if not A.ships and not A.queue then A.catalogue() end end, not A.saving, normal)
    end
    if step == 'AREAS' then
    action(w, 'Update information', 'REFRESH HOTSPOTS AND TEMPLATES', A.refresh, not A.saving, normal)
    action(w, 'Saved plans', 'OPEN SAVED FLEET TEMPLATES', function()
        A.go('SAVED')
        A.request=A.request+1; A.pending=nil; A.started=getElapsedTime()
        AddUITriggeredEvent('FOC_Advisor','refresh',A.request)
    end, not A.started, normal)
    action(w, 'Start without a hotspot', 'PLAN A NEW FLEET', function() A.go('HOME') end, A.data~=nil and not A.saving, normal)
    text(w, 'Result', A.status, warning)
    text(w, 'Start here', 'Choose an attacked area, or plan a new fleet and choose its Home. Save the composition, then review construction before approving any ships.', normal)
    local spots = A.hotspots()
    for i=1,#spots do
        local row = spots[i]
        action(w, 'Attacked area '..i, row.name..' | '..row.samples..' attack reports in the last hour', function() if A.resetDetailPage then A.resetDetailPage() end; A.chooseHotspot(row) end, true, warning)
    end
    if #spots == 0 then text(w, 'Hotspots', 'No retained civilian attacks in the last hour. This does not prove routes are safe.', warning) end
    end
    if step == 'HOME' then
        action(w,'Back','BACK TO COVERAGE',function() A.go('AREAS') end,true,normal)
        text(w,'Choose Home','Choose the sector this new fleet will patrol. This does not claim that every point in the sector is safe.',normal)
        local homes={}
        for _,home in ipairs(A.data and A.data.homes or {}) do homes[#homes+1]=home end
        table.sort(homes,function(a,b) if a.name==b.name then return tostring(a.id)<tostring(b.id) end; return a.name<b.name end)
        for _,home in ipairs(homes) do
            local selected=home
            action(w,'Patrol Home',home.name,function() A.chooseHome(selected) end,not A.saving,normal)
        end
        if #homes==0 then text(w,'Home sectors','Refresh coverage to load your known sectors.',warning) end
    end
    if step == 'SHIPS' then
    action(w, 'Back', 'BACK TO COVERAGE', function() A.go('AREAS') end, true, normal)
    action(w, 'Next: review fleet', 'REVIEW YOUR FLEET TEMPLATE', function() A.go('DRAFT') end, #A.draft>0, normal)
    action(w, 'Recommended template', 'CREATE RECOMMENDED FLEET COMPOSITION', function() A.recommend(); if #A.draft>0 then A.go('DRAFT') end end, A.ships~=nil and not A.queue and not A.saving, normal)
    action(w,'Home',A.selected and ('HOME: '..A.selected.name..' - CHANGE') or 'CHOOSE HOME',function() A.go('HOME') end,not A.saving,normal)
    action(w, 'Choose ships', 'COMPARE AVAILABLE COMBAT SHIPS', A.catalogue, A.data ~= nil and not A.saving and not A.queue, normal)
    text(w, 'Result', A.status, warning)
    if A.queue then text(w,'Comparison','One-shot comparison in progress. '..tostring(A.queue.index),normal) end
    if A.ships then
        dropdown(w, 'Sort analysed hulls', { 'SPEED', 'FIREPOWER', 'NAME' }, A.sort or 'NAME', function(value)
            A.sort=value
            if value=='NAME' then table.sort(A.ships,function(a,b)return a.name<b.name end) else A.rank(A.ships,value=='SPEED' and 'speed' or 'power') end
        end)
        local pages=math.max(1,math.ceil(#A.ships/4)); A.page=math.max(1,math.min(A.page,pages))
        action(w, 'Catalogue page', tostring(A.page)..' / '..pages..' - NEXT PAGE',function()A.page=A.page%pages+1 end,true,normal)
        for i=(A.page-1)*4+1,math.min(#A.ships,A.page*4) do
            local row=A.ships[i]
            action(w, row.owned and 'Blueprint owned' or 'NPC option', row.name..' | '..A.metric(row.speed)..' m/s | '..A.metric(row.power)..' DPS | '..(row.yard and 'ANALYSE' or row.route),function()A.analyse(row)end,row.yard~=nil,normal)
        end
    end
    if A.chosen then
        local r=A.chosen
        text(w,'Acquisition',r.route,normal)
        text(w,'Compared hull',r.name..' | speed '..A.metric(r.speed)..' m/s | travel '..A.metric(r.travel)..' m/s | sustained DPS '..A.metric(r.power),normal)
        dropdown(w,'Quantity',{'1','2','4','6','8','10','20','50'},A.quantity or '4',function(value) A.quantity=value end)
        action(w,'Composition','ADD SELECTED QUANTITY TO DRAFT',function()A.add(r,tonumber(A.quantity or '4'))end,not A.saving,normal)
    end
    end
    if step == 'DRAFT' then
    action(w, 'Back', 'BACK TO SHIP SELECTION', function() A.go('SHIPS') end, true, normal)
    action(w,'Save composition','SAVE FLEET AND HOME - CONTINUE',A.save,#A.draft>0 and not A.saving and A.selected~=nil,normal)
    action(w,'Home',A.selected and ('HOME: '..A.selected.name..' - CHANGE') or 'CHOOSE HOME BEFORE SAVING',function()A.go('HOME')end,not A.saving,normal)
    local names={};for i=1,20 do names[i]='Response Fleet '..i end
    dropdown(w,'Template slot',names,A.templateName or names[1],function(value)if not A.saving then A.templateName=value end end)
    text(w, 'Result', A.status, warning)
    for i,e in ipairs(A.draft) do
        text(w,'Draft entry '..i,tostring(e.amount)..' x '..tostring(GetMacroData(e.macro,'name') or e.macro),normal)
        if not FOC_Procurement then action(w,'NPC purchase','OPEN NPC SHIP PURCHASE FOR ENTRY '..i,function() A.purchase(e) end,not A.saving and A.savedDraft()~=nil and A.ships~=nil and A.openPurchase~=nil,normal) end
    end
    if FOC_Procurement then action(w,'NPC purchase','PREPARE ENTIRE SAVED FLEET PURCHASE',FOC_Procurement.prepare,not A.saving and A.savedDraft()~=nil and A.ships~=nil,normal) end
    text(w,'Purchase confirmation',FOC_Procurement and 'Review suppliers, actual medium equipment, quantities, Home and total in FOC. Only CONFIRM PURCHASE spends credits and authorizes assembly after delivery.' or 'Review equipment and costs in the native purchase screen.',normal)
    text(w,'Your fleet plan',tostring(#A.draft)..' ship types. Saved composition does not itself authorize a purchase.',normal)
    text(w,'Save behavior','Saving replaces the selected numbered template slot. No ship equipment or modifications are copied.',warning)
    action(w,'New composition','CLEAR UNSAVED DRAFT - KEEP SAVED TEMPLATES',function()A.draft={};A.status='Draft cleared. Saved templates are unchanged. Open a saved fleet or select new ships.'end,not A.saving,warning)
    action(w,'Saved plans','OPEN SAVED FLEET TEMPLATES',function()A.go('SAVED')end,true,normal)
    end
    if step == 'SAVED' then
    action(w,'Back','BACK TO COVERAGE',function()A.go('AREAS')end,true,normal)
    if FOC_Procurement then action(w,'Prepared purchases','CHECK PREPARED FLEET ORDER',function()A.go('PROCUREMENT');FOC_Procurement.status()end,not FOC_Procurement.pending,normal) end
    if FOC_NPC_Purchases then action(w,'NPC purchases','REVIEW NPC PURCHASES AND DELIVERY',function() A.go('NPC');FOC_NPC_Purchases.status() end,not FOC_NPC_Purchases.pending,normal) end
    text(w,'Result',A.status,warning)
    if #A.templates==0 then text(w,'Saved templates','No saved templates. Plan a new fleet from Coverage.',normal) end
    for i=1,#A.templates do
        local t=A.templates[i]
        action(w,'Saved template',t.name..' | '..(t.homename or 'CHOOSE HOME')..' | REVIEW / BUY',function()
            if A.loadTemplate(t) and A.component(t.home) then
                A.go('PURCHASE')
                if not A.ships and not A.queue then A.catalogue() end
            end
        end,not A.saving,normal)
        if FOC_Construction then
            action(w,'Build at your yards','PLAN CONSTRUCTION: '..t.name,function()
                if not A.loadTemplate(t) or not A.component(t.home) then return end
                if FOC_Construction.prepare(t,t.home) then A.go('CONSTRUCTION') end
            end,not A.saving and not FOC_Construction.pending,normal)
        end
    end
    if FOC_Construction then action(w,'Construction progress','CHECK LAST FOC CONSTRUCTION',function() A.go('CONSTRUCTION'); FOC_Construction.status() end,not FOC_Construction.pending,normal) end
    end
    if step == 'PURCHASE' then
        local t=A.savedDraft()
        action(w,'Back','BACK TO SAVED FLEETS',function()A.go('SAVED')end,true,normal)
        text(w,'Fleet Home',A.selected and A.selected.name or 'CHOOSE HOME',normal)
        for i,e in ipairs(A.draft) do
            local supplier
            for _,r in ipairs(A.ships or {}) do if r.macro==e.macro then supplier=r;break end end
            text(w,'Buy entry '..i,tostring(e.amount)..' x '..tostring(GetMacroData(e.macro,'name') or e.macro),normal)
            if FOC_Procurement then text(w,'Supplier',supplier and supplier.npcyard and tostring(supplier.npcname or 'NPC SUPPLIER') or 'NO ELIGIBLE NPC SUPPLIER FOUND',normal)
            else action(w,'NPC purchase',supplier and supplier.npcyard and ('BUY FROM '..tostring(supplier.npcname or 'NPC SUPPLIER')..' - REVIEW IN X4') or 'NO ELIGIBLE NPC SUPPLIER FOUND',function()A.purchase(e)end,t~=nil and supplier~=nil and supplier.npcyard~=nil and not A.saving and A.openPurchase~=nil,normal) end
        end
        if FOC_Construction then action(w,'Your own yards','PREVIEW BUILDING THIS FLEET AT MY YARDS',function()if t and FOC_Construction.prepare(t,t.home) then A.go('CONSTRUCTION')end end,t~=nil and not FOC_Construction.pending,normal) end
        if FOC_Procurement then action(w,'NPC purchase','PREPARE ENTIRE SAVED FLEET PURCHASE',FOC_Procurement.prepare,t~=nil and A.ships~=nil and not A.saving and not FOC_Procurement.pending,normal) end
        text(w,'Before buying',FOC_Procurement and 'Prepare first, inspect every hull and its equipment, then confirm the whole fleet price once. Native orders may wait for resources; delivery and assembly are separate.' or 'Review captured orders after native purchase; returning is not delivery.',normal)
        action(w,'Suppliers','RECHECK SHIP SUPPLIERS',A.catalogue,A.data~=nil and not A.queue and not A.saving,normal)
        action(w,'Edit','EDIT FLEET COMPOSITION',function()A.go('DRAFT')end,not A.saving,normal)
        text(w,'Result',A.status,warning)
    end
    if step == 'CONSTRUCTION' and FOC_Construction then
        local b=FOC_Construction
        action(w,'Back','BACK TO SAVED TEMPLATES',function() A.go('SAVED') end,true,normal)
        text(w,'Construction',b.message,warning)
        text(w,'Cost','Player yards consume normal construction resources. This approval does not buy from NPCs.',normal)
        action(w,'Approve construction','BUILD THIS SAVED COMPOSITION AT MY YARDS',b.commit,b.token>0 and not b.pending,warning)
        action(w,'Progress','CHECK CONSTRUCTION AND DELIVERY',b.status,not b.pending,normal)
    end
    local pageKey='advisor.detail'
    local nextIndex
    if step=='PURCHASE' and FOC_Procurement and not FOC_Procurement.pending and not A.saving and A.savedDraft() and A.ships then
        -- Back/Home, two rows per hull, optional own-yard action, then NPC prepare.
        nextIndex=3+2*#A.draft+(FOC_Construction and 1 or 0)
    end
    local first,last=pager(w,pageKey,#rows,{fixedRows=12,rowUnits=6,maximum=8,nextIndex=nextIndex})
    for i=first,last do rows[i]() end
end
