-- ReagentSource Commands: 슬래시 명령, 내보내기 창, 초기화
local _, ns = ...
local RS = ns.RS

local format, pairs, tonumber, tostring = string.format, pairs, tonumber, tostring

function RS.AddonVersion()
    local f = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    return f and f("ReagentSource", "Version") or "?"
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- 내보내기: 학습한 데이터를 Data.lua 형식 Lua 코드로 출력 → 복사해서 공유/보관
---------------------------------------------------------------------------
local function q(s) return format("%q", tostring(s)) end

local function exportText()
    local out = { "-- ReagentSource 내보내기: Data.lua 의 vendors / drops 표 안에 붙여 넣으세요" }
    local function dump(title, src, isDrop)
        out[#out + 1] = "-- " .. title
        local ids = {}
        for id in pairs(src) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local rows = {}
            for _, e in pairs(src[id]) do
                local x, y = e.x, e.y
                if isDrop and e.n and e.n > 0 then x, y = RS.round1(e.sx / e.n), RS.round1(e.sy / e.n) end
                local parts = { "zone=" .. q(e.zone), "name=" .. q(e.name) }
                if x and y then parts[#parts + 1] = format("x=%.1f, y=%.1f", x, y) end
                if e.npc then parts[#parts + 1] = "npc=" .. e.npc end
                if e.faction then parts[#parts + 1] = "faction=" .. q(e.faction) end
                rows[#rows + 1] = "        { " .. table.concat(parts, ", ") .. " },"
            end
            if #rows > 0 then
                table.sort(rows)
                local itemName = RS.GetItemInfo(id)
                out[#out + 1] = format("    [%d] = { -- %s", id, itemName or "?")
                for _, r in ipairs(rows) do out[#out + 1] = r end
                out[#out + 1] = "    },"
            end
        end
    end
    dump("vendors (NPC 판매)", RS.db.vendors, false)
    dump("drops (몬스터 드랍)", RS.db.drops, true)
    return table.concat(out, "\n")
end

local copyFrame
local function showCopy(text)
    if not copyFrame then
        local template = BackdropTemplateMixin and "BackdropTemplate" or nil
        local f = CreateFrame("Frame", "ReagentSourceCopyFrame", UIParent, template)
        f:SetSize(620, 420)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            f:SetBackdropColor(0, 0, 0, 0.9)
        end
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -10)
        title:SetText("재료 획득처 내보내기 (Ctrl+A, Ctrl+C)")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        local sf = CreateFrame("ScrollFrame", "ReagentSourceCopyScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -32)
        sf:SetPoint("BOTTOMRIGHT", -32, 12)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(570)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.edit = eb
        tinsert(UISpecialFrames, "ReagentSourceCopyFrame")
        copyFrame = f
    end
    copyFrame.edit:SetText(text)
    copyFrame:Show()
    copyFrame.edit:SetFocus()
    copyFrame.edit:HighlightText()
end

---------------------------------------------------------------------------
-- 슬래시 명령
---------------------------------------------------------------------------
local function help()
    RS.Print("명령어: /획득처 (또는 /rsrc)")
    RS.Print("  상태 - 기록된 데이터 수 / 툴팁 연결 방식")
    RS.Print("  내보내기 - 기록된 획득처를 Data.lua 형식으로 복사")
    RS.Print("  보기 <아이템ID/링크> - 획득처 전체 보기 창 열기 (마우스 올리고 단축키로도 가능)")
    RS.Print("  삭제 <아이템ID> - 해당 아이템의 기록 삭제")
    RS.Print("  초기화 확인 - 기록 전체 삭제 (Data.lua 의 정적 데이터는 유지)")
    RS.Print("  단축키 <키> - 획득처 창 단축키 변경 (기본 F12, 끄기: 단축키 끔)")
    RS.Print("  공유 - 데이터 공유 안내 창 열기 (파일 보내는 방법)")
    RS.Print("  동기화 - 지금 파티/길드원과 데이터 주고받기 (평소에는 자동)")
    RS.Print("  받는사람 - 이 계정을 데이터 받는 사람으로 등록/해제 (상수님 전용)")
    RS.Print("  경로 <폴더> - 공유 창에 보여줄 SavedVariables 폴더 경로 저장")
    RS.Print("  보냄 - 파일을 보냈다고 표시 (같은 데이터로 다시 알리지 않음)")
    RS.Print("  알림 - (1.8.5부터 자동 알림 없음) 예전 공유 알림 설정")
    RS.Print("  외부 - EG Link 공개 자료 사용 켜기/끄기")
    RS.Print("  출처 - 데이터 출처/라이선스 표시")
    RS.Print("  진단 - 동작 상태 확인 (문제가 있을 때 결과를 상수님께 보내주세요)")
    RS.Print("  디버그 - 기록될 때마다 채팅창에 알림 켜기/끄기")
end

local function handle(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    local itemID = tonumber(arg and (arg:match("item:(%d+)") or arg:match("^(%d+)")))

    if cmd == "상태" or cmd == "stats" then
        local st = ns.StaticData or {}
        RS.Print(format("기록: 판매 %d종 / 드랍 %d종, 정적 데이터: 판매 %d종 / 드랍 %d종",
            count(RS.db.vendors), count(RS.db.drops), count(st.vendors), count(st.drops)))
        local cm = ns.CommunityData
        if cm then RS.Print(format("커뮤니티 취합 자료: 버전 %s, 파일 %d개 반영", tostring(cm.version), cm.contributors or 0)) end
        local E = ns.ExternalData
        if E then
            RS.Print(format("외부 자료(EG Link): 판매 %d종 / 드랍 %d종 - %s", count(E.vendors), count(E.drops),
                RS.cfg.useExternal and "사용 중" or "꺼짐"))
        end
        RS.Print("툴팁 연결 방식: " .. tostring(RS.hookMode))
        if RS.Sync then RS.Print(RS.Sync.Status()) end
    elseif cmd == "내보내기" or cmd == "export" then
        showCopy(exportText())
    elseif cmd == "보기" or cmd == "show" then
        if not itemID then return RS.Print("사용법: /획득처 보기 <아이템ID 또는 아이템 링크>") end
        RS.ShowPopup(itemID)
    elseif cmd == "삭제" or cmd == "forget" then
        if not itemID then return RS.Print("사용법: /획득처 삭제 <아이템ID 또는 아이템 링크>") end
        RS.db.vendors[itemID], RS.db.drops[itemID] = nil, nil
        RS.Invalidate(itemID)
        RS.Print(itemID .. " 기록을 삭제했습니다.")
    elseif cmd == "초기화" or cmd == "reset" then
        if arg ~= "확인" and arg ~= "confirm" then
            return RS.Print("전체 기록을 지우려면 /획득처 초기화 확인 을 입력하세요.")
        end
        wipe(RS.db.vendors); wipe(RS.db.drops); wipe(RS.db.npcNames)
        RS.Invalidate()
        RS.Print("기록을 모두 삭제했습니다.")
    elseif cmd == "진단" or cmd == "diag" then
        local ver = RS.AddonVersion()
        RS.Print("버전 " .. tostring(ver) .. " · 언어 " .. tostring(GetLocale()) .. " · 툴팁 연결 " .. tostring(RS.hookMode))
        RS.Print("툴팁 처리 횟수 " .. tostring(RS.tooltipCalls or 0) .. " · 마지막 아이템 " .. tostring(RS.lastTooltipItem)
            .. " · 마지막 툴팁 오류 " .. tostring(RS.lastTooltipError or "없음"))
        local key = RS.db.popupKey
        RS.Print("단축키 " .. tostring(key) .. " · 원래 기능 " .. tostring(key and GetBindingAction(key) or "-")
            .. " · 현재 우선 적용 " .. tostring(key and GetBindingAction(key, true) or "-") .. " · 눌린 횟수 " .. tostring(RS.keyPresses or 0))
        if RS.lastTooltipItem then
            local src = RS.GetSources(RS.lastTooltipItem, true)
            RS.Print(format("마지막 아이템 획득처: 판매 %d · 드랍 %d · 기타 %d", src and #src.vendors or 0, src and #src.drops or 0, src and #src.etc or 0))
        end
    elseif cmd == "단축키" or cmd == "key" then
        local k = (arg or ""):upper()
        if k == "" then
            return RS.Print("현재 단축키: " .. tostring(RS.db.popupKey or "없음") .. "  (변경: /획득처 단축키 F11, 끄기: /획득처 단축키 끔)")
        end
        if k == "끔" or k == "OFF" then RS.db.popupKey = false else RS.db.popupKey = k end
        RS.ApplyPopupKey()
        RS.Invalidate()
        RS.Print("획득처 창 단축키: " .. (RS.db.popupKey or "끔") .. (RS.keyPending and " (전투가 끝나면 적용)" or ""))
    elseif cmd == "경로" or cmd == "path" then
        local raw = (msg:match("^%S+%s+(.+)$") or ""):gsub('^"', ""):gsub('"$', ""):gsub("[/\\]+$", "")
        if raw == "" then
            RS.Print("공유 창 경로: " .. tostring((RS.ShareFolderPath())))
            RS.Print("정확한 경로 저장: /획득처 경로 C:\\...\\_forever_\\WTF\\Account\\숫자#1\\SavedVariables  · 기본값으로: /획득처 경로 초기화")
        elseif raw == "초기화" or raw == "reset" then
            RS.db.svFolder = nil
            RS.Print("공유 창 경로를 기본값으로 되돌렸습니다: " .. tostring((RS.ShareFolderPath())))
        else
            RS.db.svFolder = raw
            RS.Print("공유 창 경로를 저장했습니다: " .. raw)
        end
    elseif cmd == "받는사람" or cmd == "수집자" or cmd == "collector" then
        RS.db.isCollector = not RS.db.isCollector
        RS.Invalidate()
        if RS.db.isCollector then
            RS.Print("이 계정을 |cff66ff66데이터 받는 사람|r으로 등록했습니다. 파티/길드원의 새 데이터가 자동으로 모이고, 파일 보내기 알림은 뜨지 않습니다.")
            if RS.Sync then RS.Sync.Hello() end
        else
            RS.Print("데이터 받는 사람 등록을 해제했습니다.")
        end
    elseif cmd == "동기화" or cmd == "sync" then
        if RS.Sync then RS.Sync.Hello(); RS.Print("파티/길드원에게 데이터 공유를 요청했습니다. " .. RS.Sync.Status()) end
    elseif cmd == "공유" or cmd == "share" then
        RS.ShowShareGuide()
    elseif cmd == "보냄" or cmd == "완료" or cmd == "sent" then
        RS.MarkSent()
    elseif cmd == "알림" or cmd == "notify" then
        RS.db.contribMuted = not RS.db.contribMuted
        RS.Print("데이터 공유 알림: " .. (RS.db.contribMuted and "끔" or "켬"))
    elseif cmd == "외부" or cmd == "external" then
        RS.cfg.useExternal = not RS.cfg.useExternal
        RS.db.useExternal = RS.cfg.useExternal
        RS.Invalidate()
        RS.Print("외부 자료(EG Link): " .. (RS.cfg.useExternal and "사용" or "끔"))
    elseif cmd == "출처" or cmd == "credits" then
        RS.Print("판매/드랍 기본 자료: Data from Efficient Games (https://efficient.games), licensed under CC BY 4.0.")
        RS.Print("원본: github.com/JIVESCORP/eg-link-output-wowf (빌드 병합·좌표 요약·필터링하여 변환)")
    elseif cmd == "디버그" or cmd == "debug" then
        RS.debug = not RS.debug
        RS.Print("디버그 알림: " .. (RS.debug and "켜짐" or "꺼짐"))
    else
        help()
    end
end

SLASH_REAGENTSOURCE1 = "/획득처"
SLASH_REAGENTSOURCE2 = "/rsrc"
SlashCmdList["REAGENTSOURCE"] = handle

---------------------------------------------------------------------------
-- 초기화 (Core 의 ADDON_LOADED 에서 호출)
---------------------------------------------------------------------------
local loginMsg = CreateFrame("Frame")
loginMsg:RegisterEvent("PLAYER_LOGIN")
loginMsg:SetScript("OnEvent", function()
    local ver = RS.AddonVersion()
    RS.Print(format("v%s 로드됨 · 재료에 마우스를 올리고 [%s] = 획득처 창 · /획득처 도움말", tostring(ver), tostring(RS.db and RS.db.popupKey or "F12")))
end)

function RS.OnReady()
    if RS.db.useExternal ~= nil then RS.cfg.useExternal = RS.db.useExternal end
    RS.InstallTooltipHooks()
end
