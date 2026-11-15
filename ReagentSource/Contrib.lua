-- ReagentSource Contrib: 내가 새로 수집한 데이터(애드온에 아직 없는 것)를 세고, 채팅창으로 "파일을 보내주세요" 알림
--
-- "새 데이터"로 세는 것 (애드온에 들어 있는 자료 = ExternalData + CommunityData + Data.lua 와 비교)
--   · 판매: 자료에 없는 [아이템 ↔ 상인] 조합
--   · 드랍: 자료에 없는 [아이템 ↔ 몬스터] 조합
--   · 이름: 자료의 한글 이름이 없거나 다른 NPC / 채집물 / 퀘스트 이름
--   · 적대 상인: 자료에 없는 "이 진영에 적대적인 상인" 기록
-- 취합된 새 버전을 설치하면, 그 안에 들어간 데이터는 자동으로 "새 데이터"에서 빠진다.
local _, ns = ...
local RS = ns.RS

local format, pairs, ipairs, tostring = string.format, pairs, ipairs, tostring
local NOTIFY_GAP = 30 * 60 -- 플레이 중 알림은 최소 30분 간격

local function collector()
    return (ns.StaticData and ns.StaticData.collectorName) or "상수"
end

---------------------------------------------------------------------------
-- 애드온에 이미 들어 있는 자료 색인 (한 번만 만든다)
---------------------------------------------------------------------------
local shippedV, shippedD
local function hasNpc(list, npcID)
    for _, e in pairs(list or {}) do if type(e) == "table" and e.npc == npcID then return true end end
end

local function buildIndex()
    shippedV, shippedD = {}, {}
    local E = ns.ExternalData
    if E then
        for item, npcs in pairs(E.vendors) do
            local t = {}
            for _, n in ipairs(npcs) do t[n] = true end
            shippedV[item] = t
        end
        for item, l in pairs(E.drops) do
            local t = {}
            for i = 1, #l, 2 do t[l[i]] = true end
            shippedD[item] = t
        end
    end
end

local function shippedVendor(item, npcID)
    if shippedV[item] and shippedV[item][npcID] then return true end
    local cm, st = ns.CommunityData or {}, ns.StaticData or {}
    return hasNpc(cm.vendors and cm.vendors[item], npcID) or hasNpc(st.vendors and st.vendors[item], npcID)
end

local function shippedDrop(item, npcID)
    if shippedD[item] and shippedD[item][npcID] then return true end
    local cm, st = ns.CommunityData or {}, ns.StaticData or {}
    return hasNpc(cm.drops and cm.drops[item], npcID) or hasNpc(st.drops and st.drops[item], npcID)
end

-- 공유(Sync.lua)용: 이 키의 데이터가 이미 애드온 자료나 내 기록에 있는지
function RS.HasKey(key)
    if not shippedV then buildIndex() end
    local kind, a, b = key:match("^(%a):(%d+):?(%d*)$")
    a, b = tonumber(a), tonumber(b)
    if not kind or not a then return true end
    local db, cm, E = RS.db, ns.CommunityData or {}, ns.ExternalData or {}
    if kind == "v" then
        if shippedVendor(a, b) then return true end
        for _, e in pairs(db.vendors[a] or {}) do if e.npc == b then return true end end
    elseif kind == "d" then
        if shippedDrop(a, b) then return true end
        for _, e in pairs(db.drops[a] or {}) do if e.npc == b then return true end end
    elseif kind == "n" then
        return db.npcNames[a] ~= nil or (cm.npcNames and cm.npcNames[a]) ~= nil
    elseif kind == "o" then
        return db.objNames[a] ~= nil or (cm.objNames and cm.objNames[a]) ~= nil
    elseif kind == "q" then
        return db.questNames[a] ~= nil or (cm.questNames and cm.questNames[a]) ~= nil
    elseif kind == "h" then
        local n = E.npc and E.npc[a]
        return db.hostileNPC[a] ~= nil or (cm.hostile and cm.hostile[a]) ~= nil or (n and n[3]) ~= nil
    end
    return false
end

---------------------------------------------------------------------------
-- 새 데이터 세기
---------------------------------------------------------------------------
-- includeReceived: 파티/길드원에게서 받은 데이터(rx)까지 포함할지 (공유용 목록). 기본은 내가 직접 모은 것만
function RS.CountContributions(includeReceived)
    if not RS.db then return 0, {} end
    local rx = RS.db.rx or {}
    local function mine(kind, id) return includeReceived or not (rx[kind] and rx[kind][id]) end
    if not shippedV then buildIndex() end
    local E, cm = ns.ExternalData or {}, ns.CommunityData or {}
    local keys = {}
    local c = { vendor = 0, drop = 0, name = 0, hostile = 0 }

    for item, list in pairs(RS.db.vendors) do
        for _, e in pairs(list) do
            if e.npc and (includeReceived or not e.rx) and not shippedVendor(item, e.npc) then
                keys["v:" .. item .. ":" .. e.npc] = true; c.vendor = c.vendor + 1
            end
        end
    end
    for item, list in pairs(RS.db.drops) do
        for _, e in pairs(list) do
            if e.npc and (includeReceived or not e.rx) and not shippedDrop(item, e.npc) then
                keys["d:" .. item .. ":" .. e.npc] = true; c.drop = c.drop + 1
            end
        end
    end
    local npcs = E.npc or {}
    local korean = (GetLocale and GetLocale() == "koKR")
    for id, name in pairs(korean and RS.db.npcNames or {}) do
        local n = npcs[id]
        local shipped = (cm.npcNames and cm.npcNames[id]) or (n and n[2])
        if n and shipped ~= name and mine("n", id) then keys["n:" .. id] = true; c.name = c.name + 1 end
    end
    for id, name in pairs(korean and RS.db.objNames or {}) do
        local shipped = (cm.objNames and cm.objNames[id]) or (E.oname and E.oname[id])
        local shippedKo = type(shipped) == "string" and shipped:find("[\234-\237]")
        if not shippedKo and shipped ~= name and mine("o", id) then
            keys["o:" .. id] = true; c.name = c.name + 1
        end
    end
    for id, name in pairs(korean and RS.db.questNames or {}) do
        if (cm.questNames and cm.questNames[id]) ~= name and mine("q", id) then keys["q:" .. id] = true; c.name = c.name + 1 end
    end
    for id, f in pairs(RS.db.hostileNPC) do
        local n = npcs[id]
        if not (cm.hostile and cm.hostile[id] == f) and not (n and n[3] == f) and mine("h", id) then
            keys["h:" .. id] = true; c.hostile = c.hostile + 1
        end
    end
    local total = c.vendor + c.drop + c.name + c.hostile
    return total, c, keys
end

-- "보냄" 표시한 뒤로 새로 생긴 것만 센다
local function unsentCount()
    local _, c, keys = RS.CountContributions()
    if RS.db.isCollector then return 0, c, keys end -- 받는 사람(상수) 계정은 보낼 필요 없음
    local sent = RS.db.sentKeys or {}
    local n = 0
    for k in pairs(keys or {}) do if not sent[k] then n = n + 1 end end
    return n, c, keys
end
RS.UnsentContributions = unsentCount

---------------------------------------------------------------------------
-- 안내 창 + 작은 경고 아이콘
--   새 데이터가 생기면 안내 창을 띄우고, 닫으면 빨간 느낌표 아이콘(퀵슬롯 한 칸 크기)으로 줄어든다.
--   "파일 보냈어요"를 누르거나, 취합된 새 버전이 설치되어 보낼 데이터가 없어질 때까지 유지.
---------------------------------------------------------------------------
-- 탐색기 주소창에 붙여넣으면 바로 열리는 폴더 경로
--   · /획득처 경로 로 저장한 정확한 경로가 있으면 → SavedVariables 폴더까지
--   · 없으면 → 기본 설치 위치의 Account 폴더까지 (계정 폴더 이름은 게임 안에서 알 수 없음)
local function folderPath()
    local custom = RS.db and RS.db.svFolder
    if custom and custom ~= "" then return custom, true end
    local base = (ns.StaticData and ns.StaticData.defaultGamePath) or "C:\\Program Files (x86)\\World of Warcraft\\_forever_"
    return base .. "\\WTF\\Account", false
end
RS.ShareFolderPath = folderPath
local alertFrame, alertIcon

local function backdrop(f, r, g, b, a)
    if not f.SetBackdrop then return end
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(r, g, b, a)
end

local function savePos(self, key)
    local p, _, rp, x, y = self:GetPoint()
    if RS.db then RS.db[key] = { p, rp, x, y } end
end

local function restorePos(f, key, dp, dx, dy)
    f:ClearAllPoints()
    local p = RS.db and RS.db[key]
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint(dp, UIParent, dp, dx, dy) end
end

local function makeIcon()
    local b = CreateFrame("Button", "ReagentSourceShareIcon", UIParent)
    b:SetSize(36, 36) -- 퀵슬롯 한 칸 크기
    b:SetFrameStrata("MEDIUM")
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", b.StartMoving)
    b:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self, "shareIconPos") end)

    local circle = b:CreateTexture(nil, "ARTWORK")
    circle:SetAllPoints()
    if circle.SetColorTexture then circle:SetColorTexture(0.85, 0.08, 0.08, 1) else circle:SetTexture(0.85, 0.08, 0.08, 1) end
    if b.CreateMaskTexture then -- 동그랗게 자르기
        local mask = b:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints()
        circle:AddMaskTexture(mask)
    end
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(62, 62)
    ring:SetPoint("TOPLEFT", 0, 0)
    local mark = b:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    mark:SetPoint("CENTER", 0, 1)
    mark:SetText("!")
    mark:SetTextColor(1, 1, 1)
    local glow = b:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.2, 0.2)
    glow:SetSize(66, 66)
    glow:SetPoint("CENTER")
    if b.CreateAnimationGroup then -- 은은하게 깜빡이기
        local ag = glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local al = ag:CreateAnimation("Alpha")
        al:SetFromAlpha(1); al:SetToAlpha(0.2); al:SetDuration(0.9)
        ag:Play()
    end
    b:SetScript("OnClick", function() RS.ShowShareWindow() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("재료 획득처: 데이터 공유 요청", 1, 0.3, 0.3)
        GameTooltip:AddLine(format("새로 수집한 데이터 %d건", (unsentCount())), 1, 1, 1)
        GameTooltip:AddLine("클릭: 보내는 방법 보기 · 드래그: 위치 이동", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    restorePos(b, "shareIconPos", "CENTER", 260, 120)
    b:Hide()
    alertIcon = b
end

local function addText(f, anchor, text, font, gap, color)
    local fs = f:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 6))
    fs:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    return fs
end

local function makeWindow()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "ReagentSourceShareFrame", UIParent, template)
    f:SetSize(500, 320)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self, "shareFramePos") end)
    backdrop(f, 0.06, 0.04, 0.04, 0.96)
    if f.SetBackdropBorderColor then f:SetBackdropBorderColor(0.9, 0.25, 0.25, 1) end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("|cffff5555!|r 재료 획득처 - 새 데이터 공유 요청")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() RS.MinimizeShare() end)

    f.summary = addText(f, title, "", "GameFontHighlight", 10)
    f.step1 = addText(f, f.summary, "", nil, 14)
    f.step2 = addText(f, f.step1, "", nil, 10)
    local box = CreateFrame("EditBox", nil, f, template)
    box:SetPoint("TOPLEFT", f.step2, "BOTTOMLEFT", 0, -6)
    box:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    box:SetHeight(24)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(6, 6, 0, 0)
    backdrop(box, 0, 0, 0, 0.8)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnTextChanged", function(self, user) if user then self:SetText((folderPath())); self:HighlightText() end end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.pathBox = box
    f.hint = addText(f, box, "", "GameFontDisableSmall", 4)
    f.step3 = addText(f, f.hint, "|cffffd1003.|r 다 보냈으면 |cff66ff66[완료]|r 버튼을 눌러 주세요.", nil, 10)
    addText(f, f.step3, "[나중에]나 닫기(X)를 누르면 화면에 작은 빨간 ! 아이콘으로 남습니다. 아이콘을 누르면 이 창이 다시 열립니다.",
        "GameFontDisableSmall", 12)

    -- 버튼: [저장] [나중에] [완료]
    local save = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    save:SetSize(110, 24)
    save:SetPoint("BOTTOMLEFT", 16, 14)
    save:SetText("저장")
    save:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            RS.Print("전투 중에는 저장할 수 없습니다. 전투가 끝난 뒤 눌러 주세요.")
            return
        end
        RS.db.shareSavedAt = time()
        RS.db.shareState = "window" -- 다시 불러온 뒤에도 이 창을 이어서 띄움
        ReloadUI()                  -- 다시 불러오는 순간 데이터가 파일에 저장된다
    end)
    local done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    done:SetSize(110, 24)
    done:SetPoint("BOTTOMRIGHT", -16, 14)
    done:SetText("완료")
    done:SetScript("OnClick", function() RS.MarkSent() end)
    local later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    later:SetSize(110, 24)
    later:SetPoint("BOTTOM", 0, 14)
    later:SetText("나중에")
    later:SetScript("OnClick", function() RS.MinimizeShare() end)

    restorePos(f, "shareFramePos", "CENTER", 0, 80)
    f:Hide()
    alertFrame = f
end

local function refreshWindow()
    local n, c = unsentCount()
    alertFrame.summary:SetText(format("새로 수집한 데이터가 |cffffd100%d건|r 있습니다.  (판매 %d · 드랍 %d · 이름 %d · 적대 상인 %d)",
        n, c.vendor, c.drop, c.name, c.hostile))
    local saved = RS.db.shareSavedAt and (time() - RS.db.shareSavedAt) < 6 * 3600
    alertFrame.step1:SetText("|cffffd1001.|r 아래 |cffffd100[저장]|r 버튼을 누르세요. (화면이 잠깐 다시 불러와지면서 파일에 저장됩니다)"
        .. (saved and "  |cff66ff66(저장 완료)|r" or ""))
    alertFrame.step2:SetText(format("|cffffd1002.|r 아래 폴더의 |cffffffffReagentSource.lua|r 파일을 |cffffd100%s|r님에게 보내 주세요. (.bak 파일 말고)", collector()))
    local path, exact = folderPath()
    alertFrame.pathBox:SetText(path)
    alertFrame.pathBox:SetCursorPosition(0)
    if exact then
        alertFrame.hint:SetText("경로를 클릭 → Ctrl+C로 복사 → 탐색기(윈도우+E) 주소창에 붙여넣고 Enter 하면 바로 열립니다. 파일 이름은 바꾸지 않아도 됩니다.")
    else
        alertFrame.hint:SetText("경로를 클릭 → Ctrl+C로 복사 → 탐색기(윈도우+E) 주소창에 붙여넣고 Enter → 숫자#1 폴더 → SavedVariables 폴더.\n"
            .. "게임을 다른 곳에 설치했다면 그 위치의 _forever_\\WTF\\Account 폴더입니다. 파일 이름은 바꾸지 않아도 됩니다.")
    end
end

local deferred -- 전투 중이면 큰 창은 전투가 끝난 뒤에
function RS.ShowShareWindow()
    if InCombatLockdown and InCombatLockdown() then deferred = true; return end
    if not alertFrame then makeWindow() end
    if not alertIcon then makeIcon() end
    refreshWindow()
    alertIcon:Hide()
    alertFrame:Show()
    RS.db.shareState = "window"
end

function RS.MinimizeShare()
    if not alertIcon then makeIcon() end
    if alertFrame then alertFrame:Hide() end
    alertIcon:Show()
    RS.db.shareState = "icon"
end

local function hideShare()
    if alertFrame then alertFrame:Hide() end
    if alertIcon then alertIcon:Hide() end
    RS.db.shareState = nil
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    if deferred then deferred = false; RS.ShowShareWindow() end
end)

---------------------------------------------------------------------------
-- 알림 (채팅 + 창/아이콘)
---------------------------------------------------------------------------
local lastNotify, lastCount = 0, 0

local function notify(force)
    if not RS.db then return end
    local n = unsentCount()
    if n <= 0 then -- 보낼 것이 없으면(보냄 표시 / 새 버전에 반영됨) 창과 아이콘 정리
        if RS.db.shareState then hideShare() end
        return
    end
    if RS.db.contribMuted then return end
    -- 창/아이콘: 처음 생겼을 때는 창, 사용자가 줄여 둔 상태면 아이콘 유지 (다시 접속해도 유지)
    if RS.db.shareState == "icon" then
        if not alertIcon then makeIcon() end
        if not (alertFrame and alertFrame:IsShown()) then alertIcon:Show() end
    elseif not (alertFrame and alertFrame:IsShown()) then
        RS.ShowShareWindow()
    elseif alertFrame then
        refreshWindow()
    end
    if not force and (n <= lastCount or GetTime() - lastNotify < NOTIFY_GAP) then return end
    lastNotify, lastCount = GetTime(), n
    RS.Print(format("|cffffd100새로 수집한 획득처 데이터가 %d건 있습니다. %s님에게 파일을 보내주세요!|r", n, collector()))
    RS.Print(format("%s님과 파티를 맺거나 같은 길드로 접속해 있으면 자동으로 전달되고, 이 알림도 사라집니다.", collector()))
    RS.Print("화면의 안내 창(또는 빨간 ! 아이콘)에서 [저장] → 파일 보내기 → [완료] 순서로 진행해 주세요.")
end

function RS.ShowShareGuide()
    local n = unsentCount()
    if n <= 0 and RS.CountContributions() == 0 then
        RS.Print("지금은 보낼 새 데이터가 없습니다. 감사합니다!")
        return
    end
    RS.ShowShareWindow()
end

function RS.MarkSent()
    local _, _, keys = RS.CountContributions()
    RS.db.sentKeys = {}
    for k in pairs(keys or {}) do RS.db.sentKeys[k] = true end
    lastCount = 0
    hideShare()
    RS.db.shareSavedAt = nil
    RS.Print("고맙습니다! 완료로 표시했습니다. 새 데이터가 더 모이면 다시 알려드릴게요.")
end

-- 기록이 바뀔 때마다(Invalidate 호출) 조금 뒤에 확인
local pending = false
local checker = CreateFrame("Frame")
checker:Hide()
local waited = 0
checker:SetScript("OnUpdate", function(self, e)
    waited = waited + e
    if waited < 5 then return end
    waited, pending = 0, false
    self:Hide()
    notify(false)
end)

local origInvalidate = RS.Invalidate
function RS.Invalidate(itemID)
    origInvalidate(itemID)
    if RS.db and not pending then pending = true; checker:Show() end
end

-- 누구의 데이터인지 파일 안에 기록 (취합할 때 같은 사람 파일은 최신 것만 쓰기 위해)
local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
    if RS.db then RS.db.savedAt = time() end
end)

-- 접속하고 잠시 뒤 한 번 알림
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if RS.db then
        local name, realm = UnitName("player"), GetRealmName and GetRealmName()
        if name then RS.db.contributor = name .. (realm and realm ~= "" and ("-" .. realm) or "") end
    end
    local t = 0
    self:SetScript("OnUpdate", function(f, e)
        t = t + e
        if t < 12 then return end
        f:SetScript("OnUpdate", nil)
        notify(true)
    end)
end)
