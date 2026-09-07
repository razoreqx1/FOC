-- B060: Lua never receives or reconstructs a native build task. MD retains it.
local N={request=0,message='No NPC purchase review loaded.'}
FOC_NPC_Purchases=N
function N.changed() if FOC_Advisor then FOC_Advisor.changed() end end
function N.integer(v,min,max)
    local n=tonumber(v)
    return n and n==n and n>=min and n<=max and n%1==0 and n or nil
end
function N.send(kind,values,guard,open)
    if N.pending then return false end
    N.request=N.request+1; N.stage=nil
    N.pending={kind=kind,time=getElapsedTime(),guard=guard,open=open}
    local packet={N.request}; for _,v in ipairs(values or {}) do packet[#packet+1]=v end
    AddUITriggeredEvent('FOC_NPC_Purchases',kind,packet)
    return true
end
function N.start(template,home,yard,macro,quantity,guard,open)
    if N.pending or not template or not N.integer(template.id,1,9007199254740991) or not home or not yard or type(macro)~='string' or not N.integer(quantity,1,100) or type(guard)~='function' or type(open)~='function' or not guard() then return false end
    N.message='Arming purchase capture. X4 opens only after complete confirmation.'
    return N.send('start',{tonumber(template.id),home,yard,macro,quantity,tostring(home)},guard,open)
end
function N.status(token) return N.send('status',{tonumber(token) or 0}) end
function N.discard()
    if N.snapshot and N.snapshot.prepared==1 then N.message='Prepared purchases retain payment and order evidence. Use prepared order status.';return false end
    if N.pending or not N.snapshot or N.snapshot.approved~=0 then return false end
    return N.send('discard',{N.snapshot.token})
end
function N.approve()
    local s=N.snapshot
    if s and s.prepared==1 then N.message='Prepared purchases are verified by their exact native order IDs. Use prepared order status.';return false end
    if N.pending or not s or s.approved~=0 or s.review<0 or s.review~=s.revision or s.overflow~=0 then return false end
    local a=FOC_Advisor; local home=a and a.selected and a.component(a.selected.id)
    if not home or tostring(home)~=s.home then N.message='Home changed. Choose the reviewed Home before approving.'; return false end
    local token,revision,template=s.token,s.review,s.template
    local values={token,revision,home,template}
    for _,r in ipairs(s.rows) do if r.selected then values[#values+1]=r.id end end
    if #values==4 then N.message='Select the exact purchases to use for this fleet first.';return false end
    s.review=-1 -- consume transient approval before submitting; MD also consumes once
    N.message='Approving only the displayed captured purchases. No new purchase is sent.'
    return N.send('approve',values)
end
-- B064: an all-list PREVIEW is not automatic adoption. Only confirm() sends.
function N.selection(s)
    local rows,total={},0
    for _,r in ipairs(s and s.rows or {}) do
        if not N.custom or r.selected then rows[#rows+1]=r;total=total+tonumber(r.price) end
    end
    return rows,total
end
function N.matches(s,rows)
    if N.pending or not s or s~=N.snapshot or s.approved~=0 or s.overflow~=0 or s.review<0 or s.review~=s.revision or #rows~=s.expected then return false end
    local a=FOC_Advisor;local t=a and a.savedDraft and a.savedDraft()
    if not t or tonumber(t.id)~=s.template or not a.selected or tostring(a.component(a.selected.id))~=s.home then return false end
    local amounts,seen={},{}
    for _,r in ipairs(rows) do
        if seen[r.id] or (r.rowstate~='QUEUED' and r.rowstate~='DELIVERED') then return false end
        seen[r.id]=true;amounts[r.macro]=(amounts[r.macro] or 0)+1
    end
    for _,e in ipairs(t.entries or {}) do
        if amounts[e.macro]~=tonumber(e.amount) then return false end
        amounts[e.macro]=nil
    end
    return next(amounts)==nil
end
function N.confirm(s)
    local rows=N.selection(s)
    if not N.matches(s,rows) then N.message='List changed or does not match the saved fleet. Check purchases; nothing approved.';return false end
    for _,r in ipairs(s.rows) do r.selected=false end
    for _,r in ipairs(rows) do r.selected=true end
    return N.approve()
end
function N.render(w,action,text,dropdown,normal,warning)
    local a,s=FOC_Advisor,N.snapshot
    local rows,measurements={},{}
    local function current() return a.step=='NPC' and (not a.isCurrent or a.isCurrent(w)) and N.snapshot==s end
    local function button(label,caption,fn,active,color)
        measurements[#measurements+1]={label,caption}
        rows[#rows+1]=function() action(w,label,caption,function() if active and current() and not N.pending then fn();N.changed() end end,active,color or normal) end
    end
    local function prose(label,value)
        local caption=tostring(value):sub(1,220)
        measurements[#measurements+1]={label,caption}
        rows[#rows+1]=function() text(w,label,caption,normal) end
    end
    local function choice(label,values,selected,fn)
        measurements[#measurements+1]={label,selected}
        rows[#rows+1]=function() dropdown(w,label,values,selected,function(v) if current() and not N.pending then fn(v);N.changed() end;return false end) end
    end
    button('Back','BACK TO FLEET BUILD / BUY',function() a.go('PURCHASE') end,not N.pending)
    button('Update','CHECK PURCHASES / DELIVERY',function() N.status(s and s.token) end,not N.pending)
    if #(N.jobs or {})>0 then
        local values,map={'Current purchase review'},{}
        for _,j in ipairs(N.jobs) do local label='Job '..j.id..' | '..j.jobname:sub(1,80);values[#values+1]=label;map[label]=j.id end
        choice('Saved jobs',values,'Current purchase review',function(v) N.status(map[v] or 0) end)
    end
    prose('Status',N.message)
    if s and s.prepared==1 and s.approved==0 and FOC_Procurement then
        button('Prepared purchase','OPEN PREPARED ORDER STATUS',function()a.go('PROCUREMENT');FOC_Procurement.status(s.token)end,not FOC_Procurement.pending)
        prose('Order protection','This purchase retains payment and native order IDs. Manual capture approval and discard are blocked.')
    elseif s then
        local selected,total=N.selection(s)
        prose('Fleet / Home','Job '..s.token..' | '..s.homename..' | '..#selected..' selected / '..s.expected..' needed ('..s.count..' captured)')
        prose('Recorded total',tostring(total)..' Cr | Recorded order prices, not payment receipts.')
        local values,lookup={},{}
        local inspected
        for _,r in ipairs(s.rows) do
            local ok,name=pcall(GetMacroData,r.macro,'name')
            local label='#'..r.id..' | '..tostring(ok and name or r.macro):sub(1,80)..' | '..r.rowstate
            values[#values+1]=label;lookup[label]=r
            if r.id==N.detail then inspected=r end
        end
        inspected=inspected or s.rows[1]
        if inspected then
            local start=values[1];for label,r in pairs(lookup) do if r==inspected then start=label end end
            choice('Inspect a purchase',values,start,function(v) if lookup[v] then N.detail=lookup[v].id end end)
            prose('Selected detail','#'..inspected.id..' | '..inspected.yard..' | '..tostring(inspected.price)..' Cr | '..inspected.ship)
            if s.approved==0 then
                local included=not N.custom or inspected.selected
                button('Adjust list',included and 'EXCLUDE THIS PURCHASE' or 'INCLUDE THIS PURCHASE',function()
                    if not N.custom then for _,r in ipairs(s.rows) do r.selected=true end;N.custom=true end
                    inspected.selected=not inspected.selected
                end,not N.pending and s.review>=0)
            end
        end
        if s.approved==0 then
            prose('Your confirmation','Use only purchases you intended for this fleet. Inspect entries above; exclude unrelated matches. CHECK resets this preview.')
            button('Approve fleet','CONFIRM: USE THESE '..#selected..' PURCHASES FOR THIS FLEET',function() N.confirm(s) end,N.matches(s,selected),warning)
            if not N.matches(s,selected) then prose('Approval blocked','CHECK for a current list; select the saved fleet and Home. Exact hull quantities must match; cancelled, missing or extra purchases cannot be approved.') end
            button('Abandon review','DISCARD UNAPPROVED TRACKING ONLY - KEEP PURCHASES',N.discard,not N.pending,warning)
        end
    end
    prose('Next / waiting',s and s.prepared==1 and 'Prepared orders retain their exact task/payment evidence across reload. CHECK never buys. Use prepared order status for unresolved verification; do not repeat a pending purchase.' or 'After approval X4 delivers; FOC checks assembly separately. No new purchase from CHECK. Reload closes capture, keeps orders. Do not buy again just because delivery is pending.')
    -- Fixed descriptors only: up to 14 rows, regardless of 100 purchases/20 jobs.
    -- Native text measurement and shared pool checked before population.
    if not a.fitReview or not a.fitReview(#rows,measurements) then
        action(w,'Back','BACK TO FLEET BUILD / BUY',function() if current() then a.go('PURCHASE');N.changed() end end,true,normal)
        text(w,'Review cannot fit','Increase the window size or reduce UI scale. No purchases approved; this review needs more room.',warning)
        return
    end
    for _,render in ipairs(rows) do render() end
end
function N.tick()
    if N.pending and getElapsedTime()-N.pending.time>20 then
        N.pending=nil;N.stage=nil
        N.message='Confirmation timed out. No purchase menu opened by this request. Check retained purchases before retrying.'
        N.changed()
    end
end
RegisterEvent('FOC_NPC_Purchases.request',function(_,v)
    if not N.pending or tonumber(v)~=N.request then return end
    if N.stage then N.stage.invalid=true else N.stage={rows={},seen={},jobs={},jobseen={}} end
end)
RegisterEvent('FOC_NPC_Purchases.job',function(_,v)
    local s=N.stage;if not s then return end
    local id=N.integer(v,1,9007199254740991)
    if s.job or not id or s.jobseen[id] or #s.jobs>=20 then s.invalid=true;return end
    s.job={id=id};s.jobseen[id]=true
end)
for _,f in ipairs({'jobname','jobstate'}) do
    RegisterEvent('FOC_NPC_Purchases.'..f,function(_,v)
        local s=N.stage;if not s then return end
        if not s.job or s.job[f]~=nil or type(v)~='string' then s.invalid=true;return end
        s.job[f]=v
    end)
end
RegisterEvent('FOC_NPC_Purchases.jobcommit',function()
    local s=N.stage;if not s then return end
    if not s.job or not s.job.jobname or not s.job.jobstate then s.invalid=true;return end
    s.jobs[#s.jobs+1]=s.job;s.job=nil
end)
for _,field in ipairs({'started','token','revision','template','home','homename','state','approved','review','overflow','expected','count','result','jobcount','discarded','prepared'}) do
    RegisterEvent('FOC_NPC_Purchases.'..field,function(_,v)
        local s=N.stage; if not s or not N.pending then return end
        if s[field]~=nil then s.invalid=true end; s[field]=v
    end)
end
RegisterEvent('FOC_NPC_Purchases.row',function(_,v)
    local s=N.stage; if not s then return end
    local id=N.integer(v,1,100)
    if s.row or not id or s.seen[id] or #s.rows>=100 then s.invalid=true; return end
    s.row={id=id};s.seen[id]=true
end)
for _,field in ipairs({'macro','rowstate','ship','price','yard'}) do
    RegisterEvent('FOC_NPC_Purchases.'..field,function(_,v)
        local s=N.stage; if not s then return end
        if not s.row then s.invalid=true; return end
        if s.row[field]~=nil then s.invalid=true end; s.row[field]=v
    end)
end
RegisterEvent('FOC_NPC_Purchases.rowcommit',function()
    local s=N.stage; if not s then return end
    local r=s.row; s.row=nil
    if not r then s.invalid=true;return end
    for _,f in ipairs({'macro','rowstate','ship','yard'}) do if type(r[f])~='string' or r[f]=='' then s.invalid=true end end
    local states={QUEUED=true,DELIVERED=true,CANCELLED=true,['DELIVERY UNCONFIRMED']=true}
    local price=tonumber(r.price)
    if not states[r.rowstate] or not price or price~=price or price<0 or price>=math.huge then s.invalid=true end
    s.rows[#s.rows+1]=r
end)
RegisterEvent('FOC_NPC_Purchases.complete',function()
    local s,p=N.stage,N.pending; if not s or not p then return end
    N.stage=nil;N.pending=nil
    if p.kind=='status' and N.integer(s.jobcount,0,20)~=#s.jobs then s.invalid=true end
    if type(s.result)=='string' and not s.invalid and not s.job and s.token==nil and #s.rows==0 and not s.row then
        N.message=s.result
        if p.kind=='discard' and tonumber(s.discarded)==1 then N.snapshot=nil end
        if p.kind=='status' then N.jobs=s.jobs end
        N.changed();return
    end
    for _,f in ipairs({'started','token','revision','template','approved','overflow','expected','count'}) do
        local max=9007199254740991
        if f=='approved' or f=='overflow' then max=1 elseif f=='count' or f=='expected' then max=100 end
        s[f]=N.integer(s[f],0,max);if not s[f] then s.invalid=true end
    end
    s.review=N.integer(s.review,-1,9007199254740991)
    if s.prepared~=nil then s.prepared=N.integer(s.prepared,0,1);if not s.prepared then s.invalid=true end end
    if s.invalid or s.row or s.job or not s.review or type(s.home)~='string' or type(s.homename)~='string' or type(s.state)~='string' or #s.rows~=s.count or s.token==0 or s.template==0 or s.expected==0 then
        N.message='Purchase readback incomplete or request refused. Previous evidence retained; check purchases before retrying.'
    elseif (p.kind=='start' and s.started~=s.token) or (p.kind~='start' and s.started~=0) then
        N.message='Capture confirmation did not match. No menu opened.'
    else
        N.snapshot=s;N.message=s.state;N.custom=nil;N.detail=nil
        if p.kind=='status' then N.jobs=s.jobs end
        if p.kind=='start' then
            if p.guard() then p.open() else N.message='Page or plan changed while arming. No menu opened. Review retained capture before continuing.' end
        end
    end
    N.changed()
end)
