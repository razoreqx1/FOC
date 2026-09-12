local B={enabled=false,known=false,pending=false}
FOCCapture=B
function B.render(w,action,text,normal,warning)
    if not B.requested then B.requested=true;AddUITriggeredEvent('FOC_Capture','read',nil) end
    action(w,'Boarding',B.known and (B.enabled and 'ATTEMPT CAPTURE: ON - TURN OFF' or 'ATTEMPT CAPTURE: OFF - TURN ON') or 'READING CAPTURE POLICY',function()
        if B.known and not B.pending then B.pending=true;AddUITriggeredEvent('FOC_Capture','set',B.enabled and 0 or 1) end
    end,B.known and not B.pending,normal)
    text(w,'Capture policy','Eligible fleets may board hostile capital ships when available marines and combat support are sufficient. Otherwise normal combat continues. Manual work is protected; capture is not guaranteed.',normal)
    if B.result then text(w,'Capture result',B.result,warning) end
end
RegisterEvent('FOC_Capture.policy',function(_,value)
    if value~=0 and value~=1 then return end
    B.enabled=value==1;B.known=true;B.pending=false
    if B.onPolicy then B.onPolicy() end
end)
RegisterEvent('FOC_Capture.result',function(_,value)B.result=tostring(value) end)
