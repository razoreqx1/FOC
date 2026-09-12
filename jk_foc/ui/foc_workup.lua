-- Persistent, bounded data only. Never evaluate saved text as Lua.
local ffi=require('ffi')
local W={}
FOC_Workup=W
function W.catalogue(e)
    local P=FOC_Procurement;local C=ffi.C;local yard=P.supplier(e)
    local n=assert(P.integer(C.GetNumAvailableEquipment(yard,''),1,8192),'Equipment catalogue unavailable')
    local buf=ffi.new('EquipmentWareInfo[?]',n);assert(tonumber(C.GetAvailableEquipment(buf,n,yard,''))==n,'Equipment catalogue changed')
    local list,byMacro={},{}
    for i=0,n-1 do
        local item={kind=ffi.string(buf[i].type),macro=ffi.string(buf[i].macro),ware=ffi.string(buf[i].ware)}
        list[#list+1]=item;if item.macro~='' then byMacro[item.macro]=item end
    end
    return list,byMacro
end
function W.ammoCompatible(e,kind,macro)
    local C=ffi.C
    if kind=='missile' then
        for _,k in ipairs({'weapon','turret','turretgroup'})do for _,slot in pairs(e.plan[k] or {})do
            if slot.macro~='' and C.IsAmmoMacroCompatible(slot.macro,macro) then return true end
        end end
        return false
    elseif kind=='drone' then return C.IsUnitMacroCompatible(0,e.macro,macro)
    elseif kind=='deployable' then return C.IsDeployableMacroCompatible(0,e.macro,macro)
    elseif kind=='countermeasure' then return C.GetDefaultCountermeasureStorageCapacity(e.macro)>0 end
    return false
end
function W.ammoCapacity(e,kind)
    local C=ffi.C;local P=FOC_Procurement;local cap
    if kind=='missile' then
        cap=P.number(C.GetDefaultMissileStorageCapacity(e.macro))
        for _,k in ipairs({'weapon','turret','turretgroup'})do for _,s in pairs(e.plan[k] or {})do
            if s.macro~='' then cap=cap+P.number(C.GetMacroMissileCapacity(s.macro))*(k=='turretgroup' and s.count or 1) end
        end end
    elseif kind=='drone' then cap=GetMacroUnitStorageCapacity(e.macro)
    elseif kind=='deployable' then cap=C.GetMacroDeployableCapacity(e.macro)
    elseif kind=='countermeasure' then cap=C.GetDefaultCountermeasureStorageCapacity(e.macro) end
    return assert(P.integer(cap,0,100000),'Storage capacity unavailable')
end
function W.normaliseAmmo(e)
    local _,catalogue=W.catalogue(e);local plans={missile={},drone={},deployable={},countermeasure={}}
    for kind,plan in pairs(plans)do for macro,amount in pairs(e.plan[kind] or {})do
        local item=assert(catalogue[macro],'Stored ammunition no longer available')
        assert(plans[item.kind],'Unknown ammunition category')
        assert(not plans[item.kind][macro] or plans[item.kind][macro]==amount,'Conflicting ammunition quantities')
        plans[item.kind][macro]=amount
    end end
    for kind,plan in pairs(plans)do e.plan[kind]=plan end
end
function W.validateStores(e)
    if not e.customStores then return end
    local _,catalogue=W.catalogue(e);local P=FOC_Procurement
    for _,kind in ipairs({'missile','drone','deployable','countermeasure'})do
        local used=0
        for macro,amount in pairs(e.plan[kind] or {})do
            assert(P.integer(amount,0,100000),'Invalid ammunition amount')
            local item=assert(catalogue[macro],'Ammunition unavailable')
            assert(item.kind==kind and (amount==0 or W.ammoCompatible(e,kind,macro)),'Ammunition does not fit ship equipment')
            used=used+amount*(kind=='missile' and P.number(GetWareData(item.ware,'volume')) or 1)
        end
        assert(used<=W.ammoCapacity(e,kind),'Ship ammunition capacity exceeded')
    end
end
function W.selectAmmo(q,index,item,amount)
    local P=FOC_Procurement;if P.pending or P.executing or not P.current(q) then return false end
    local ok,result=pcall(function()
        local e=P.copyPlan(q.entries[index]);W.normaliseAmmo(e)
        assert(e.plan[item.kind] and W.ammoCompatible(e,item.kind,item.macro),'Unsupported ammunition')
        e.plan[item.kind][item.macro]=assert(P.integer(amount,0,100000),'Invalid amount');e.customStores=true
        e.loadoutid='';e.loadoutname='Custom equipment';return e
    end)
    if not ok then P.message=tostring(result);return false end
    return W.replace(q,index,result)
end
function W.softwareOptions(e)
    local C=ffi.C;local P=FOC_Procurement;local list=W.catalogue(e)
    local n=assert(P.integer(C.GetNumSoftwareSlots(0,e.macro),0,128),'Software slots unavailable')
    local buf=ffi.new('SoftwareSlot[?]',n);assert(tonumber(C.GetSoftwareSlots(buf,n,0,e.macro))==n,'Software slots changed')
    local result={}
    for slot=1,n do
        local max=ffi.string(buf[slot-1].max)
        for _,item in ipairs(list)do if item.kind=='software' and ffi.string(C.GetSoftwareMaxCompatibleVersion(0,e.macro,item.ware))==max then result[#result+1]={slot=slot,ware=item.ware,name=item.ware} end end
    end
    assert(#result<=256,'Too many software choices');return result
end
function W.selectSoftware(q,index,item)
    local P=FOC_Procurement;if P.pending or P.executing or not P.current(q) then return false end
    local e=P.copyPlan(q.entries[index]);local valid=false
    for _,o in ipairs(W.softwareOptions(e))do if o.slot==item.slot and o.ware==item.ware then valid=true end end
    if not valid then return false end
    e.plan.software[item.slot]=item.ware;e.loadoutid='';e.loadoutname='Custom equipment'
    return W.replace(q,index,e)
end
function W.replace(q,index,replacement)
    local P=FOC_Procurement;local prepared={}
    if P.pending or P.executing or not P.current(q) or not q.entries[index] or q.entries[index].macro~=replacement.macro then return false end
    local ok,err=pcall(function()
        for i,old in ipairs(q.entries)do
            if old.macro==replacement.macro then
                local e={};for k,v in pairs(old)do e[k]=v end
                for _,k in ipairs({'plan','equipmentEdits','loadoutid','loadoutname','marines','service','customStores'})do e[k]=P.copyPlan(replacement[k]) end
                P.checkCrew(e)
                W.validateStores(e)
                if e.loadoutid and e.loadoutid~='' then P.loadoutValid(e,e.loadoutid) end
                for _,edit in pairs(e.equipmentEdits or {})do assert(P.slotCompatible(e,edit.slot,edit.macro),'Equipment does not fit at every allocated yard') end
                e.wares=Helper.callLoadoutFunction(e.plan,nil,P.wares,nil,'UILoadout2')
                e.price,e.priced,e.hullprice=P.price(e);prepared[i]=e
            end
        end
    end)
    Helper.ffiClearNewHelper()
    if not ok then P.message='Workup unchanged: '..tostring(err);P.changed();return false end
    for i,e in pairs(prepared)do q.entries[i]=e end
    q.total=0;for _,e in ipairs(q.entries)do q.total=q.total+e.amount*e.price end
    P.message='Ship equipment and crew updated. No credits spent.';P.changed()
    return true
end
function W.render(q,prose,button,choice)
    local P=FOC_Procurement
    local ix=math.min(P.selectedEntry or 1,#q.entries);local e=q.entries[ix]
    local ships={};for i,item in ipairs(q.entries)do ships[i]=i..': '..item.name..' | '..item.yardname end
    choice('Ship workup',ships,ix,function(i)P.selectedEntry=i;W.slots=nil;W.loadouts=nil;W.options=nil end)
    local modes={'Equipment slots','Saved loadouts','Crew','Ammunition and drones','Software'}
    choice('Configure',modes,W.mode or 1,function(i)W.mode=i end)
    prose('Applies to',e.name..' ships in this template, across all allocated yards. Native captain included.')
    local ok,err=pcall(function()
        if (W.mode or 1)==1 then
            local slots=P.equipmentSlots(e)
            local names={};for i,slot in ipairs(slots)do names[i]=slot.kind..' '..slot.index end
            if #names>0 then
                local selected=math.min(W.slot or 1,#names)
                choice('Equipment slot',names,selected,function(i)W.slot=i;W.options=nil end)
                local options=P.slotOptions(e,slots[selected]);local labels={'Choose compatible equipment'}
                for i,item in ipairs(options)do labels[i+1]=i..': '..item.name end
                choice('Fit equipment',labels,1,function(i)if i>1 then P.selectEquipment(q,ix,slots[selected],options[i-1].macro) end end)
            else prose('Equipment','No editable equipment slots found.') end
        elseif W.mode==2 then
            local items=P.savedLoadouts(e);local labels={};local selected=1
            for i,item in ipairs(items)do labels[i]=item.name;if item.id==e.loadoutid then selected=i end end
            choice('X4 saved loadout',labels,selected,function(i)P.selectLoadout(q,ix,items[i]) end)
        elseif W.mode==4 then
            local list=W.catalogue(e);local items,labels={},{}
            for _,item in ipairs(list)do if W.ammoCompatible(e,item.kind,item.macro) then items[#items+1]=item;labels[#labels+1]=item.kind..': '..tostring(GetMacroData(item.macro,'name')) end end
            assert(#items<=256,'Too many ammunition choices')
            if #items==0 then prose('Ammunition','No compatible ammunition or drones available.') else
                local selected=math.min(W.ammo or 1,#items);local item=items[selected]
                choice('Ammunition',labels,selected,function(i)W.ammo=i end)
                local quantities={0,1,5,10,20,25,50,100,200,500,1000};local cap=W.ammoCapacity(e,item.kind)
                local volume=item.kind=='missile' and P.number(GetWareData(item.ware,'volume')) or 1
                assert(volume>0,'Ammunition volume unavailable')
                local current=(e.plan[item.kind] or {})[item.macro] or 0
                local found=false;for _,amount in ipairs(quantities)do if amount==current then found=true end end
                if not found then quantities[#quantities+1]=current;table.sort(quantities) end
                local values,names,active={},{},1;for _,amount in ipairs(quantities)do if amount*volume<=cap then values[#values+1]=amount;names[#names+1]=tostring(amount);if amount==current then active=#values end end end
                choice('Quantity per ship',names,active,function(i)W.selectAmmo(q,ix,item,values[i])end)
                prose('Storage','Shared capacity: '..cap..'. Other selected ammunition remains; total capacity is checked before saving.')
            end
        elseif W.mode==5 then
            local items=W.softwareOptions(e);local labels={'Choose software'}
            for i,item in ipairs(items)do labels[i+1]='Slot '..item.slot..': '..item.name end
            choice('Install software',labels,1,function(i)if i>1 then W.selectSoftware(q,ix,items[i-1]) end end)
        else
            local capacity=assert(P.integer(ffi.C.GetPeopleCapacity(0,e.macro,false),0,100000),'Crew capacity unavailable')
            prose('Crew capacity',capacity..' places besides the captain. Selected people come from your existing Academy pool; no free crew.')
            local amounts={};for i=0,math.min(100,capacity)do amounts[#amounts+1]=tostring(i) end
            local function crew(field,value)
                local replacement={};for k,v in pairs(e)do replacement[k]=v end;replacement[field]=value
                local check,why=pcall(P.checkCrew,replacement)
                if check then W.replace(q,ix,replacement) else P.message=tostring(why) end
            end
            choice('Marines',amounts,(e.marines or 0)+1,function(i)crew('marines',i-1)end)
            choice('Service crew',amounts,(e.service or 0)+1,function(i)crew('service',i-1)end)
            local total=0;for _,item in ipairs(q.entries)do total=total+((item.marines or 0)+(item.service or 0))*item.amount end
            prose('Academy reservation',total..' existing recruits needed for this fleet; maximum100. Availability is checked before any order.')
        end
    end)
    Helper.ffiClearNewHelper()
    if not ok then prose('Cannot edit',tostring(err)) end
    button('Save workup','SAVE EQUIPMENT AND CREW TO TEMPLATE',function()W.save(q)end,P.current(q) and not P.pending)
    button('Review order','RETURN TO ORDER REVIEW',function()W.editing=nil end,not P.pending)
end
function W.encode(value,depth)
    depth=(depth or 0)+1;assert(depth<=14,'Workup nesting limit')
    local kind=type(value)
    if kind=='string' then return 's'..#value..':'..value end
    if kind=='number' then assert(value==value and math.abs(value)<1e12,'Invalid workup number');local s=tostring(value);return 'n'..#s..':'..s end
    if kind=='boolean' then return value and 't' or 'f' end
    assert(kind=='table','Unsupported workup value')
    local keys={};for k in pairs(value)do assert(type(k)=='string' or type(k)=='number','Invalid workup key');keys[#keys+1]=k end
    assert(#keys<=8192,'Workup exceeds bound')
    table.sort(keys,function(a,b)return type(a)..tostring(a)<type(b)..tostring(b) end)
    local out={'a'..#keys..':'}
    for _,k in ipairs(keys)do out[#out+1]=W.encode(k,depth);out[#out+1]=W.encode(value[k],depth) end
    local result=table.concat(out);assert(#result<=262144,'Workup exceeds storage limit');return result
end
function W.decode(text)
    assert(type(text)=='string' and #text<=262144,'Invalid saved workup')
    local at,nodes=1,0
    local function read(depth)
        nodes=nodes+1;assert(depth<=14 and nodes<=32768,'Workup complexity limit')
        local tag=text:sub(at,at);at=at+1
        if tag=='t' then return true elseif tag=='f' then return false end
        local stop=text:find(':',at,true);assert(stop and stop-at<=8,'Invalid workup length')
        local size=text:sub(at,stop-1);assert(size:match('^%d+$'),'Invalid workup count');size=tonumber(size);at=stop+1
        if tag=='a' then
            assert(size<=8192,'Workup count limit');local result={}
            for i=1,size do local key=read(depth+1);assert((type(key)=='string' or type(key)=='number') and result[key]==nil,'Duplicate workup key');result[key]=read(depth+1) end
            return result
        end
        assert((tag=='s' or tag=='n') and at+size-1<=#text,'Truncated workup')
        local value=text:sub(at,at+size-1);at=at+size
        if tag=='n' then value=tonumber(value);assert(value and value==value and math.abs(value)<1e12,'Invalid workup number') end
        return value
    end
    local value=read(1);assert(at==#text+1,'Trailing workup data');return value
end
function W.capture(q)
    local entries={}
    for _,e in ipairs(q.entries)do
        entries[e.macro]={plan=e.plan,edits=e.equipmentEdits or {},loadoutid=e.loadoutid or '',name=e.loadoutname or 'Generated medium equipment',marines=e.marines or 0,service=e.service or 0,customStores=e.customStores==true}
    end
    return W.encode({version=1,entries=entries})
end
function W.restore(e,blob)
    if not blob or blob=='' then return end
    local data=W.decode(blob);assert(data.version==1 and type(data.entries)=='table','Unknown saved workup version')
    local saved=data.entries[e.macro];if not saved then return end
    assert(type(saved.plan)=='table','Saved equipment plan missing')
    e.plan=FOC_Procurement.copyPlan(saved.plan);e.equipmentEdits=saved.edits;e.loadoutid=saved.loadoutid;e.loadoutname=saved.name;e.marines=saved.marines;e.service=saved.service
    e.customStores=saved.customStores==true;W.validateStores(e)
    -- Crew is transferred from Academy after delivery, never fabricated in a loadout.
    e.plan.crew={};e.plan.hascrewexperience=false
    FOC_Procurement.checkCrew(e)
    e.wares=Helper.callLoadoutFunction(e.plan,nil,FOC_Procurement.wares,nil,'UILoadout2')
    e.price,e.priced,e.hullprice=FOC_Procurement.price(e)
end
function W.save(q,continuation)
    local P=FOC_Procurement
    if W.pending or P.pending or not P.current(q) then return false end
    local ok,blob=pcall(W.capture,q)
    if not ok then P.message=tostring(blob);return false end
    local t=FOC_Advisor.savedDraft()
    if t.workup==blob then if continuation then continuation() end;return true end
    local values={q.template,blob}
    for _,entry in ipairs(q.composition)do
        local e;for _,item in ipairs(q.entries)do if item.macro==entry.macro then e=item;break end end
        values[#values+1]=entry.macro;values[#values+1]=e.service or 0;values[#values+1]=e.marines or 0
    end
    W.pending={quote=q,template=t,blob=blob,continuation=continuation};P.pending={kind='workup',time=getElapsedTime()}
    AddUITriggeredEvent('FOC_Workup','save',values);return true
end
RegisterEvent('FOC_Workup.saved',function(_,blob)
    local p=W.pending;if not p then return end
    W.pending=nil
    if not FOC_Procurement.pending or FOC_Procurement.pending.kind~='workup' then return end
    FOC_Procurement.pending=nil
    if blob~=p.blob or FOC_Procurement.quote~=p.quote or FOC_Advisor.savedDraft()~=p.template then FOC_Procurement.message='Workup save not verified; no order submitted.';FOC_Procurement.changed();return end
    p.template.workup=blob;p.quote.workup=blob
    FOC_Procurement.message='Equipment and crew choices saved to this template.'
    if p.continuation then p.continuation() end
    FOC_Procurement.changed()
end)
