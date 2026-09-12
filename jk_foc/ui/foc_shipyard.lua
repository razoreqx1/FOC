-- B074: bounded question-led editor. MD, not this view, owns purchases and jobs.
local S = { stage='START', quantity=4 }
FOC_Shipyard = S
function S.busy()
    return FOC_Advisor.saving or FOC_Procurement.pending or FOC_Procurement.executing or FOC_Construction.pending
end
function S.go(stage)
    if S.busy() then return false end
    S.stage=stage
    if FOC_Advisor.resetDetailPage then FOC_Advisor.resetDetailPage() end
    FOC_Advisor.changed()
    return true
end
function S.invalidate()
    local p=FOC_Procurement
    if p.quote and not p.quote.used then p.quote=nil end
    FOC_Construction.token=0
end
function S.begin()
    local a=FOC_Advisor
    if S.busy() then return end
    a.shipyardMode=true; a.supportmacro=''; a.draft={}; a.selected=nil
    local used={};for _,t in ipairs(a.templates) do used[t.name]=true end
    a.templateName='Response Fleet 1'
    for i=1,20 do if not used['Response Fleet '..i] then a.templateName='Response Fleet '..i;break end end
    S.invalidate();S.go('FLAGSHIP')
    a.ships=nil;a.queue=nil;a.catalogue()
end
function S.load(t)
    local a=FOC_Advisor
    if S.busy() or #a.draft>0 then return end
    if not a.loadTemplate(t) then return end
    -- Explicitly copying a composition into the new wizard, not migrating its jobs.
    a.shipyardMode=true;a.supportmacro=tonumber(t.shipyard)==1 and (t.supportmacro or '') or ''
    S.invalidate();a.ships=nil;a.queue=nil;a.catalogue();S.go('SUMMARY')
end
function S.escortHull(row)
    return type(row)=='table' and not row.support and (row.class=='shiptypes_s' or row.class=='shiptypes_m')
end
function S.hull(row,kind)
    local a=FOC_Advisor
    if S.busy() or not a.shipyardMode then return end
    local found=false;for _,r in ipairs(a.ships or {}) do if r==row then found=true end end
    if not found or not row.yard or (kind=='SUPPORT')~=(row.support==true) then return end
    if kind~='FLAGSHIP' and kind~='SUPPORT' and not S.escortHull(row) then return end
    if kind=='FLAGSHIP' then
        if #a.draft>0 then return end
        a.add(row,1);S.go('ESCORTS')
    elseif kind=='SUPPORT' then
        if a.supportmacro~='' then return end
        if a.add(row,1) then a.supportmacro=row.macro;S.go('ASSEMBLY') end
    else
        local n=a.number(S.quantity)
        if n and n%1==0 and n>=1 and n<=99 and a.add(row,n) then S.go('ESCORTS') end
    end
    S.invalidate()
end
function S.prepare(route)
    local a=FOC_Advisor
    if S.busy() or not a.shipyardMode or #a.draft==0 or not a.selected or not a.component(a.selected.id) then return end
    local available,reason=a.routeStatus(route)
    if not available then a.status=reason;S.go('SUMMARY');return end
    S.route=route
    -- Re-preparing an unchanged composition must retain its exact template ID,
    -- so the existing incomplete-purchase guard cannot be bypassed by re-saving.
    if a.savedDraft() then S.awaitQuote=true;return end
    S.awaitSave=true;a.onSaved=S.saved
    a.save()
    if not a.saving then S.awaitSave=nil end
end
function S.saveTemplate()
    local a=FOC_Advisor
    if S.busy() or not a.shipyardMode then return end
    S.awaitQuote=nil;S.awaitSave=nil;S.route=nil;a.onSaved=nil
    if a.savedDraft() then a.status='Template already saved. No purchase requested.';return end
    a.save()
end
function S.saved(ok)
    if not S.awaitSave then return end
    S.awaitSave=nil
    if ok then S.awaitQuote=true else S.stage='SUMMARY' end
end
function S.tick()
    local a=FOC_Advisor
    if S.awaitQuote and not S.busy() then
        S.awaitQuote=nil
        local available,reason=a.routeStatus(S.route)
        if not available then a.status=reason;S.stage='SUMMARY';return end
        S.stage='QUOTE';FOC_Procurement.prepare(S.route)
    end
end
function S.render(w,action,text,dropdown,normal,warning,pager,openFleets)
    local a=FOC_Advisor
    if S.stage=='QUOTE' then
        if a.step=='PROCUREMENT' then return FOC_Procurement.render(w,action,text,dropdown,normal,warning) end
        if a.step=='NPC' then return FOC_NPC_Purchases.render(w,action,text,dropdown,normal,warning) end
        S.stage='SUMMARY'
    end
    local rows,captions={},{}
    local nextIndex
    local targets={START='New task force',FLAGSHIP='Select ship',ESCORT_HULL='Select ship',ESCORTS='Continue',SUPPORT='No auxiliary',ASSEMBLY='Gather here',TEMPLATES='Use composition',OWNED='Build fleet'}
    if S.stage=='START' then targets.START=not a.data and 'Start' or #a.draft>0 and 'Continue' or 'New task force' end
    if S.stage=='SUMMARY' then
        if not a.selected then targets.SUMMARY='Location'
        elseif not a.savedDraft() then targets.SUMMARY='Save template'
        elseif a.routeStatus('NPC') then targets.SUMMARY='Buy from NPC yards'
        elseif a.routeStatus('MIXED') then targets.SUMMARY='Combined order'
        elseif a.routeStatus('OWNED') then targets.SUMMARY='Build at your yards'
        else targets.SUMMARY='Refresh availability' end
    end
    local function prose(label,value,color)
        captions[#captions+1]={label,tostring(value or '')}
        rows[#rows+1]=function() text(w,label,value,color or normal) end
    end
    local function button(label,value,fn,active)
        if not nextIndex and label==targets[S.stage] and active~=false then
            nextIndex=#rows+1
            if not a.showPointers or a.showPointers() then value='-> '..value end
        end
        captions[#captions+1]={label,value}
        rows[#rows+1]=function() action(w,label,value,function()
            if not a.isCurrent(w) or S.busy() then return end
            fn();a.changed()
        end,active~=false and not S.busy(),normal) end
    end
    local function choice(label,values,current,fn)
        local longest=tostring(current or '')
        for _,v in ipairs(values) do if #tostring(v)>#longest then longest=tostring(v) end end
        captions[#captions+1]={label,longest}
        rows[#rows+1]=function() dropdown(w,label,values,current,function(value)
            if a.isCurrent(w) and not S.busy() then fn(value);S.invalidate() end
        end) end
    end
    prose('SHIPYARD','Build a flagship and its escorts, then assign the completed fleet a mission.')
    if a.started or a.saving then prose('Reading',a.status,warning) end
    if S.stage=='START' then
        if not a.data then
            button('Start','READ AVAILABLE SHIPYARDS AND TEMPLATES',function() a.refresh() end,not a.started)
        else
            if #a.draft>0 then
                button('Continue','CONTINUE CURRENT COMPOSITION',function() S.go(a.shipyardMode and 'SUMMARY' or 'LEGACY') end)
                button('New composition','DISCARD UNSAVED COMPOSITION AND START NEW',S.begin)
            else
                button('New task force','BUILD A NEW FLEET',S.begin)
                button('Saved composition','BUILD FROM A SAVED TEMPLATE',function() S.go('TEMPLATES') end,#a.templates>0)
            end
            button('Already ordered?','CHECK EXISTING PURCHASE / DELIVERY',function() S.invalidate();S.stage='QUOTE';a.go('PROCUREMENT');FOC_Procurement.status() end)
            button('Your fleets','GIVE A COMPLETED FLEET AN ASSIGNMENT',openFleets)
        end
    elseif S.stage=='LEGACY' then
        prose('Existing draft','Your Strategic Ops composition is retained. Return there to finish it, or explicitly start a new Shipyard composition.')
        button('Back','SHIPYARD START - KEEP CURRENT COMPOSITION',function() S.go('START') end)
    elseif S.stage=='TEMPLATES' then
        button('Back','BACK',function() S.go('START') end)
        for _,t in ipairs(a.templates) do button('Use composition',t.name..' | '..tostring(t.total)..' ships',function() S.load(t) end) end
    elseif S.stage=='FLAGSHIP' or S.stage=='ESCORT_HULL' or S.stage=='SUPPORT' then
        local kind=S.stage
        prose('Choose',kind=='FLAGSHIP' and 'Which ship should lead?' or kind=='SUPPORT' and 'Would you like an auxiliary supply ship, such as a Nomad?' or 'Choose S- or M-class combat escorts to defend the flagship.')
        if kind=='SUPPORT' then
            prose('Supply support','An auxiliary is assigned Supply Fleet. This does not buy supplies or guarantee repairs.')
            button('No auxiliary','CONTINUE WITHOUT A SUPPLY SHIP',function() S.go('ASSEMBLY') end)
        else button('Back','BACK',function() S.go(kind=='FLAGSHIP' and 'START' or 'ESCORTS') end) end
        local list={};for _,r in ipairs(a.ships or {}) do
            if (r.yard or kind=='SUPPORT') and (kind=='SUPPORT')==(r.support==true) and (kind~='ESCORT_HULL' or S.escortHull(r)) then list[#list+1]=r end
        end
        table.sort(list,function(x,y) return x.name==y.name and x.macro<y.macro or x.name<y.name end)
        if #list==0 then prose('Availability',a.ships and 'No compatible available ships found. You can return and refresh the yard list.' or a.status,warning) end
        for _,r in ipairs(list) do
            if r.yard then button('Select ship',r.name..' | '..r.route,function() S.hull(r,kind) end)
            else prose('Unavailable auxiliary',r.name..' | NPC: '..(r.npcreason or r.route)..' | Your yards: '..(r.ownreason or r.route),warning) end
        end
        if kind=='SUPPORT' then button('Refresh availability','RECHECK SHIPYARDS',function() a.catalogue() end) end
    elseif S.stage=='ESCORTS' then
        prose('Escorts','How many escorts of the next ship type do you want? Add another type if needed.')
        local amounts={};for i=1,99 do amounts[#amounts+1]=tostring(i) end
        choice('Quantity',amounts,tostring(S.quantity),function(v) S.quantity=tonumber(v) end)
        button('Add escorts','CHOOSE ESCORT SHIP',function() S.go('ESCORT_HULL') end)
        button('Continue','ESCORTS DONE - CHOOSE SUPPLY SUPPORT',function() S.go('SUPPORT') end)
        button('Review','REVIEW CURRENT COMPOSITION',function() S.go('SUMMARY') end)
    elseif S.stage=='ASSEMBLY' then
        prose('Assembly location','Where should the completed fleet gather and wait? Choose its operational Home and mission later in Fleets.')
        button('Back','BACK TO COMPOSITION',function() S.go('SUMMARY') end)
        for _,h in ipairs(a.data and a.data.homes or {}) do button('Gather here',h.name,function()
            if a.chooseHome(h) then S.invalidate();S.go('SUMMARY') end
        end) end
    elseif S.stage=='SUMMARY' then
        local slots={};for i=1,20 do slots[#slots+1]='Response Fleet '..i end
        choice('Template slot',slots,a.templateName or slots[1],function(v) a.templateName=v end)
        prose('Template',a.savedDraft() and 'SAVED - reusable without purchasing.' or 'Not saved. Save this composition without buying ships.')
        for i,e in ipairs(a.draft) do
            local name=e.macro;for _,r in ipairs(a.ships or {}) do if r.macro==e.macro then name=r.name;break end end
            prose(i==1 and 'Flagship + same-type escorts' or e.macro==a.supportmacro and 'Supply Fleet' or 'Defence escorts',e.amount..' x '..name)
        end
        prose('Gather at',a.selected and a.selected.name or 'CHOOSE ASSEMBLY SECTOR',a.selected and normal or warning)
        button('Location','CHOOSE ASSEMBLY SECTOR',function() S.go('ASSEMBLY') end)
        button('More escorts','ADD MORE ESCORTS',function() S.go('ESCORTS') end,a.supportmacro=='')
        button('Save template','SAVE AS TEMPLATE - NO PURCHASE',S.saveTemplate,#a.draft>0 and a.selected~=nil)
        local npc,npcReason=a.routeStatus('NPC');local own,ownReason=a.routeStatus('OWNED')
        if not npc then prose(own and 'Build route' or 'NPC purchase unavailable',own and 'Build this fleet at your own yards. Some selected ships are not sold by NPC yards.' or npcReason,own and normal or warning) end
        if not own then prose('Your-yard build unavailable',ownReason,warning) end
        if not npc or not own then button('Refresh availability','RECHECK SUPPLIERS',function() a.catalogue() end) end
        button('Buy from NPC yards','REVIEW EQUIPMENT AND COMPLETE PRICE',function() S.prepare('NPC') end,npc and a.selected~=nil)
        if not npc then button('Combined order','REVIEW BUY / BUILD TOGETHER - ONE FLEET',function() S.prepare('MIXED') end,a.routeStatus('MIXED') and a.selected~=nil) end
        button('Build at your yards','REVIEW OWNED-YARD CONSTRUCTION',function() S.prepare('OWNED') end,own and a.selected~=nil)
        button('Back','SHIPYARD START - KEEP CURRENT COMPOSITION',function() S.go('START') end)
    elseif S.stage=='OWNED' then
        local b=FOC_Construction
        prose('Owned-yard plan',b.message)
        if b.activity then prose('Latest delivery',b.activity) end
        prose('On approval','Use normal yard resources, attach the chosen roles, gather and wait. No patrol mission or supply-cargo purchase.')
        button('Build fleet','APPROVE THIS CONSTRUCTION ONCE',function() b.commit() end,b.token>0)
        button('Progress','CHECK EXISTING CONSTRUCTION',function() b.status() end)
        button('Assignments','OPEN FLEETS',openFleets)
        button('Back','BACK TO COMPOSITION',function() S.go('SUMMARY') end)
    end
    if not a.started and not a.saving and a.status then prose('Status',a.status) end
    local units,fits
    if a.shipyardRowUnits then units,fits=a.shipyardRowUnits(captions) end
    if fits==false then
        text(w,'Display too small','Reduce UI scaling or enlarge the view. Your composition is retained; no purchase was made.',warning)
        return
    end
    local first,last=pager(w,'advisor.detail',#rows,{fixedRows=8,rowUnits=units or 6,maximum=units and 40 or 6,nextIndex=nextIndex})
    for i=first,last do rows[i]() end
end
