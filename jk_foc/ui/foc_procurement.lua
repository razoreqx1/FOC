-- Prepared native NPC purchases. MD owns the persistent permit and task witnesses.
local ffi = require('ffi')
local C = ffi.C
local P = { request=0, message='Prepare a saved fleet to review its suppliers, equipment and price.' }
FOC_Procurement=P
function P.changed() if FOC_Advisor then FOC_Advisor.changed() end end
-- UI-returned LuaIDs are not serialized numeric IDs. Never weaken A.component.
function P.uiComponent(value)
    if type(value)~='userdata' then return nil,'NPC shiptrader missing or unexpected identity type' end
    local ok,id=pcall(ConvertIDTo64Bit,value)
    if not ok then return nil,'NPC shiptrader ID conversion failed: '..tostring(id) end
    local component=FOC_Advisor.component(id)
    if not component then return nil,'NPC shiptrader identity is no longer valid' end
    return component
end
function P.diagnostic(stage,detail)
    local message='[FOC][B071][PROCUREMENT] '..stage..' '..tostring(detail)
    if message~=P.lastDiagnostic and (P.diagnosticCount or 0)<32 then
        P.lastDiagnostic=message;P.diagnosticCount=(P.diagnosticCount or 0)+1
        DebugError(message)
    end
end
function P.failure(stage,err,context)
    P.lastFailure={stage=stage,text=tostring(err),context=context or P.supplierEvidence or 'Supplier not resolved'}
    P.diagnostic(stage,P.lastFailure.context..' | '..P.lastFailure.text)
end
function P.integer(v,lo,hi)
    local n=tonumber(v)
    return n and n==n and n%1==0 and n>=lo and n<=hi and n or nil
end
function P.number(v)
    local n=tonumber(v)
    assert(n and n==n and n>=0 and n<=9000000000000,'Price or native quantity unavailable')
    return n
end
function P.taskKey(v)
    local s=tostring(v):gsub('ULL$','')
    assert(s:match('^%d+$') and s:match('[1-9]'),'Invalid native build task ID')
    return s
end
function P.money(n) return ConvertMoneyString(n,false,true,0,true,false)..' Cr' end
-- Query only a task just returned by this executor, never an old saved receipt ID.
function P.receiptObject(id,yard)
    local ok,key=pcall(function()
        local info=C.GetBuildTaskInfo(id)
        if P.taskKey(info.id)~=P.taskKey(id) then return '' end
        local object=FOC_Advisor.component(info.component)
        local builder=FOC_Advisor.component(info.buildingcontainer)
        if not object or not builder or tostring(builder)~=tostring(yard) then return '' end
        return tostring(object)
    end)
    return ok and key or ''
end
-- Diagnostic observer only: never normalize a report or grant purchase/bind authority.
function P.reportEvidence(s)
    local issues={}
    local function value(v)
        local t=type(v)
        if t=='string' or t=='number' or t=='boolean' then
            return t..'='..tostring(v):gsub('[%c]',' '):sub(1,48)
        end
        return t -- Do not stringify/dereference native objects or metatables.
    end
    local function check(ok,label,v)
        if not ok and #issues<6 then issues[#issues+1]=label..'('..value(v)..')' end
    end
    for _,f in ipairs({'token','revision','template','total','expected','done','submitted','approved','overflow','allow','entrycount','receiptcount','count','reportedpaid'})do
        check(P.integer(s[f],0,9000000000000),f,s[f])
    end
    for _,f in ipairs({'done','approved','overflow','allow'})do check(P.integer(s[f],0,1),f..'.flag',s[f]) end
    for _,f in ipairs({'expected','submitted'})do check(P.integer(s[f],0,100),f..'.bound',s[f]) end
    for _,f in ipairs({'home','state'})do check(type(s[f])=='string',f,s[f]) end
    for _,f in ipairs({'reason','detail'})do check(s[f]==nil or type(s[f])=='string',f,s[f]) end
    for _,spec in ipairs({{'entries','entrycount',tonumber(s.protocol)==3 and 100 or 8},{'receipts','receiptcount',100},{'rows','count',100}})do
        local list=s[spec[1]]
        check(tonumber(s[spec[2]])==#list,spec[2]..'/actual='..#list,s[spec[2]])
        check(#list<=spec[3],spec[1]..'.bound',#list)
        for i=1,math.min(#list,100)do
            local r=list[i];local label=spec[1]..'['..i..'].'
            if spec[1]=='entries'then
                for _,f in ipairs({'macro','yard'})do check(type(r[f])=='string',label..f,r[f])end
                check(P.integer(r.amount,1,100),label..'amount',r.amount)
                check(P.integer(r.price,tonumber(s.protocol)==3 and r.route=='OWNED' and 0 or 1,9000000000000),label..'price',r.price)
            elseif spec[1]=='receipts'then
                check(type(r.key)=='string' and r.key:match('^%d+$'),label..'key',r.key)
                check(P.integer(r.entry,1,tonumber(s.protocol)==3 and 100 or 8),label..'entryindex',r.entryindex)
            else
                for _,f in ipairs({'macro','yard','state'})do check(type(r[f])=='string',label..f,r[f])end
                if tonumber(s.protocol)~=2 and tonumber(s.protocol)~=3 then check(type(r.task)=='userdata',label..'task',r.task) end
                for _,f in ipairs({'price','paid'})do check(tonumber(r[f]),label..f,r[f])end
            end
        end
    end
    check(not s.item,'unfinished.'..tostring(s.kind),s.item and s.item.id)
    check(not s.invalid,'framing/row-validation',s.invalid)
    local reason=issues[1] or 'unclassified validation failure'
    local detail='request='..value(s.request)..' token='..value(s.token)..' revision='..value(s.revision)..' | '..table.concat(issues,'; ')
    return reason:sub(1,110),detail:sub(1,1100)
end
function P.send(kind,values,quote)
    if P.pending or P.executing then return false end
    P.request=P.request+1
    local packet={P.request};for _,v in ipairs(values or {})do packet[#packet+1]=v end
    P.pending={kind=kind,quote=quote,time=getElapsedTime(),request=P.request};P.stage=nil
    if kind=='recoverreview' or kind=='recover' then P.pending.token=values[1];P.pending.revision=values[2] end
    if kind=='reserve' then
        local fields={}
        for i,v in ipairs(packet)do fields[#fields+1]=i..':'..type(v)..'='..tostring(v):sub(1,96) end
        P.diagnostic('RESERVE_PACKET',table.concat(fields,' | '))
    end
    AddUITriggeredEvent('FOC_Procurement',kind,packet)
    return true
end
function P.status(token) return P.send('status',{token or P.token or 0}) end
function P.supplier(e)
    local a=FOC_Advisor
    local yard=a.component(e.yard)
    assert(yard,'Supplier unavailable')
    local owned,trader=GetComponentData(yard,'isplayerowned','shiptrader')
    P.supplierEvidence='yard='..tostring(e.yard)..' | hull='..tostring(e.macro)..' | owned='..tostring(owned)..' | trader_type='..type(trader)
    assert(e.route=='OWNED' and owned==true or e.route~='OWNED' and owned==false,'Supplier ownership changed or unavailable')
    local traderID,reason=P.uiComponent(trader)
    assert(traderID,reason)
    P.supplierEvidence=P.supplierEvidence..' | trader_id='..tostring(traderID)
    local allowed,reason=a.eligibility(e.macro,yard,e.route=='OWNED')
    assert(allowed,reason or 'Hull permission unavailable')
    assert(C.IsComponentOperational(yard) and C.HasSuitableBuildModule(yard,0,e.macro) and C.CanGenerateValidLoadout(yard,e.macro),'Supplier cannot build this hull')
    local n=P.integer(C.GetNumContainerBuilderMacros(yard),1,2048)
    assert(n,'Supplier hull catalogue unavailable')
    local buf=ffi.new('const char*[?]',n)
    assert(tonumber(C.GetContainerBuilderMacros(buf,n,yard))==n,'Supplier catalogue changed')
    local found=false;for i=0,n-1 do if ffi.string(buf[i])==e.macro then found=true end end
    assert(found,'Supplier no longer sells this hull')
    return yard
end
-- Inspect the actual serialized loadout once per category, including grouped equipment.
function P.wares(loadout)
    local rows={}
    local function add(ware,n,software)
        assert(type(ware)=='string' and ware~='','Equipment ware unavailable')
        n=assert(P.integer(n,1,100000),'Equipment count unavailable')
        local key=(software and 'S:' or 'M:')..ware
        if rows[key] then rows[key].amount=rows[key].amount+n
        else rows[key]={ware=ware,amount=n,software=software==true} end
    end
    for _,cat in ipairs({'engines','shields','weapons','turrets','turretgroups','shieldgroups','ammo','units','software'})do
        local n=assert(P.integer(loadout['num'..cat],0,4096),'Loadout exceeds equipment bound')
        for i=0,n-1 do
            local v=loadout[cat][i]
            if cat=='software' then add(ffi.string(v.ware),1,true)
            else
                local macro=ffi.string(v.macro)
                local amount=1
                if cat=='ammo' or cat=='units' then amount=v.amount
                elseif cat=='turretgroups' or cat=='shieldgroups' then amount=v.count end
                if macro~='' and tonumber(amount)>0 then add(GetMacroData(macro,'ware'),amount,false) end
            end
        end
    end
    assert(tonumber(loadout.numengines)>0 and ffi.string(loadout.thruster.macro)~='','Engine or thruster missing')
    add(GetMacroData(ffi.string(loadout.thruster.macro),'ware'),1,false)
    local list={};for _,r in pairs(rows)do list[#list+1]=r end
    assert(#list<=512,'Equipment catalogue exceeds review bound')
    table.sort(list,function(a,b)return a.ware<b.ware end)
    return list
end
function P.price(e)
    local yard=P.supplier(e)
    local n=assert(P.integer(C.GetNumAvailableEquipment(yard,''),1,8192),'Supplier equipment unavailable')
    local buf=ffi.new('EquipmentWareInfo[?]',n)
    assert(tonumber(C.GetAvailableEquipment(buf,n,yard,''))==n,'Equipment catalogue changed')
    local available={};for i=0,n-1 do available[ffi.string(buf[i].ware)]=true end
    if e.route=='OWNED' then
        local priced={}
        for _,w in ipairs(e.wares)do
            assert(available[w.ware],'Equipment unavailable at your yard: '..w.ware)
            priced[#priced+1]={ware=w.ware,amount=w.amount,software=w.software,price=0}
        end
        return 0,priced,0 -- Native owned-yard resources, never a zero-priced NPC purchase.
    end
    local discounts=GetComponentData(yard,'discounts')
    assert(type(discounts)=='table' and #discounts<=128,'Supplier discount unavailable')
    local factor=1
    for _,d in ipairs(discounts)do if d.applytoshipsales then factor=factor-P.number(d.amount)/100 end end
    assert(factor>=0,'Invalid supplier discount')
    local hullware=GetMacroData(e.macro,'ware')
    assert(type(hullware)=='string' and hullware~='','Hull ware missing')
    local hull=P.number(C.GetBuildWarePrice(yard,hullware))
    local total=hull
    local priced={}
    for _,w in ipairs(e.wares)do
        assert(available[w.ware],'Equipment no longer sold: '..w.ware)
        local price
        if w.software then
            price=factor*P.number(C.GetContainerBuildPriceFactor(yard))*P.number(GetContainerWarePrice(yard,w.ware,false))
        else
            local volatile=GetWareData(w.ware,'volatile')
            assert(type(volatile)=='boolean','Equipment price classification unavailable')
            price=volatile and 0 or P.number(C.GetBuildWarePrice(yard,w.ware))
        end
        total=total+w.amount*price
        priced[#priced+1]={ware=w.ware,amount=w.amount,software=w.software,price=price}
    end
    total=P.number(RoundTotalTradePrice(total))
    assert(total>0,'NPC quote must have a positive price')
    return total,priced,hull
end
function P.loadoutValid(e,id)
    assert(type(id)=='string' and id~='','Select a saved loadout')
    local yard=P.supplier(e)
    assert(C.IsLoadoutCompatible(e.macro,id),'Saved loadout does not fit this ship')
    local invalid=ffi.new('uint32_t[?]',1)
    assert(C.IsLoadoutValid(0,e.macro,id,invalid),'Saved loadout contains unavailable equipment')
    assert(ffi.string(C.GetMissingLoadoutBlueprints(yard,0,e.macro,id))=='','Supplier lacks loadout blueprints')
end
function P.copyPlan(value,depth)
    depth=(depth or 0)+1;assert(depth<=12,'Equipment plan nesting exceeds limit')
    if type(value)~='table' then return value end
    local result={};local count=0
    for key,v in pairs(value)do count=count+1;assert(count<=8192,'Equipment plan exceeds limit');result[key]=P.copyPlan(v,depth) end
    return result
end
function P.equipmentSlots(e)
    local result={}
    for _,kind in ipairs({'engine','shield','weapon','turret','thruster'})do
        local count=assert(P.integer(kind=='thruster' and C.GetNumVirtualUpgradeSlots(0,e.macro,kind) or C.GetNumUpgradeSlots(0,e.macro,kind),0,512),'Ship equipment slots unavailable')
        e.plan[kind]=e.plan[kind] or {}
        for i=1,count do if not e.plan[kind][i] then e.plan[kind][i]={macro='',ammomacro='',weaponmode=''} end end
    end
    for _,kind in ipairs({'engine','shield','weapon','turret','thruster','turretgroup','shieldgroup'})do
        for index,slot in pairs(e.plan[kind] or {})do
            assert(P.integer(index,1,4096) and type(slot)=='table','Unsupported equipment slot')
            result[#result+1]={kind=kind,index=index,path=slot.path,group=slot.group}
        end
    end
    assert(#result<=512,'Too many equipment slots to review')
    table.sort(result,function(a,b)if a.kind==b.kind then return a.index<b.index end;return a.kind<b.kind end)
    return result
end
function P.slotCompatible(e,slot,macro)
    if type(macro)~='string' or macro=='' then return false end
    local races=GetMacroData(macro,'makerraceid');local shipraces=GetMacroData(e.macro,'makerraceid')
    if type(races)~='table' or type(shipraces)~='table' then return false end
    for _,race in ipairs(races)do
        local same=false;for _,shiprace in ipairs(shipraces)do if shiprace==race then same=true end end
        if same then break end
        if race=='xenon' or race=='khaak' then return false end
    end
    if slot.kind=='thruster' then return C.IsVirtualUpgradeMacroCompatible(0,e.macro,'thruster',slot.index,macro) end
    if slot.kind=='turretgroup' or slot.kind=='shieldgroup' then
        if type(slot.path)~='string' or type(slot.group)~='string' then return false end
        return C.IsUpgradeGroupMacroCompatible(0,e.macro,slot.path,slot.group,slot.kind:gsub('group$',''),macro)
    end
    return C.IsUpgradeMacroCompatible(0,0,e.macro,false,slot.kind,slot.index,macro)
end
function P.slotOptions(e,slot)
    local yard=P.supplier(e)
    local n=assert(P.integer(C.GetNumAvailableEquipment(yard,''),1,8192),'Supplier equipment unavailable')
    local buf=ffi.new('EquipmentWareInfo[?]',n)
    assert(tonumber(C.GetAvailableEquipment(buf,n,yard,''))==n,'Supplier equipment changed')
    local result,seen={},{}
    local kind=slot.kind:gsub('group$','')
    for i=0,n-1 do
        if ffi.string(buf[i].type)==kind then
            local macro=ffi.string(buf[i].macro)
            if not seen[macro] and P.slotCompatible(e,slot,macro) then
                seen[macro]=true;result[#result+1]={macro=macro,name=tostring(GetMacroData(macro,'name'))}
            end
        end
    end
    assert(#result<=256,'Too many compatible equipment choices')
    table.sort(result,function(a,b)if a.name==b.name then return a.macro<b.macro end;return a.name<b.name end)
    return result
end
function P.selectEquipment(q,index,slot,macro)
    if P.pending or P.executing or not P.current(q) then return false end
    local old=q.entries[index]
    local ok,replacement=pcall(function()
        assert(old and P.slotCompatible(old,slot,macro),'Equipment does not fit this slot')
        local available=false
        for _,item in ipairs(P.slotOptions(old,slot))do if item.macro==macro then available=true end end
        assert(available,'Equipment is not available from this supplier')
        local e={};for k,v in pairs(old)do e[k]=v end
        e.plan=P.copyPlan(old.plan)
        local target=assert(e.plan[slot.kind] and e.plan[slot.kind][slot.index],'Slot no longer exists')
        assert(target.path==slot.path and target.group==slot.group,'Equipment group changed')
        target.macro=macro;target.ammomacro='';target.weaponmode=''
        e.loadoutid='';e.loadoutname='Custom equipment'
        e.equipmentEdits=P.copyPlan(old.equipmentEdits or {})
        e.equipmentEdits[slot.kind..':'..slot.index]={slot=P.copyPlan(slot),macro=macro}
        e.wares=Helper.callLoadoutFunction(e.plan,nil,P.wares,nil,'UILoadout2')
        e.price,e.priced,e.hullprice=P.price(e)
        return e
    end)
    Helper.ffiClearNewHelper()
    if not ok then P.message='Equipment unchanged: '..tostring(replacement);P.changed();return false end
    if FOC_Workup and not FOC_Workup.replace(q,index,replacement) then return false end
    q.entries[index]=replacement;q.total=0
    for _,entry in ipairs(q.entries)do q.total=q.total+entry.amount*entry.price end
    P.slotEditor=nil;P.loadoutChoices=nil;P.message='Equipment and exact price updated. No credits spent.';P.changed();return true
end
function P.savedLoadouts(e)
    local n=assert(P.integer(C.GetNumLoadoutsInfo(0,e.macro),0,256),'Too many saved loadouts; maximum256')
    local list={{id='',name='Generated medium equipment'}}
    if n>0 then
        local buf=ffi.new('UILoadoutInfo[?]',n)
        assert(tonumber(C.GetLoadoutsInfo(buf,n,0,e.macro))==n,'Saved loadout list changed; refresh')
        local seen={}
        for i=0,n-1 do
            local id=ffi.string(buf[i].id)
            assert(id~='' and not seen[id],'Invalid or duplicate saved loadout identity')
            seen[id]=true
            list[#list+1]={id=id,name=tostring(i+1)..': '..ffi.string(buf[i].name):sub(1,80)}
        end
    end
    return list
end
function P.selectLoadout(q,index,item)
    if P.pending or P.executing or not P.current(q) then return false end
    local old=q.entries[index]
    if not old or type(item)~='table' then return false end
    local ok,result=pcall(function()
        local replacement={}
        for k,v in pairs(old)do replacement[k]=v end
        replacement.loadoutid=item.id;replacement.loadoutname=item.name
        replacement.equipmentEdits=nil
        -- A native preset replaces the custom stores, not their validation state.
        replacement.customStores=false
        P.generate(replacement)
        return replacement
    end)
    Helper.ffiClearNewHelper()
    if not ok then P.message='Loadout unchanged: '..tostring(result);P.changed();return false end
    if FOC_Workup and not FOC_Workup.replace(q,index,result) then return false end
    q.entries[index]=result
    q.total=0;for _,entry in ipairs(q.entries)do q.total=q.total+entry.amount*entry.price end
    P.selectedEquipment=1;P.message='Equipment and price updated for this ship group. No credits spent.'
    P.changed();return true
end
function P.generate(e)
    local yard=P.supplier(e)
    local raw
    if e.loadoutid and e.loadoutid~='' then
        P.loadoutValid(e,e.loadoutid)
        raw=Helper.getLoadoutHelper2(C.GetLoadout2,C.GetLoadoutCounts2,'UILoadout2',0,e.macro,e.loadoutid)
    else raw=Helper.getLoadoutHelper2(C.GenerateShipLoadout2,C.GenerateShipLoadoutCounts2,'UILoadout2',yard,0,e.macro,0.5) end
    local expected=P.wares(raw)
    local software={software={}}
    local n=assert(P.integer(C.GetNumSoftwareSlots(0,e.macro),0,128),'Software slot count unavailable')
    if n>0 then
        local buf=ffi.new('SoftwareSlot[?]',n)
        assert(tonumber(C.GetSoftwareSlots(buf,n,0,e.macro))==n,'Software slots changed')
        for i=0,n-1 do software.software[#software.software+1]={maxsoftware=ffi.string(buf[i].max),currentsoftware=ffi.string(buf[i].current)} end
    end
    e.plan=Helper.convertLoadout(0,e.macro,raw,software,'UILoadout2')
    -- convertLoadout mirrors raw ammo into three editor categories. The editor
    -- subsequently filters them; this adapter serializes that raw list only once.
    e.plan.deployable={};e.plan.countermeasure={};e.plan.crew={};e.plan.hascrewexperience=false
    e.wares=Helper.callLoadoutFunction(e.plan,nil,P.wares,nil,'UILoadout2')
    assert(#expected==#e.wares,'Generated equipment was not preserved')
    for i,w in ipairs(expected)do
        local actual=e.wares[i]
        assert(w.ware==actual.ware and w.amount==actual.amount and w.software==actual.software,'Generated equipment serialization changed')
    end
    e.price,e.priced,e.hullprice=P.price(e)
end
function P.checkCrew(e)
    local count=(e.marines or 0)+(e.service or 0)
    assert(P.integer(e.marines or 0,0,100) and P.integer(e.service or 0,0,100),'Invalid Academy crew quantity')
    if count>0 then
        local capacity=assert(P.integer(C.GetPeopleCapacity(0,e.macro,false),0,100000),'Ship crew capacity unavailable')
        assert(count<=capacity,'This ship cannot carry the requested crew')
    end
end
function P.prepare(route)
    local a=FOC_Advisor
    if P.pending or P.executing or a.saving then return false end
    local t=a.savedDraft();local home=a.selected and a.component(a.selected.id)
    if not t or not home then a.status='Save the exact fleet and Home before preparing a purchase.';return false end
    P.supplierEvidence=nil
    local ok,q=pcall(function()
        assert(#t.entries>=1 and #t.entries<=8,'Fleet entry limit exceeded')
        local quote={schema=(route=='MIXED' or route=='OWNED') and 3 or 2,route=route,composition={},template=t.id,shipyard=tonumber(t.shipyard)==1,supportmacro=t.supportmacro or '',home=tostring(home),homename=a.selected.name,name=t.name,entries={},total=0,count=0,time=getElapsedTime()}
        local assigned={}
        for _,entry in ipairs(t.entries)do
            local row;for _,r in ipairs(a.ships or {})do if r.macro==entry.macro then row=r;break end end
            local own=row and (route=='OWNED' or route=='MIXED' and not row.npcyard) and row.ownyard
            assert(row and (row.npcyard or own),(row and row.name or entry.macro)..': '..(row and row.npcreason or 'Ship catalogue missing; refresh suppliers before purchase'))
            assert(route~='OWNED' or own,'No eligible player yard for '..entry.macro)
            local amount=assert(P.integer(entry.amount,1,100),'Invalid quantity')
            quote.composition[#quote.composition+1]={macro=entry.macro,amount=amount}
            local allocations={}
            if own then
                local yards=row.ownyards or {{id=own,name=row.ownname}}
                assert(#yards>0 and #yards<=128,'Owned yard list exceeds bounds')
                local byyard={}
                for unit=1,amount do
                    local best
                    for _,yard in ipairs(yards)do
                        if not best or (assigned[yard.id] or 0)<(assigned[best.id] or 0) then best=yard end
                    end
                    assigned[best.id]=(assigned[best.id] or 0)+1
                    local allocation=byyard[best.id]
                    if not allocation then allocation={yard=best.id,yardname=best.name,amount=0};byyard[best.id]=allocation;allocations[#allocations+1]=allocation end
                    allocation.amount=allocation.amount+1
                end
            else allocations[1]={yard=row.npcyard,yardname=row.npcname,amount=amount} end
            for _,allocation in ipairs(allocations)do
                local e={route=own and 'OWNED' or 'NPC',macro=entry.macro,amount=allocation.amount,yard=tostring(allocation.yard),yardname=allocation.yardname,name=row.name}
                P.generate(e);if FOC_Workup then FOC_Workup.restore(e,t.workup) end;quote.entries[#quote.entries+1]=e
                quote.total=quote.total+e.amount*e.price;quote.count=quote.count+e.amount
            end
        end
        assert(quote.count<=100 and (quote.schema==3 or P.number(quote.total)>0),'Fleet exceeds purchase bound')
        return quote
    end)
    Helper.ffiClearNewHelper()
    a.go('PROCUREMENT')
    if ok then P.quote=q;P.selectedEntry=1;P.selectedEquipment=1;P.lastFailure=nil;P.message='Prepared for review. No credits spent.';P.diagnostic('PREPARED',P.supplierEvidence..' | count='..q.count..' | total='..q.total)
    else P.quote=nil;P.message='Cannot prepare purchase: '..tostring(q);P.failure('PREPARE - no payment attempted by this action',q) end
    P.changed();return ok
end
function P.current(q)
    local a=FOC_Advisor;local t=a.savedDraft()
    if not q or q~=P.quote or q.used or not t or t.id~=q.template or tostring(t.home)~=q.home or a.saving then return false end
    if q.shipyard~=(tonumber(t.shipyard)==1) or q.supportmacro~=(t.supportmacro or '') then return false end
    local composition=q.composition or q.entries
    if #t.entries~=#composition then return false end
    for i,e in ipairs(composition)do if t.entries[i].macro~=e.macro or t.entries[i].amount~=e.amount then return false end end
    return getElapsedTime()>=q.time and getElapsedTime()-q.time<=120
end
function P.recheck(q)
    assert(P.current(q),'Quote expired or saved fleet/Home changed; prepare again')
    local total=0
    for _,e in ipairs(q.entries)do
        P.checkCrew(e)
        if FOC_Workup then FOC_Workup.validateStores(e) end
        if e.loadoutid and e.loadoutid~='' then P.loadoutValid(e,e.loadoutid) end
        for _,edit in pairs(e.equipmentEdits or {})do assert(P.slotCompatible(e,edit.slot,edit.macro),'Custom equipment compatibility changed') end
        local price,rows,hull=P.price(e)
        assert(price==e.price and hull==e.hullprice and #rows==#e.priced,'Supplier quote changed; prepare again')
        for i,r in ipairs(rows)do assert(r.price==e.priced[i].price,'Equipment price changed; prepare again') end
        total=total+price*e.amount
    end
    assert(total==q.total and P.number(GetPlayerMoney())>=total,'Insufficient funds for this exact quote')
end
function P.confirm(saved)
    if P.pending or P.executing then return false end
    local q=P.quote
    if FOC_Workup and not saved then return FOC_Workup.save(q,function()P.confirm(true)end) end
    local ok,packet=pcall(function()
        P.recheck(q)
        -- Lookup slots require native IDs; textual quote keys stay in the quote.
        local home=assert(FOC_Advisor.component(q.home),'Home unavailable before reservation')
        local values={q.template,home,home,q.total}
        for _,e in ipairs(q.entries)do
            local yard=assert(FOC_Advisor.component(e.yard),'Supplier unavailable before reservation')
            values[#values+1]=yard;values[#values+1]=e.macro;values[#values+1]=e.amount;values[#values+1]=e.price
            if q.schema==3 then values[#values+1]=e.route end
        end
        return values
    end)
    if not ok then P.message=tostring(packet);P.failure('CONFIRM - no payment attempted by this action',packet);P.changed();return false end
    P.message='Reserving this confirmed purchase. Waiting for persistent order protection.'
    return P.send(q.schema==3 and 'reservemixed' or 'reserve',packet,q)
end
function P.submit(q,token)
    -- Only the unique complete reserve response calls this function. Never a status/reload callback.
    local ok,err=pcall(P.recheck,q)
    q.used=true;P.executing=true
    local submitted,paid,attempted=0,0,false
    if ok then
        ok,err=pcall(function()
            for entryIndex,e in ipairs(q.entries)do
                for _=1,e.amount do
                    local yard=P.supplier(e)
                    local price=P.price(e);assert(price==e.price,'Price changed during submission')
                    local before=P.number(GetPlayerMoney());assert(before>=e.price,'Insufficient funds; remaining ships not ordered')
                    -- Build buffers are prepared before the native money transfer.
                    local id=Helper.callLoadoutFunction(e.plan,nil,function(loadout,crew)
                        local info=ffi.new('AddBuildTask6Container')
                        info.paintmodwareid=''
                        attempted=true -- BEFORE payment OR an owned resource build, including a thrown call.
                        if e.route~='OWNED' then
                            TransferPlayerMoneyTo(e.price,yard)
                            local after=P.number(GetPlayerMoney())
                            assert(after==before-e.price,'Payment readback uncertain; no further spending')
                            paid=paid+e.price
                        end
                        local task=C.AddBuildTask6(yard,0,e.macro,loadout,e.price,crew,false,'',info)
                        assert(task~=0,'Native order rejected after payment; inspect retained purchase')
                        if e.route~='OWNED' then C.SetBuildTaskTransferredMoney(task,e.price) end
                        return task
                    end,nil,'UILoadout2')
                    local key=P.taskKey(id)
                    submitted=submitted+1
                    AddUITriggeredEvent('FOC_Procurement','receipt',{token,submitted,entryIndex,key,e.price,P.receiptObject(id,yard)})
                end
            end
        end)
    end
    Helper.ffiClearNewHelper();P.executing=false
    P.token=token
    P.message=ok and 'Native orders submitted; verifying exact task IDs and payments.' or ('Purchase stopped: '..tostring(err)..(attempted and '. Do not repeat it; inspect order status.' or '. No payment attempted; check status before preparing again.'))
    if ok then P.lastFailure=nil;P.diagnostic('SUBMITTED','token='..token..' | count='..submitted..' | paid='..paid)
    else P.failure(attempted and 'SUBMIT - payment attempted; do not repeat' or 'SUBMIT - no payment attempted; check status',err) end
    AddUITriggeredEvent('FOC_Procurement','submitted',{token,submitted,paid,ok and 1 or (attempted and 0 or 2)})
    P.changed()
end
function P.resolve(s)
    if s.approved~=0 or s.done~=1 or s.submitted~=s.expected or #s.receipts~=s.expected or s.overflow~=0 then return end
    local byKey={}
    for _,r in ipairs(s.rows)do
        if (s.protocol==2 or s.protocol==3) then
            if r.receiptkey~='' then if byKey[r.receiptkey] then return end;byKey[r.receiptkey]=r end
        elseif type(r.task)=='userdata' then
            local ok,key=pcall(function()return P.taskKey(ConvertIDTo64Bit(r.task))end)
            if ok then if byKey[key] then return end;byKey[key]=r end
        end
    end
    local packet={s.token,s.revision}
    local seen={}
    for i,receipt in ipairs(s.receipts)do
        local r=byKey[receipt.key];local e=s.entries[receipt.entry]
        if not r or seen[r.id] or not e or r.macro~=e.macro or r.yard~=e.yard or r.price~=e.price or r.paid~=e.price or (r.state~='QUEUED' and r.state~='DELIVERED') then return end
        seen[r.id]=true;packet[#packet+1]=r.recordid or r.id;packet[#packet+1]=receipt.key
    end
    if P.lastBind~=s.token..':'..s.revision then
        P.lastBind=s.token..':'..s.revision
        AddUITriggeredEvent('FOC_Procurement','bind',packet)
    end
end
function P.render(w,action,text,dropdown,normal,warning)
    local a,q,s=FOC_Advisor,P.quote,P.snapshot
    local rows,metrics={},{}
    local function current()return a.step=='PROCUREMENT' and (not a.isCurrent or a.isCurrent(w))end
    local function prose(label,value,color)
        value=tostring(value);metrics[#metrics+1]={label,value}
        rows[#rows+1]=function()text(w,label,value,color or normal)end
    end
    local function button(label,value,fn,active)
        metrics[#metrics+1]={label,value}
        rows[#rows+1]=function()action(w,label,value,function()if active and current() and not P.pending and not P.executing then fn();P.changed()end end,active,warning)end
    end
    local function choice(label,values,index,fn)
        metrics[#metrics+1]={label,values[index] or ''}
        rows[#rows+1]=function()dropdown(w,label,values,values[index],function(v)
            if current() and P.quote==q and not P.pending then for i,name in ipairs(values)do if name==v then fn(i);P.changed();break end end end
            return false
        end)end
    end
    button('Back','BACK TO FLEET BUILD / BUY',function()a.go('PURCHASE')end,not P.pending)
    button('Order status','CHECK PREPARED ORDER / DELIVERY',function()P.status()end,not P.pending)
    if P.lastFailure then
        local failure=P.lastFailure
        prose('Error / report',failure.stage..' | '..failure.context..'\n'..failure.text..'\nFOC could not complete this step. Please take a screenshot of this entire page and report it to the developer.',warning)
    else prose('Status',P.message) end
    if q and not q.used and FOC_Workup and FOC_Workup.editing==q then
        FOC_Workup.render(q,prose,button,choice)
    elseif q and not q.used then
        prose('Fleet / Home',q.count..' ships | '..tostring(q.name)..' | '..tostring(q.homename))
        prose('Total purchase price',P.money(q.total))
        local options={};for i,e in ipairs(q.entries)do options[i]=i..': '..e.amount..' x '..tostring(e.name):sub(1,70) end
        local ix=P.selectedEntry or 1;local e=q.entries[ix] or q.entries[1]
        choice('Inspect ship',options,ix,function(i)P.selectedEntry=i;P.selectedEquipment=1 end)
        prose('Supplier / ship price',e.route=='OWNED' and tostring(e.yardname)..' | BUILD using your yard resources; no credit charge' or tostring(e.yardname)..' | '..P.money(e.hullprice)..' ship; '..P.money(e.price)..' equipped, each')
        local equipment={};for i,v in ipairs(e.priced)do equipment[i]=i..': '..v.amount..' x '..tostring(GetWareData(v.ware,'name')):sub(1,70) end
        local wi=math.min(P.selectedEquipment or 1,#equipment)
        if wi>0 then
            choice('Inspect equipment',equipment,wi,function(i)P.selectedEquipment=i end)
            local v=e.priced[wi];prose('Equipment detail',v.ware..' | '..v.amount..' x '..P.money(v.price)..' per ship')
        end
        button('Equipment','EDIT EQUIPMENT / CREW / SAVED LOADOUT',function()
            if FOC_Workup then FOC_Workup.editing=q;return end
            local ok,list=pcall(P.savedLoadouts,e)
            Helper.ffiClearNewHelper()
            if ok then P.loadoutChoices={quote=q,entry=e,list=list} else P.message=tostring(list) end
            local slotsOK,slots=pcall(P.equipmentSlots,e)
            if slotsOK then P.slotEditor={quote=q,entry=e,slots=slots,index=1} else P.message=tostring(slots) end
            local capacityOK,capacity=pcall(function()return assert(P.integer(C.GetPeopleCapacity(0,e.macro,false),0,100000),'Crew capacity unavailable')end)
            if capacityOK then P.crewEditor={quote=q,entry=e,capacity=capacity} else P.message=tostring(capacity) end
        end,P.current(q) and not P.pending)
        local presets=P.loadoutChoices
        if presets and presets.quote==q and presets.entry==e then
            local names,selected={},1
            for i,item in ipairs(presets.list)do names[i]=item.name;if item.id==(e.loadoutid or '')then selected=i end end
            choice('Saved loadout',names,selected,function(i)
                if P.selectLoadout(q,ix,presets.list[i]) then P.loadoutChoices=nil end
            end)
        end
        local crew=P.crewEditor
        if crew and crew.quote==q and crew.entry==e then
            prose('Crew capacity',crew.capacity..' places excluding the native captain; Academy supplies selected crew.')
            local amounts={};for i=0,math.min(100,crew.capacity)do amounts[#amounts+1]=tostring(i) end
            choice('Academy marines',amounts,(e.marines or 0)+1,function(i)
                if i-1+(e.service or 0)<=crew.capacity and P.current(q) then e.marines=i-1 end
            end)
            choice('Academy service crew',amounts,(e.service or 0)+1,function(i)
                if i-1+(e.marines or 0)<=crew.capacity and P.current(q) then e.service=i-1 end
            end)
            if FOC_Workup then button('Save workup','SAVE EQUIPMENT AND CREW TO TEMPLATE',function()FOC_Workup.save(q)end,P.current(q) and not P.pending) end
        end
        local editor=P.slotEditor
        if editor and editor.quote==q and editor.entry==e and #editor.slots>0 then
            local names={};for i,slot in ipairs(editor.slots)do names[i]=i..': '..slot.kind..' '..slot.index end
            choice('Equipment slot',names,editor.index,function(i)editor.index=i;editor.options=nil end)
            button('Compatible equipment','SHOW COMPATIBLE EQUIPMENT',function()
                local ok,list=pcall(P.slotOptions,e,editor.slots[editor.index])
                Helper.ffiClearNewHelper()
                if ok then editor.options=list else P.message=tostring(list) end
            end,P.current(q) and not P.pending)
            if editor.options and #editor.options>0 then
                local labels={'Choose equipment'}
                for i,item in ipairs(editor.options)do labels[i+1]=i..': '..item.name:sub(1,80) end
                choice('Fit equipment',labels,1,function(i)
                    if i>1 then P.selectEquipment(q,ix,editor.slots[editor.index],editor.options[i-1].macro) end
                end)
            end
        end
        prose('Loadout / crew',(e.loadoutname or 'Generated medium equipment')..'. Native captain included; extra crew and paint are not imported from saved loadouts.')
        prose('After confirmation',q.shipyard and 'Buy once, attach escorts and optional supply ship, then gather at the assembly sector and wait. Choose Home and mission later in Fleets. No supply cargo is purchased; changed ship orders block assembly.' or 'X4 may queue for materials. FOC tracks these exact orders and assembles the fleet for Home patrol after delivery, if ship orders remain unchanged.')
        button('Purchase fleet','CONFIRM PURCHASE: '..q.count..' SHIPS FOR '..P.money(q.total),function()if P.quote==q and P.current(q)then P.confirm()end end,P.current(q) and not P.pending)
        button('Change / expired quote','PREPARE A FRESH QUOTE',function()P.prepare(q.route)end,not P.pending)
    elseif s and s.token>0 then
        prose('Retained order','Job '..s.token..' | '..s.submitted..' / '..s.expected..' orders reported | '..P.money(s.total)..' quoted')
        prose('Confirmed debit readback',P.money(s.reportedpaid)..'. An interrupted or uncertain transfer is not included; inspect X4 balance and orders before acting.')
        prose('Native verification',s.state)
        if (s.protocol==2 or s.protocol==3) and #s.rows>0 then
            local ships={};for i,r in ipairs(s.rows)do ships[i]=i..': '..r.shiplabel..' | '..r.state end
            local ix=math.min(P.selectedShip or 1,#ships)
            choice('Retained ships',ships,ix,function(i)if P.snapshot==s then P.selectedShip=i end end)
            local r=s.rows[ix];prose('Retained ship detail',r.macro..' | record '..r.recordid..' | '..r.shiplabel)
        end
        if (s.protocol==2 or s.protocol==3) and s.approved==0 then
            prose('Recovery',s.recoveryreason,warning)
            if s.recoveryready==1 and P.recoveryView==s then
                prose('Before recovery','Confirm these retained ships as this fleet. Missing order history may be reconciled only for idle Hold Position with an empty queue. You approve replacing that reviewed idle state; no second payment or purchase. Changes after review block assembly.',warning)
                button('Recover fleet','-> CONFIRM RECOVERY: '..#s.rows..' RETAINED SHIPS - NO CHARGE',function()
                    if P.snapshot==s and P.recoveryView==s then P.recoveryView=nil;P.send('recover',{s.token,s.revision}) end
                end,not P.pending)
            else
                button('Recovery review','-> REVIEW RETAINED FLEET RECOVERY - NO CHARGE',function()
                    if P.snapshot==s then P.recoveryView=nil;P.send('recoverreview',{s.token,s.revision}) end
                end,not P.pending)
            end
        end
        prose('Next step','Submitted orders continue in X4 with this menu closed. CHECK reads status only. A partial or uncertain purchase must not be repeated.')
        if s.approved==1 then button('Fleet delivery','VIEW VERIFIED PURCHASES / FLEET DELIVERY',function()a.go('NPC');FOC_NPC_Purchases.status(s.token)end,true)end
    else
        prose('Retained order','No retained order was returned. This is not a payment receipt.',warning)
        prose('Next step',P.lastFailure and 'Report this screenshot, then return to Fleet Build / Buy to review the supplier. Do not repeat an uncertain purchase.' or 'Return to Fleet Build / Buy to verify the saved fleet, Home and supplier before preparing.',warning)
    end
    if not a.fitReview or not a.fitReview(#rows,metrics)then
        action(w,'Back','BACK TO FLEET BUILD / BUY',function()if current()then a.go('PURCHASE');P.changed()end end,true,normal)
        text(w,'Review cannot fit','Increase window size or reduce UI scale. This view cannot confirm a purchase; existing orders are unchanged.',warning)
        return
    end
    for _,draw in ipairs(rows)do draw()end
end
function P.tick()
    if P.pending and getElapsedTime()-P.pending.time>20 then
        if P.pending.kind=='workup' then
            P.pending=nil;if FOC_Workup then FOC_Workup.pending=nil end
            P.message='Workup save response timed out. No purchase was submitted; review the template before confirming.';P.changed();return
        end
        if P.pending.quote then P.pending.quote.used=true end
        P.pending=nil;P.stage=nil
        P.message='Purchase response timed out. Check retained order status before doing anything else; no automatic retry.'
        P.failure('READBACK - purchase state uncertain; do not repeat',P.message)
        P.changed()
    end
end
RegisterEvent('FOC_Procurement.begin',function(_,v)
    local id=P.integer(v,0,9007199254740991)
    if not id or (id~=0 and (not P.pending or id~=P.pending.request))then P.stage=nil;return end
    P.stage={request=id,entries={},receipts={},rows={},invalid=false}
    P.probeRequest=nil
    -- Retired B070 native-ID probe: saved task IDs must not be queried after reload.
end)
for _,f in ipairs({'token','revision','template','home','total','expected','state','done','submitted','approved','overflow','allow','entrycount','receiptcount','count','reportedpaid','reason','detail','protocol','recoveryready','recoveryreason'})do
    RegisterEvent('FOC_Procurement.'..f,function(_,v)local s=P.stage;if not s then return end;if s[f]~=nil then s.invalid=true end;s[f]=v end)
end
for _,kind in ipairs({'entry','receipt','row'})do
    RegisterEvent('FOC_Procurement.'..kind,function(_,v)
        local s=P.stage;if not s then return end
        local list=kind=='entry' and s.entries or kind=='receipt' and s.receipts or s.rows
        if s.item or not P.integer(v,1,100) or tonumber(v)~=#list+1 then s.invalid=true;return end
        s.item={id=tonumber(v)};s.kind=kind
    end)
end
for _,f in ipairs({'macro','yard','amount','price','key','entryindex','task','paid','rowstate','recordid','receiptkey','shiplabel','route'})do
    RegisterEvent('FOC_Procurement.field.'..f,function(_,v)
        local s=P.stage;if not s then return end
        if not s.item or s.item[f]~=nil then s.invalid=true;return end;s.item[f]=v
    end)
end
RegisterEvent('FOC_Procurement.commit',function()
    local s=P.stage;if not s or not s.item then if s then s.invalid=true end;return end
    local r=s.item;s.item=nil
    if s.kind=='entry'then
        if type(r.macro)~='string' or type(r.yard)~='string' or not P.integer(r.amount,1,100) or not P.integer(r.price,tonumber(s.protocol)==3 and r.route=='OWNED' and 0 or 1,9000000000000)then s.invalid=true end
        if tonumber(s.protocol)==3 and (r.route~='OWNED' and r.route~='NPC' or r.route=='OWNED' and tonumber(r.price)~=0)then s.invalid=true end
        r.amount=tonumber(r.amount);r.price=tonumber(r.price);s.entries[#s.entries+1]=r
    elseif s.kind=='receipt'then
        r.entry=tonumber(r.entryindex)
        if type(r.key)~='string' or not r.key:match('^%d+$') or not P.integer(r.entry,1,tonumber(s.protocol)==3 and 100 or 8)then s.invalid=true end
        s.receipts[#s.receipts+1]=r
    else
        r.state=r.rowstate;r.price=tonumber(r.price);r.paid=tonumber(r.paid)
        local identity=type(r.task)=='userdata'
        if (tonumber(s.protocol)==2 or tonumber(s.protocol)==3) then
            r.recordid=P.integer(r.recordid,1,100)
            identity=r.recordid and type(r.receiptkey)=='string' and (r.receiptkey=='' or r.receiptkey:match('^[1-9]%d*$')) and type(r.shiplabel)=='string'
            for _,old in ipairs(s.rows)do if old.recordid==r.recordid then identity=false end end
        end
        if type(r.macro)~='string' or type(r.yard)~='string' or type(r.state)~='string' or not identity or not r.price or not r.paid then s.invalid=true end
        s.rows[#s.rows+1]=r
    end
end)
RegisterEvent('FOC_Procurement.complete',function()
    local s=P.stage;if not s then return end;P.stage=nil
    local diagnosticReason,diagnosticDetail=P.reportEvidence(s)
    local pending
    if s.request~=0 then pending=P.pending;P.pending=nil end
    for _,f in ipairs({'token','revision','template','total','expected','done','submitted','approved','overflow','allow','entrycount','receiptcount','count','reportedpaid'})do
        s[f]=P.integer(s[f],0,9000000000000);if not s[f]then s.invalid=true end
    end
    for _,f in ipairs({'done','approved','overflow','allow'})do if not P.integer(s[f],0,1)then s.invalid=true end end
    if s.protocol~=nil then
        s.protocol=P.integer(s.protocol,2,3)
        s.recoveryready=P.integer(s.recoveryready,0,1)
        if not s.protocol or not s.recoveryready or type(s.recoveryreason)~='string' then s.invalid=true end
    end
    -- Optional appended diagnostics support older reports; never grant permission.
    for _,f in ipairs({'reason','detail'})do
        if s[f]==nil then s[f]='' end
        if type(s[f])~='string' then s.invalid=true end
    end
    if not P.integer(s.expected,0,100) or not P.integer(s.submitted,0,100)then s.invalid=true end
    if s.invalid or s.item or type(s.home)~='string' or type(s.state)~='string' or s.entrycount~=#s.entries or s.receiptcount~=#s.receipts or s.count~=#s.rows or #s.entries>(s.protocol==3 and 100 or 8) or #s.receipts>100 or #s.rows>100 then
        if pending and pending.quote then pending.quote.used=true end
        P.message='Incomplete purchase readback. Previous evidence retained; no automatic purchase retry.'
        P.diagnostic('READBACK_FIELDS',diagnosticDetail)
        P.failure('READBACK - purchase state uncertain; do not repeat',P.message..' Field: '..diagnosticReason)
        P.changed();return
    end
    P.snapshot=s;P.message=s.state;P.recoveryView=nil;if s.token>0 then P.token=s.token end
    if (s.protocol==2 or s.protocol==3) and s.token>0 and P.lastFailure and P.lastFailure.stage:find('READBACK',1,true)==1 then P.lastFailure=nil end
    if pending and pending.kind=='recoverreview' and (s.protocol==2 or s.protocol==3) and s.recoveryready==1 and pending.token==s.token and pending.revision==s.revision then P.recoveryView=s end
    if pending and (pending.kind=='reserve' or pending.kind=='reservemixed') and pending.quote then
        local q=pending.quote
        local same=(q.schema~=3 or s.protocol==3) and s.reason=='' and s.allow==1 and s.token>0 and s.revision==1 and s.done==0 and s.submitted==0 and s.reportedpaid==0 and s.approved==0 and s.overflow==0 and #s.receipts==0 and #s.rows==0 and s.template==q.template and s.home==q.home and s.total==q.total and s.expected==q.count and #s.entries==#q.entries
        for i,e in ipairs(q.entries)do local r=s.entries[i];if not r or r.yard~=e.yard or r.macro~=e.macro or r.amount~=e.amount or r.price~=e.price or q.schema==3 and r.route~=e.route then same=false end end
        if same then P.submit(q,s.token)
        else
            q.used=true
            local reason=s.reason~='' and s.reason or 'Reservation returned no matching purchase permission; exact failed check unavailable.'
            P.message=reason
            P.failure(s.allow==0 and 'RESERVATION REFUSED - this confirmation did not attempt payment' or 'RESERVATION READBACK MISMATCH - do not repeat',reason,s.detail~='' and s.detail or nil)
        end
    else
        P.resolve(s)
    end
    P.changed()
end)
