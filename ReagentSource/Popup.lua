-- ReagentSource Popup: 재료에 마우스를 올리고 단축키(기본 F12)를 누르면 뜨는 "획득처 전체 보기" 창
--   · NPC 판매 / 몬스터 드랍을 나눠서 가까운 순으로 표시
--   · 좌표(파란 글씨)를 클릭하면 그 위치로 길 안내
--     Shortest Path Forever 가 있으면 KQuestGuide 와 같은 방식(핀 + 점선 경로 + 화살표),
--     없으면 게임 기본 지도 핀 + 추적
local _, ns = ...
local RS = ns.RS

local format, floor, sqrt = string.format, math.floor, math.sqrt
local ROW_H = 18
local WIDTH = 440

---------------------------------------------------------------------------
-- 길 안내
---------------------------------------------------------------------------
local SPF_OWNER = "ReagentSource"
local frame, content, rows = nil, nil, {} -- 획득처 창 (아래에서 만든다)

local function spfApi()
    local s = rawget(_G, "ShortestPathForever")
    return type(s) == "table" and type(s.API) == "table" and s.API or nil
end

local function blizzardPin(e)
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
    local ok = pcall(function()
        if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(e.uiMap) then error("map") end
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(e.uiMap, e.x / 100, e.y / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end)
    return ok
end

---------------------------------------------------------------------------
-- 안내 상태 표시줄 + 종료 처리
--   안내 시작 → 획득처 창 닫기, 화면 위쪽에 작은 표시줄("이름 - 아이템 - 획득처로 안내 중" + [안내 종료])
--   종료 조건: ① 목적지 5야드 미만 도착  ② [안내 종료] 버튼  ③ 다른 길찾기가 안내를 가져감
---------------------------------------------------------------------------
local ARRIVE_YARDS = 5
local guide        -- { e, itemName, mode = "spf"|"pin", inst, wx, wy }
local guideBar

local function worldOf(uiMap, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, uiMap, CreateVector2D(x, y))
    if not (ok and inst and pos) then return end
    local wx, wy = pos.x, pos.y
    if pos.GetXY then wx, wy = pos:GetXY() end
    return inst, wx, wy
end

local function playerWorldPos()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local m = C_Map.GetBestMapForUnit("player")
    if not m then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
    if not (ok and pos) then return end
    local px, py = pos.x, pos.y
    if pos.GetXY then px, py = pos:GetXY() end
    return worldOf(m, px, py)
end

local function clearRoute()
    if not guide then return end
    if guide.mode == "spf" then
        local api = spfApi()
        if api and api.Cancel then pcall(api.Cancel, SPF_OWNER) end
    else
        if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, false) end
    end
end

function RS.StopGuide(reason)
    if not guide then return end
    if reason ~= "taken" then clearRoute() end
    local e = guide.e
    guide = nil
    if RS.db then RS.db.activeGuide = nil end
    if guideBar then guideBar:Hide() end
    if reason == "arrived" then
        RS.Print(format("도착했습니다: %s - 안내를 종료합니다.", e.name))
    elseif reason == "button" then
        RS.Print("안내를 종료했습니다.")
    end
end

-- 지역 이동(로딩) 직후에는 길찾기/핀이 지워질 수 있다 → 이 시간 안에 사라지면 같은 목적지로 다시 건다
-- (퀘스트 길잡이 KQuestGuide 와 같은 방식, 40초)
local ZONE_WINDOW = 40
local zoneChangeAt = 0
local zf = CreateFrame("Frame")
zf:RegisterEvent("PLAYER_ENTERING_WORLD")
zf:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zf:SetScript("OnEvent", function() zoneChangeAt = GetTime() end)
local function justChangedZone() return GetTime() - zoneChangeAt < ZONE_WINDOW end

local function submitRoute(e, itemName, isVendor)
    local api = spfApi()
    if api and api.NavigateRoute and RS.cfg.useSPF ~= false then
        local stop = { map = e.uiMap, x = e.x / 100, y = e.y / 100,
            title = (itemName and (itemName .. " · ") or (e.label and (e.label .. " · ")) or "") .. e.name, radius = ARRIVE_YARDS }
        if isVendor and e.npc then stop.npc = e.npc end -- 도착하면 상인 이름표 강조
        -- 다른 애드온의 길찾기가 진행 중이면 다시 걸 때는 덮어쓰지 않는다
        local ok, res = pcall(api.NavigateRoute, SPF_OWNER, { stop })
        if ok and res then return "spf" end
    end
    if blizzardPin(e) then return "pin" end
end

local function makeGuideBar()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "ReagentSourceGuideBar", UIParent, template)
    f:SetSize(320, 50)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        if RS.db then RS.db.guideBarPos = { p, rp, x, y } end
    end)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0, 0, 0, 0.6)
        f:SetBackdropBorderColor(0.3, 0.6, 0.9, 0.8)
    end
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", 8, -7)
    f.text:SetPoint("TOPRIGHT", -8, -7)
    f.text:SetJustifyH("CENTER")
    f.text:SetWordWrap(false)
    f.dist = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.dist:SetPoint("BOTTOMLEFT", 10, 8)
    local stop = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    stop:SetSize(80, 18)
    stop:SetPoint("BOTTOMRIGHT", -6, 5)
    stop:SetText("안내 종료")
    if stop.GetFontString and stop:GetFontString() then stop:GetFontString():SetFontObject("GameFontNormalSmall") end
    stop:SetScript("OnClick", function() RS.StopGuide("button") end)

    -- 도착 확인 (0.25초마다)
    local acc = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 0.25 or not guide then return end
        acc = 0
        if guide.mode == "spf" then
            local api = spfApi()
            local ok, cur = pcall(api and api.CurrentStop or function() end, SPF_OWNER)
            if ok and cur == nil and GetTime() - guide.started > 2 then
                local why = api and api.Ended and select(2, pcall(api.Ended, SPF_OWNER))
                local inst, px, py = playerWorldPos()
                local near = inst and inst == guide.inst and ((px - guide.wx) ^ 2 + (py - guide.wy) ^ 2) < 30 ^ 2
                if why == "replaced" then
                    RS.StopGuide("taken")          -- 다른 애드온/사용자가 새 길찾기를 시작함
                elseif near or why == "arrived" then
                    RS.StopGuide("arrived")
                elseif justChangedZone() then
                    -- 지역 이동 중 경로가 지워짐 → 2초 간격으로 같은 목적지에 다시 건다
                    if GetTime() >= (guide.retryAt or 0) then
                        guide.retryAt = GetTime() + 2
                        local mode = submitRoute(guide.e, guide.itemName, guide.isVendor)
                        if mode then guide.mode, guide.started = mode, GetTime() end
                    end
                    return
                else
                    RS.StopGuide("taken")          -- 길찾기 쪽에서 직접 취소함
                end
                return
            end
        elseif guide.mode == "pin" and C_Map and C_Map.GetUserWaypoint then
            local okw, wp = pcall(C_Map.GetUserWaypoint)
            if okw and not wp and GetTime() - guide.started > 2 then
                if justChangedZone() then
                    if GetTime() >= (guide.retryAt or 0) then
                        guide.retryAt = GetTime() + 2
                        blizzardPin(guide.e)       -- 지역 이동 중 지워진 핀 다시 찍기
                    end
                else
                    RS.StopGuide("taken")          -- 사용자가 지도에서 핀을 지움
                    return
                end
            end
        end
        local inst, px, py = playerWorldPos()
        if inst and guide.inst and inst == guide.inst then
            local d = math.sqrt((px - guide.wx) ^ 2 + (py - guide.wy) ^ 2)
            self.dist:SetText(format("남은 거리 약 %d야드", math.floor(d + 0.5)))
            if d < ARRIVE_YARDS then RS.StopGuide("arrived") end
        else
            self.dist:SetText("다른 지역 · 경로를 따라 이동하세요")
        end
    end)

    f:ClearAllPoints()
    local p = RS.db and RS.db.guideBarPos
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("TOP", UIParent, "TOP", 0, -96) end
    f:Hide()
    guideBar = f
end

local function startGuide(e, itemName, mode, isVendor)
    if not guideBar then makeGuideBar() end
    local inst, wx, wy = worldOf(e.uiMap, e.x / 100, e.y / 100)
    guide = { e = e, itemName = itemName, mode = mode, isVendor = isVendor, inst = inst, wx = wx, wy = wy, started = GetTime() }
    if RS.db then -- /reload·재접속 뒤 이어서 안내하기 위해 저장
        RS.db.activeGuide = { e = { zone = e.zone, name = e.name, x = e.x, y = e.y, uiMap = e.uiMap, npc = e.npc, method = e.method,
            label = e.label }, itemName = itemName, isVendor = isVendor }
    end
    local who = e.method and ("[" .. e.method .. "] " .. e.name) or e.name
    if e.label then -- 장소·NPC 검색에서 시작한 안내 (1.11.0)
        guideBar.text:SetText(format("|cff66ccff%s|r - %s 안내 중", who, e.label))
    else
        guideBar.text:SetText(format("|cff66ccff%s|r - %s - 획득처로 안내 중", who, itemName or "아이템"))
    end
    guideBar.dist:SetText("")
    guideBar:Show()
    if frame then frame:Hide() end -- 획득처 창 닫기
end

function RS.Navigate(e, itemName, isVendor)
    if not (e and e.uiMap and e.x and e.y) then
        RS.Print("이 획득처는 지도 위치 정보가 없어 안내할 수 없습니다.")
        return
    end
    if guide then RS.StopGuide("replace") end
    local mode = submitRoute(e, itemName, isVendor)
    if mode then
        startGuide(e, itemName, mode, isVendor)
    else
        RS.Print("이 위치에는 핀을 찍을 수 없습니다: " .. RS.FormatEntry(e))
    end
end

-- /reload 나 재접속 뒤: 진행 중이던 안내를 이어서 (길찾기 애드온이 준비될 시간을 두고)
local resume = CreateFrame("Frame")
resume:RegisterEvent("PLAYER_LOGIN")
resume:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local t = 0
    self:SetScript("OnUpdate", function(f, el)
        t = t + el
        if t < 4 then return end
        f:SetScript("OnUpdate", nil)
        local g = RS.db and RS.db.activeGuide
        if g and g.e and g.e.uiMap then
            local mode = submitRoute(g.e, g.itemName, g.isVendor)
            if mode then startGuide(g.e, g.itemName, mode, g.isVendor) else RS.db.activeGuide = nil end
        end
    end)
end)

---------------------------------------------------------------------------
-- 창
---------------------------------------------------------------------------

local function distText(e)
    if e.dist and e.dist < 1e11 then
        local y = sqrt(e.dist)
        if y >= 1000 then return format("약 %.1fkm", y * 0.9144 / 1000) end
        return format("약 %d야드", floor(y + 0.5))
    end
    return nil
end

local function makeFrame()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "ReagentSourcePopup", UIParent, template)
    f:SetSize(WIDTH, 360)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        if RS.db then RS.db.popupPos = { p, rp, x, y } end
    end)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        f:SetBackdropBorderColor(0.4, 0.6, 0.8, 1)
    end

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(22, 22)
    f.icon:SetPoint("TOPLEFT", 12, -10)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
    f.title:SetPoint("RIGHT", f, "RIGHT", -32, 0)
    f.title:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.footer:SetPoint("BOTTOMLEFT", 12, 8)
    f.footer:SetPoint("BOTTOMRIGHT", -12, 8)
    f.footer:SetJustifyH("LEFT")
    f.footer:SetText("파란 좌표를 클릭하면 길 안내 · 현재 위치에서 가까운 순 · ESC로 닫기")

    -- 탭 (NPC 판매 / 몬스터 드랍 / ETC). 내용이 있는 탭만 보인다
    f.tabs = {}
    for i, key in ipairs({ "vendors", "drops", "etc" }) do
        local t = CreateFrame("Button", nil, f)
        t:SetHeight(20)
        t.key = key
        t.bg = t:CreateTexture(nil, "BACKGROUND")
        t.bg:SetAllPoints()
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t.text:SetPoint("CENTER")
        t:SetScript("OnClick", function(self) RS.SelectTab(self.key) end)
        f.tabs[key] = t
    end
    f.tabLine = f:CreateTexture(nil, "ARTWORK")
    f.tabLine:SetHeight(1)
    f.tabLine:SetPoint("TOPLEFT", 10, -60)
    f.tabLine:SetPoint("TOPRIGHT", -10, -60)
    if f.tabLine.SetColorTexture then f.tabLine:SetColorTexture(0.4, 0.6, 0.8, 0.6) else f.tabLine:SetTexture(0.4, 0.6, 0.8, 0.6) end

    local sf = CreateFrame("ScrollFrame", "ReagentSourcePopupScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -64)
    sf:SetPoint("BOTTOMRIGHT", -30, 26)
    content = CreateFrame("Frame", nil, sf)
    content:SetSize(WIDTH - 44, 10)
    sf:SetScrollChild(content)

    tinsert(UISpecialFrames, "ReagentSourcePopup")
    f:Hide()
    if RS.db and RS.db.popupPos then
        local p = RS.db.popupPos
        f:ClearAllPoints()
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    frame = f
end

local function getRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, content)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetPoint("LEFT", 4, 0)
    r.left:SetJustifyH("LEFT")
    r.coord = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.coord:SetPoint("RIGHT", -4, 0)
    r.coord:SetJustifyH("RIGHT")
    r.left:SetPoint("RIGHT", r.coord, "LEFT", -6, 0)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    if r.hl.SetColorTexture then r.hl:SetColorTexture(0.3, 0.6, 1, 0.15) else r.hl:SetTexture(0.3, 0.6, 1, 0.15) end
    r:SetScript("OnClick", function(self)
        if self.entry then RS.Navigate(self.entry, frame.itemName, self.isVendor) end
    end)
    r:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.entry.name, 1, 1, 1)
        GameTooltip:AddLine(RS.FormatEntry(self.entry), 0.8, 0.8, 0.8)
        if self.entry.chance then GameTooltip:AddLine(format("%s 약 %d%% (플레이어 기록 기준)", self.entry.method and "획득 확률" or "드랍률", self.entry.chance), 1, 0.65, 0.25) end
        if self.entry.giver then GameTooltip:AddLine("퀘스트 주는 NPC: " .. self.entry.giver, 1, 0.82, 0) end
        GameTooltip:AddLine(self.entry.uiMap and "클릭: 이 위치로 길 안내" or "위치 정보 없음 (안내 불가)", 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

local function setHeader(i, text, color)
    local r = getRow(i)
    r.entry = nil
    r:EnableMouse(false)
    r.left:SetText(text)
    r.left:SetTextColor(color[1], color[2], color[3])
    r.coord:SetText("")
    r:Show()
end

local function setEntry(i, e, isVendor, color)
    local r = getRow(i)
    r.entry, r.isVendor = e, isVendor
    r:EnableMouse(true)
    local extra = {}
    if e.chance then extra[#extra + 1] = e.chance .. "%" end
    local d = distText(e)
    if d then extra[#extra + 1] = d end
    local tail = #extra > 0 and ("  |cff888888" .. table.concat(extra, " · ") .. "|r") or ""
    local head = e.method and ("|cffffd100[" .. e.method .. "]|r ") or ""
    local where = e.zone and (" |cffaaaaaa- " .. e.zone .. "|r") or ""
    if e.giver then where = " |cffaaaaaa- " .. e.giver .. ", " .. e.zone .. "|r" end
    if e.noLoc then where = "" end
    r.left:SetText(head .. (e.name or "?") .. where .. tail)
    r.left:SetTextColor(color[1], color[2], color[3])
    if e.x and e.y and e.uiMap then
        r.coord:SetText(format("|cff4db8ff[%.1f, %.1f]|r", e.x, e.y))
    elseif e.x and e.y then
        r.coord:SetText(format("|cff888888(%.1f, %.1f)|r", e.x, e.y))
    else
        r.coord:SetText("")
    end
    r:Show()
end

local TAB_LABEL = { vendors = "NPC 판매", drops = "몬스터 드랍", etc = "ETC" }
local current -- 지금 보여주는 획득처 (탭 전환용)

local function layoutTabs(src)
    local x = 10
    for _, key in ipairs({ "vendors", "drops", "etc" }) do
        local t = frame.tabs[key]
        local n = #src[key]
        local show = n > 0 or (key == "etc" and src.unknown)
        if show then
            t.text:SetText(src.unknown and TAB_LABEL[key] or format("%s (%d)", TAB_LABEL[key], n))
            local w = math.max(70, t.text:GetStringWidth() + 20)
            t:SetWidth(w)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -39)
            x = x + w + 4
            t:Show()
        else
            t:Hide()
        end
    end
end

function RS.SelectTab(key)
    if not current then return end
    current.tab = key
    for k, t in pairs(frame.tabs) do
        local on = (k == key)
        if t.bg.SetColorTexture then
            t.bg:SetColorTexture(on and 0.25 or 0.1, on and 0.45 or 0.12, on and 0.7 or 0.18, on and 0.9 or 0.8)
        else
            t.bg:SetTexture(on and 0.25 or 0.1, on and 0.45 or 0.12, on and 0.7 or 0.18, on and 0.9 or 0.8)
        end
        t.text:SetTextColor(on and 1 or 0.7, on and 1 or 0.7, on and 1 or 0.7)
    end
    local list = current[key] or {}
    local color = { 1, 1, 1 }
    local i = 0
    if key == "etc" and current.unknown then
        i = 1
        setHeader(i, "습득 경로 알 수 없음", { 0.7, 0.7, 0.7 })
        i = 2
        setHeader(i, "|cff888888게임에서 직접 얻으면 자동으로 기록됩니다.|r", { 0.6, 0.6, 0.6 })
    else
        for _, e in ipairs(list) do i = i + 1; setEntry(i, e, key == "vendors", color) end
    end
    for j = i + 1, #rows do rows[j]:Hide(); rows[j].entry = nil end
    content:SetHeight(math.max(10, i * ROW_H))
    frame:SetHeight(math.min(520, math.max(150, i * ROW_H + 96)))
    local sf = _G.ReagentSourcePopupScroll
    if sf and sf.SetVerticalScroll then sf:SetVerticalScroll(0) end
end

local function showPopup(itemID)
    if not itemID then return end
    local src = RS.GetSources(itemID, true) -- 지금 위치 기준으로 새로 정렬
    local name, link, _, _, _, _, _, _, _, icon = RS.GetItemInfo(itemID)
    if not icon and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(itemID) end
    if not src then src = { vendors = {}, drops = {}, etc = {}, unknown = true } end
    if not frame then makeFrame() end
    frame.itemName = name
    frame.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    frame.title:SetText((link or name or ("아이템 " .. itemID)) .. " |cffaaaaaa획득처|r")
    current = src
    layoutTabs(src)
    local first = (#src.vendors > 0 and "vendors") or (#src.drops > 0 and "drops") or "etc"
    RS.SelectTab(first)
    frame:Show()
end

function RS.ShowPopup(itemID)
    local ok, err = pcall(showPopup, itemID)
    if not ok then RS.Print("|cffff4444획득처 창 오류:|r " .. tostring(err) .. "  (이 문구를 상수님께 알려주세요)") end
end

---------------------------------------------------------------------------
-- 단축키 (Bindings.xml 에서 호출). 마우스를 올린 아이템 기준
---------------------------------------------------------------------------
BINDING_HEADER_REAGENTSOURCE = "재료 획득처"
BINDING_NAME_REAGENTSOURCE_POPUP = "마우스 올린 재료의 획득처 전체 보기"

function ReagentSource_OpenPopup()
    local itemID = GameTooltip:IsShown() and RS.hoverItemID
    if not itemID then
        if frame and frame:IsShown() then frame:Hide() return end
        RS.Print("재료(아이템)에 마우스를 올린 상태에서 단축키를 눌러 주세요.")
        return
    end
    RS.ShowPopup(itemID)
end

---------------------------------------------------------------------------
-- 우선 단축키 (기본 F12)
--   게임 단축키보다 먼저 받기 위해 "우선 순위 덮어쓰기 바인딩"(SetOverrideBindingClick)을 쓴다.
--   · 아이템 툴팁이 떠 있을 때 누르면 → 획득처 창
--   · 아니면 → 그 키에 원래 지정된 게임 기능(예: 가방 열기)을 그대로 실행
--   저장된 게임 단축키 설정은 바꾸지 않는다. 접속할 때마다 다시 걸리며, 전투 중에는 걸 수 없어 전투 후에 건다.
---------------------------------------------------------------------------
-- 원래 기능으로 넘겨줘도 안전한 게임 단축키 (보호 기능이 아닌 것만)
local PASS_THROUGH = {
    OPENALLBAGS = true, TOGGLEBACKPACK = true, TOGGLEBAG1 = true, TOGGLEBAG2 = true,
    TOGGLEBAG3 = true, TOGGLEBAG4 = true, TOGGLEBAG5 = true, TOGGLEKEYRING = true,
    TOGGLEREAGENTBAG = true,
}

local keyButton = CreateFrame("Button", "ReagentSourceKeyButton", UIParent)
keyButton:Hide()
keyButton:RegisterForClicks("AnyDown")
keyButton:SetScript("OnClick", function()
    RS.keyPresses = (RS.keyPresses or 0) + 1
    local itemID = GameTooltip:IsShown() and RS.hoverItemID
    if itemID then
        RS.ShowPopup(itemID)
        return
    end
    local key = RS.db and RS.db.popupKey
    local action = key and GetBindingAction(key) -- 저장된(원래) 게임 단축키 기능
    if action and PASS_THROUGH[action] and RunBinding then
        pcall(RunBinding, action)
    elseif frame and frame:IsShown() then
        frame:Hide()
    end
end)

local appliedKey
function RS.ApplyPopupKey()
    if not RS.db then return end
    if InCombatLockdown and InCombatLockdown() then RS.keyPending = true; return end
    RS.keyPending = false
    if appliedKey then ClearOverrideBindings(keyButton); appliedKey = nil end
    if RS.db.popupKey == nil then RS.db.popupKey = "F12" end
    local key = RS.db.popupKey
    if key and key ~= "" and key ~= false then
        SetOverrideBindingClick(keyButton, true, key, "ReagentSourceKeyButton")
        appliedKey = key
    end
end

function RS.PopupKeyName()
    return (RS.db and RS.db.popupKey) or (GetBindingKey and GetBindingKey("REAGENTSOURCE_POPUP"))
end

RS.On("PLAYER_ENTERING_WORLD", function() RS.ApplyPopupKey() end)
RS.On("PLAYER_REGEN_ENABLED", function() if RS.keyPending then RS.ApplyPopupKey() end end)
