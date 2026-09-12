-- B060: one-use construction approval; MD owns jobs and native task identities.
local B = { request=0, token=0, job=0, message='Choose a saved fleet template and Home area.' }
FOC_Construction = B
function B.changed()
    if FOC_Advisor and FOC_Advisor.changed then FOC_Advisor.changed() end
end
function B.send(kind, data)
    if B.pending then return false end
    B.request = B.request + 1
    B.token = 0
    B.pending = { kind=kind, started=getElapsedTime() }
    B.stage = nil
    local packet = { B.request }
    for _, value in ipairs(data) do packet[#packet+1]=value end
    AddUITriggeredEvent('FOC_Construction',kind,packet)
    return true
end
function B.prepare(template, sector)
    if B.pending then return false end
    if type(template)=='table' and template.workup and template.workup~='' and FOC_Procurement then
        FOC_Procurement.prepare('OWNED')
        return false -- Procurement owns navigation; do not replace its workup with the legacy preset page.
    end
    local id = FOC_Advisor and FOC_Advisor.component(sector)
    if not id or type(template)~='table' or not tonumber(template.id) then
        B.message='Select a Home area and a saved template first.'; return false
    end
    B.home=tostring(id)
    B.message='Checking your yards, owned blueprints and equipment...'
    return B.send('prepare',{tonumber(template.id),id,tostring(id)})
end
function B.commit()
    if B.pending or B.token<=0 then return false end
    local selected=FOC_Advisor and FOC_Advisor.selected
    local home=selected and FOC_Advisor.component(selected.id)
    if not home or tostring(home)~=B.home then
        B.token=0
        B.message='Home area changed. Review a new construction plan before building.'
        return false
    end
    local token=B.token
    B.message='Submitting the approved construction once...'
    return B.send('commit',{token})
end
function B.status()
    return B.send('status',{B.job or 0})
end
function B.tick()
    if B.pending and getElapsedTime()-B.pending.started>20 then
        B.pending=nil; B.stage=nil; B.token=0
        B.message='Readback timed out. Check construction status before making another plan.'
        B.changed()
    end
end
RegisterEvent('FOC_Construction.request',function(_,request)
    if not B.pending or tonumber(request)~=B.request then return end
    if B.stage then B.stage.invalid=true; return end
    B.stage={}
end)
for _,field in ipairs({'token','job','result'}) do
    RegisterEvent('FOC_Construction.'..field,function(_,value)
        local s=B.stage
        if not B.pending or not s then return end
        if s[field]~=nil then s.invalid=true end
        s[field]=value
    end)
end
RegisterEvent('FOC_Construction.complete',function()
    local s,p=B.stage,B.pending
    if not s or not p then return end
    B.stage=nil; B.pending=nil; B.token=0
    local token,job=tonumber(s.token),tonumber(s.job)
    if s.invalid or not token or token<0 or token%1~=0 or not job or job<0 or job%1~=0 or type(s.result)~='string' then
        B.message='Incomplete construction readback. Check status before retrying.'
    elseif p.kind~='prepare' and token~=0 then
        B.message='Unexpected approval in a status result. No new approval retained.'
    else
        B.message=s.result
        if p.kind=='prepare' then B.token=token else B.job=job end
    end
    B.changed()
end)
RegisterEvent('FOC_Construction.activity',function(_,message)
    -- Background delivery is not a response to the currently pending approval.
    B.activity=tostring(message)
end)
