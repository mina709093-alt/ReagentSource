-- ReagentSource MapSearch: 월드맵 위 장소 검색
--   · 월드맵을 열면 지도 위쪽에 검색창이 나옵니다. 지역 이름이나 지역 안 지명을 입력하면 결과 목록이 뜹니다.
--   · 결과를 누르면 월드맵이 그 지역 지도로 바뀌고, 그 지명의 실제 지도 좌표에 별 표시(마커)가 나옵니다.
--     OpenMap(이어 붙인 세계 지도)이 켜져 있으면 OpenMap 공개 API(OpenMapAPI)로 그 지점까지 이동·확대합니다.
--     기본 월드맵이면 SetMapID로 지도를 바꾸고, 확대 기능이 있으면 그 지점으로 확대합니다.
--   · 지명 자료는 MapSearchData.lua(게임 테이블에서 자동 생성)를 씁니다.
--   · 장소는 월드맵만 다룹니다. 미니맵, 지도 웨이포인트(C_Map.SetUserWaypoint), 길 안내는 건드리지 않습니다.
--   · (1.11.0) NPC 이름·부제로도 찾습니다(NpcSearchData.lua + 실제로 본 위치). NPC를 고르면 지도 이동에 더해
--     획득처 창과 같은 길 안내(RS.Navigate: SPF 경로 또는 지도 핀)를 시작합니다.
--   · 전투 중에는 지도를 바꾸지 않고, 전투가 끝나면 이동합니다(월드맵 오염 방지).
local _, ns = ...
local RS = ns.RS

local format, lower, gsub, sort = string.format, string.lower, string.gsub, table.sort
local min, max, floor = math.min, math.max, math.floor

local MAX_ROWS = 10        -- 한 번에 보여 줄 결과 수
local BOX_W, BOX_H = 260, 24
local ROW_H = 20
local LIST_W = 380
local MARKER_SIZE = 26     -- 화면에서 보이는 마커 크기(확대해도 같은 크기)
local ZOOM_PLACE = 0.6     -- OpenMap: 장소로 갈 때 지역 너비의 60%가 화면에 보이게
local ZOOM_ZONE = 1.1      -- OpenMap: 지역·대륙으로 갈 때 그 지도 전체가 보이게

local ACCENT = "|cff10d0a0"
local MUTED = "|cff8c99a1"

-- 별칭: 줄여 부르는 이름 → 자료의 이름(한글 또는 영문). 검색어가 별칭과 똑같을 때 정확 일치로 봅니다.
local ALIASES = {
    ["아포"] = "아이언포지", ["스톰"] = "스톰윈드", ["오그"] = "오그리마", ["언더"] = "언더시티",
    ["썬더"] = "썬더 블러프", ["썬블"] = "썬더 블러프", ["다르"] = "다르나서스", ["무법"] = "무법항",
    ["메네실"] = "메네실 항구", ["가시덤불"] = "가시덤불 골짜기", ["잿골"] = "잿빛 골짜기",
    ["if"] = "Ironforge", ["sw"] = "Stormwind City", ["og"] = "Orgrimmar", ["org"] = "Orgrimmar",
    ["uc"] = "Undercity", ["tb"] = "Thunder Bluff", ["darn"] = "Darnassus", ["bb"] = "Booty Bay",
    ["stv"] = "Stranglethorn Vale",
}

local function isKorean()
    return not GetLocale or GetLocale() == "koKR"
end

-- 검색용 글자: 영문 소문자로, 띄어쓰기와 기호(' - : . 등)는 뺍니다. 한글은 그대로입니다.
local function normalize(s)
    if type(s) ~= "string" then return "" end
    return (gsub(lower(s), "[%s%p]", ""))
end

---------------------------------------------------------------------------
-- 검색 목록 (처음 검색할 때 한 번 만듭니다)
--   { kind = "continent" | "zone" | "place", ko, en, map, x, y(0~1), zoneKo/zoneEn, contKo/contEn, kKo, kEn }
---------------------------------------------------------------------------
local index
local aliasKeys   -- [정리한 별칭] = 정리한 대상 이름

local function buildIndex()
    local D = ns.MapSearchData
    index = {}
    aliasKeys = {}
    for k, v in pairs(ALIASES) do aliasKeys[normalize(k)] = normalize(v) end
    if type(D) ~= "table" or type(D.maps) ~= "table" or type(D.places) ~= "table" then return index end
    local world = D.world or { "아제로스", "Azeroth" }
    local function contNames(contID)
        local c = contID and D.maps[contID]
        if c then return c[1], c[2] end
        return world[1], world[2]
    end
    for id, m in pairs(D.maps) do
        local e = { map = id, ko = m[1], en = m[2] }
        if m[3] == 2 then
            e.kind = "continent"
        else
            e.kind = "zone"
            e.contKo, e.contEn = contNames(m[4])
        end
        index[#index + 1] = e
    end
    for _, p in ipairs(D.places) do
        local zone = D.maps[p[3]]
        -- 지역 지도와 이름이 같은 지명(지역 자체)은 지역 결과와 겹치므로 뺍니다.
        if zone and p[1] ~= zone[1] then
            local e = { kind = "place", ko = p[1], en = p[2], map = p[3], x = p[4] / 100, y = p[5] / 100,
                zoneKo = zone[1], zoneEn = zone[2] }
            e.contKo, e.contEn = contNames(zone[4])
            index[#index + 1] = e
        end
    end
    -- NPC (1.11.0): QuestieDB 자료 + 취합 자료(CommunityData.npcSpots) + 내 기록(ReagentSourceDB.npcSpots)
    --   같은 NPC·같은 지도면 내 기록 → 취합 자료 → QuestieDB 순으로 위치를 고릅니다. 앞의 둘은 "확인됨"
    local function addNpc(id, ko, en, sub, fac, rank, map, x, y, seen)
        local zone = D.maps[map]
        if not zone or not x or not y then return end
        local e = { kind = "npc", id = id, ko = ko or en, en = en or ko, sub = sub, fac = fac, rank = rank,
            map = map, x = x / 100, y = y / 100, zoneKo = zone[1], zoneEn = zone[2], seen = seen }
        e.contKo, e.contEn = contNames(zone[4])
        index[#index + 1] = e
    end
    local mine = RS.db and type(RS.db.npcSpots) == "table" and RS.db.npcSpots or {}
    local cm = ns.CommunityData and type(ns.CommunityData.npcSpots) == "table" and ns.CommunityData.npcSpots or {}
    local function seenSpot(id, map)
        local m = mine[id] and type(mine[id].m) == "table" and mine[id].m[map]
        if m and m.x and m.y then return m.x, m.y end
        local c = cm[id] and type(cm[id].m) == "table" and cm[id].m[map]
        if c then return c[1], c[2] end
    end
    local known = {}
    for _, r in ipairs(ns.NpcSearchData or {}) do
        local id = r[1]
        local done = {}
        known[id] = { ko = r[2] or nil, en = r[3], done = done }
        for i = 7, #r, 3 do
            local map = r[i]
            local sx, sy = seenSpot(id, map)
            addNpc(id, r[2] or nil, r[3], r[4] or nil, r[5], r[6], map, sx or r[i + 1], sy or r[i + 2], sx ~= nil)
            done[map] = true
        end
    end
    -- 자료에 없는 NPC나 자료에 없는 지도의 위치
    local function addSeen(src, isMine)
        for id, e in pairs(src) do
            local k = known[id]
            if not k then k = { done = {} }; known[id] = k end
            for map, s in pairs(type(e.m) == "table" and e.m or {}) do
                local x, y
                if isMine then x, y = s.x, s.y else x, y = s[1], s[2] end
                if not k.done[map] and x and y then
                    local name = k.ko or e.name or k.en
                    addNpc(id, name, k.en or name, nil, nil, nil, map, x, y, true)
                    k.done[map] = true
                end
            end
        end
    end
    addSeen(mine, true)
    addSeen(cm, false)

    for _, e in ipairs(index) do
        e.kKo, e.kEn = normalize(e.ko), normalize(e.en)
        if e.sub then e.kSub = normalize(e.sub) end
    end
    return index
end

local KIND_ORDER = { continent = 0, zone = 1, place = 2, npc = 3 }

-- 한 이름(정리한 글자)과 검색어의 점수: 0 정확, 1 앞부분 일치, 2 중간 일치, nil 안 맞음
local function scoreKey(key, q)
    if key == "" then return nil end
    if key == q then return 0 end
    local s = key:find(q, 1, true)
    if s == 1 then return 1 end
    if s then return 2 end
end

-- 검색: 결과 목록(점수 순)과 전체 개수를 돌려줍니다.
local function search(text)
    local q = normalize(text)
    if q == "" then return {}, 0 end
    if not index then buildIndex() end
    local alias = aliasKeys[q]
    local found = {}
    for _, e in ipairs(index) do
        local sk, se = scoreKey(e.kKo, q), scoreKey(e.kEn, q)
        local s = sk
        if se and (not s or se < s) then s = se end
        if alias and (e.kKo == alias or e.kEn == alias) then s = 0 end
        -- NPC 부제(예: 그리핀 조련사)로도 찾습니다. 이름보다 한 단계 뒤
        if e.kSub and not s then
            local ss = scoreKey(e.kSub, q)
            if ss then s = (ss == 0) and 1 or 2 end
        end
        if s then
            found[#found + 1] = { e = e, s = s, byEn = (se ~= nil and (sk == nil or se < sk)) }
        end
    end
    local ko = isKorean()
    sort(found, function(a, b)
        if a.s ~= b.s then return a.s < b.s end
        local ka, kb = KIND_ORDER[a.e.kind], KIND_ORDER[b.e.kind]
        if ka ~= kb then return ka < kb end
        local na, nb = ko and a.e.ko or a.e.en, ko and b.e.ko or b.e.en
        if #na ~= #nb then return #na < #nb end
        if na ~= nb then return na < nb end
        return (a.e.map or 0) < (b.e.map or 0)
    end)
    return found, #found
end

-- 결과 한 줄 글: "장소명 | 소속 지역 | 대륙"
local function rowText(r)
    local e, ko = r.e, isKorean()
    local name = ko and e.ko or e.en
    local extra = ""
    if ko and r.byEn and e.en and e.en ~= e.ko then extra = MUTED .. " (" .. e.en .. ")|r" end
    if e.kind == "continent" then
        return format("|cffffffff%s|r%s  %s| 대륙|r", name, extra, MUTED)
    elseif e.kind == "zone" then
        return format("|cffffffff%s|r%s  %s| %s|r  %s(지역)|r", name, extra, MUTED, ko and e.contKo or e.contEn, ACCENT)
    elseif e.kind == "npc" then
        -- "[NPC] 이름 <부제> | 지역 | 대륙 (희귀)(얼라이언스)(확인됨)"
        local tags = ""
        if e.rank == 2 or e.rank == 4 then tags = tags .. " |cffc0c0ff(희귀)|r" end
        local my = RS.PlayerFaction and RS.PlayerFaction()
        if e.fac == "A" or e.fac == "H" then
            local mineFac = (e.fac == "A" and my == "Alliance") or (e.fac == "H" and my == "Horde")
            tags = tags .. (mineFac and MUTED or "|cffff6060") .. (e.fac == "A" and " (얼라이언스)" or " (호드)") .. "|r"
        end
        if e.seen then tags = tags .. ACCENT .. " (확인됨)|r" end
        local sub = e.sub and (MUTED .. " <" .. e.sub .. ">|r") or ""
        return format("|cffffd100[NPC]|r |cffffffff%s|r%s%s  %s| %s | %s|r%s", name, sub, extra, MUTED,
            ko and e.zoneKo or e.zoneEn, ko and e.contKo or e.contEn, tags)
    end
    return format("|cffffffff%s|r%s  %s| %s | %s|r", name, extra, MUTED,
        ko and e.zoneKo or e.zoneEn, ko and e.contKo or e.contEn)
end

---------------------------------------------------------------------------
-- 지도 제어
---------------------------------------------------------------------------
local function worldMap()
    local wm = rawget(_G, "WorldMapFrame")
    if type(wm) == "table" and wm.GetMapID then return wm end
end

-- OpenMap이 이어 붙인 지도를 보여 주고 있으면 그 API를 돌려줍니다.
local function openMapApi()
    local api = rawget(_G, "OpenMapAPI")
    if type(api) ~= "table" or type(api.IsStitched) ~= "function" or type(api.WorldFromMap) ~= "function"
        or type(api.ShowWorld) ~= "function" then return nil end
    local ok, stitched = pcall(api.IsStitched)
    if ok and stitched then return api end
end

local marker              -- 마커 프레임 (아래에서 만듦)
local target              -- 마커 위치 { map, x, y } 또는 { u, v } (OpenMap 세계 좌표)
local pending             -- 전투 중이라 미뤄 둔 이동
local showMarker, hideMarker, markerLevel

-- 기본 월드맵: 그 지점으로 확대 (확대 기능이 없거나 확대 단계가 하나뿐이면 지도만 바꿉니다)
local function zoomTo(wm, mapID, x, y)
    local sc = wm.ScrollContainer
    if not (sc and sc.InstantPanAndZoom and sc.GetScaleForMaxZoom and sc.GetScaleForMinZoom) then return false end
    if wm:GetMapID() ~= mapID then return false end
    local ok = pcall(function()
        local lo, hi = sc:GetScaleForMinZoom(), sc:GetScaleForMaxZoom()
        if type(lo) ~= "number" or type(hi) ~= "number" or hi <= lo * 1.01 then error("no zoom") end
        sc:InstantPanAndZoom(hi, x, y)
    end)
    return ok
end

local function setMap(wm, mapID)
    if wm:GetMapID() == mapID then return true end
    local ok = pcall(wm.SetMapID, wm, mapID)
    return ok and wm:GetMapID() == mapID
end

local function mapRect(api, mapID)
    local l, t = api.WorldFromMap(mapID, 0, 0)
    local r, b = api.WorldFromMap(mapID, 1, 1)
    if l and t and r and b and r > l then return l, t, r, b end
end

local function go(e)
    local wm = worldMap()
    if not (e and wm and wm:IsShown()) then return false end
    if InCombatLockdown and InCombatLockdown() then
        pending = e
        RS.Print("전투 중에는 월드맵을 옮기지 않습니다. 전투가 끝나면 '" .. (isKorean() and e.ko or e.en) .. "'(으)로 이동합니다.")
        return false
    end
    pending = nil
    hideMarker()

    -- OpenMap 이어 붙인 지도
    local api = openMapApi()
    if api then
        local ok, moved = pcall(function()
            local l, t, r, b = mapRect(api, e.map)
            if not l then return false end
            if e.kind == "place" or e.kind == "npc" then
                local u, v = api.WorldFromMap(e.map, e.x, e.y)
                if not u then return false end
                api.ShowWorld(u, v, 1 / ((r - l) * ZOOM_PLACE))
                target = { u = u, v = v, name = e.ko, nameEn = e.en }
                showMarker()
            else
                api.ShowWorld((l + r) / 2, (t + b) / 2, 1 / ((r - l) * ZOOM_ZONE))
            end
            return true
        end)
        if ok and moved then return true end
        -- (이어 붙인 지도에 없는 지도면 아래의 기본 방법으로)
    end

    -- 기본 월드맵
    if not setMap(wm, e.map) then
        RS.Print("이 지도를 열 수 없습니다: " .. (isKorean() and e.ko or e.en))
        return false
    end
    if e.kind == "place" or e.kind == "npc" then
        target = { map = e.map, x = e.x, y = e.y, name = e.ko, nameEn = e.en }
        showMarker()
        -- 지도가 바뀐 다음 화면 크기가 잡힌 뒤에 확대합니다.
        local function later() if target and target.map == e.map then zoomTo(wm, e.map, e.x, e.y) end end
        if C_Timer and C_Timer.After then C_Timer.After(0, later) else later() end
    end
    return true
end

---------------------------------------------------------------------------
-- 마커: 지도 캔버스 위에 직접 그리는 별 표시와 이름 (지도 웨이포인트는 쓰지 않음)
---------------------------------------------------------------------------
local function canvasOf(wm)
    local c = wm.GetCanvas and wm:GetCanvas()
    if not c and wm.ScrollContainer then c = wm.ScrollContainer.Child end
    return c
end

-- 지금 캔버스 위의 마커 자리(0~1, 캔버스 기준). 보이면 안 되면 nil
local function markerPos(wm)
    if not target then return end
    if target.u then
        local api = openMapApi()
        if not (api and type(api.MapFromWorld) == "function") then return end
        local ok, x, y = pcall(api.MapFromWorld, wm:GetMapID(), target.u, target.v)
        if ok and x and y then return x, y end
        return
    end
    if wm:GetMapID() == target.map then return target.x, target.y end
end

local function updateMarker(self)
    local wm = worldMap()
    local canvas = wm and canvasOf(wm)
    local x, y
    if canvas and wm:IsShown() then x, y = markerPos(wm) end
    if not x then
        -- 기본 지도에서 다른 지도로 바꾸면 마커를 지웁니다(OpenMap은 이어진 지도라 계속 보임).
        if target and target.map and wm and wm:GetMapID() ~= target.map then target = nil end
        self.dot:Hide(); self.label:Hide(); self.ring:Hide()
        if not target then self:Hide() end
        return
    end
    local sc = wm.ScrollContainer
    local scale = sc and sc.GetCanvasScale and sc:GetCanvasScale() or 1
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    self:SetScale(1 / scale)
    local cw, ch = canvas:GetWidth() * scale, canvas:GetHeight() * scale
    self:ClearAllPoints()
    self:SetPoint("CENTER", canvas, "TOPLEFT", x * cw, -y * ch)
    self.dot:Show(); self.label:Show(); self.ring:Show()
    -- OpenMap은 지도 그림을 나중에 더 높은 층에 그릴 수 있어서, 마커 층을 가끔 다시 맞춥니다.
    self.lv = (self.lv or 0) + (self.elapsed or 0)
    if self.lv > 0.5 then
        self.lv = 0
        local lvl = markerLevel(wm, canvas)
        if self:GetFrameLevel() ~= lvl then self:SetFrameLevel(lvl) end
    end
    -- 고리를 천천히 깜빡여 눈에 띄게
    self.t = (self.t or 0) + (self.elapsed or 0)
    local a = 0.35 + 0.35 * math.abs(math.sin(self.t * 3))
    self.ring:SetAlpha(a)
end

local function ensureMarker()
    if marker then return marker end
    local wm = worldMap()
    local canvas = wm and canvasOf(wm)
    if not canvas then return end
    local f = CreateFrame("Frame", nil, canvas)
    f:SetSize(MARKER_SIZE, MARKER_SIZE)
    f:EnableMouse(false)
    local ring = f:CreateTexture(nil, "ARTWORK")
    ring:SetTexture("Interface\\Buttons\\WHITE8X8")
    ring:SetVertexColor(0.063, 0.816, 0.627, 1)
    ring:SetSize(MARKER_SIZE + 10, MARKER_SIZE + 10)
    ring:SetPoint("CENTER")
    if ring.SetRotation then pcall(ring.SetRotation, ring, math.pi / 4) end
    f.ring = ring
    local dot = f:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    dot:SetAllPoints()
    f.dot = dot
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", f, "BOTTOM", 0, -4)
    label:SetTextColor(1, 1, 1)
    if label.SetShadowOffset then label:SetShadowOffset(1, -1) end
    f.label = label
    f:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = elapsed
        local ok, err = pcall(updateMarker, self)
        if not ok then
            -- 마커만 숨기고 계속 시도합니다. 같은 오류는 한 번만 알립니다(원인 확인용).
            self.dot:Hide(); self.label:Hide(); self.ring:Hide()
            if self.lastErr ~= tostring(err) then
                self.lastErr = tostring(err)
                RS.Print("|cffff4444장소 검색 마커 오류:|r " .. self.lastErr .. "  (이 문구를 상수님께 알려주세요)")
            end
        end
    end)
    f:Hide()
    marker = f
    return f
end

markerLevel = function(wm, canvas)
    local level = (canvas:GetFrameLevel() or 0) + 100
    local api = rawget(_G, "OpenMapAPI")
    if type(api) == "table" and type(api.ArtTopLevel) == "function" then
        local ok, top = pcall(api.ArtTopLevel)
        if ok and type(top) == "number" then level = max(level, top + 10) end
    end
    return min(level, 9000)
end

showMarker = function()
    local f = ensureMarker()
    if not (f and target) then return end
    local wm = worldMap()
    f:SetFrameLevel(markerLevel(wm, canvasOf(wm)))
    f.label:SetText(isKorean() and target.name or target.nameEn or target.name)
    f.t = 0
    f:Show()
end

hideMarker = function()
    target = nil
    if marker then marker:Hide() end
end

---------------------------------------------------------------------------
-- 검색창과 결과 목록
---------------------------------------------------------------------------
local box, edit, hint, clearBtn, list
local rows = {}
local results, total = {}, 0

local function setBackdrop(f, bg, edge)
    if not f.SetBackdrop then return end
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
end

local function hideList()
    if list then list:Hide() end
end

local function choose(i)
    local r = results[i]
    if not r then return end
    hideList()
    if edit then
        edit.choosing = true
        edit:SetText(isKorean() and r.e.ko or r.e.en)
        edit.choosing = nil
        edit:ClearFocus()
    end
    go(r.e)
    -- NPC는 지도 이동과 함께 길 안내(획득처 창과 같은 방식: SPF가 있으면 경로, 없으면 지도 핀)
    if r.e.kind == "npc" and RS.Navigate then
        local e = r.e
        local nav = { uiMap = e.map, x = floor(e.x * 1000 + 0.5) / 10, y = floor(e.y * 1000 + 0.5) / 10,
            name = isKorean() and e.ko or e.en, zone = isKorean() and e.zoneKo or e.zoneEn, npc = e.id,
            label = "NPC 찾기" }
        local ok, err = pcall(RS.Navigate, nav, nil, true)
        if not ok then RS.Print("|cffff4444NPC 길 안내 오류:|r " .. tostring(err)) end
    end
end

local function makeRow(i)
    local b = CreateFrame("Button", nil, list)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4 - (i - 1) * ROW_H)
    b:SetPoint("RIGHT", list, "RIGHT", -4, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\WHITE8X8")
    hl:SetVertexColor(0.06, 0.40, 0.32, 0.6)
    hl:SetAllPoints()
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", 6, 0)
    t:SetPoint("RIGHT", -6, 0)
    t:SetJustifyH("LEFT")
    if t.SetWordWrap then t:SetWordWrap(false) end
    b.text = t
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function(self) choose(self.index) end)
    rows[i] = b
    return b
end

local function refreshList()
    if not (box and list and edit) then return end
    local text = edit:GetText() or ""
    if normalize(text) == "" then hideList(); return end
    results, total = search(text)
    local shown = min(#results, MAX_ROWS)
    local lines = shown
    for i = 1, shown do
        local b = rows[i] or makeRow(i)
        b.index = i
        b.text:SetText(rowText(results[i]))
        b:EnableMouse(true)
        b:Show()
    end
    local extraLine
    if total == 0 then
        extraLine = MUTED .. "검색 결과가 없습니다. 다른 이름이나 영문으로 찾아보세요.|r"
    elseif total > shown then
        extraLine = MUTED .. format("결과가 %d개 더 있습니다. 더 자세히 입력해 보세요.", total - shown) .. "|r"
    end
    if extraLine then
        lines = lines + 1
        local b = rows[lines] or makeRow(lines)
        b.index = nil
        b.text:SetText(extraLine)
        b:EnableMouse(false)
        b:Show()
    end
    for i = lines + 1, #rows do rows[i]:Hide() end
    list:SetHeight(lines * ROW_H + 8)
    list:Show()
end

local function resetSearch()
    if edit then
        edit.choosing = true
        edit:SetText("")
        edit.choosing = nil
        edit:ClearFocus()
    end
    results, total = {}, 0
    hideList()
end

-- 검색창 자리: 저장한 위치(지도 위쪽 가운데에서 떨어진 거리)가 있으면 그 자리
local function placeBox()
    local wm = worldMap()
    local sc = wm and wm.ScrollContainer or wm
    if not (box and sc) then return end
    local pos = RS.db and type(RS.db.mapSearchPos) == "table" and RS.db.mapSearchPos or nil
    local dx = pos and tonumber(pos.x) or 0
    local dy = pos and tonumber(pos.y) or -6
    box:ClearAllPoints()
    box:SetPoint("TOP", sc, "TOP", dx, dy)
end

local function savePos()
    local wm = worldMap()
    local sc = wm and wm.ScrollContainer or wm
    if not (box and sc and RS.db) then return end
    local bs, ss = box:GetEffectiveScale(), sc:GetEffectiveScale()
    local bx, by = box:GetCenter()
    local sx = sc:GetCenter()
    local btop, stop = box:GetTop(), sc:GetTop()
    if not (bx and sx and btop and stop) then return end
    local dx = (bx * bs - sx * ss) / bs
    local dy = (btop * bs - stop * ss) / bs
    RS.db.mapSearchPos = { x = floor(dx + 0.5), y = floor(dy + 0.5) }
end

local function createBox(wm)
    local sc = wm.ScrollContainer or wm
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    box = CreateFrame("Frame", nil, wm, template)
    box:SetSize(BOX_W, BOX_H)
    box:SetFrameLevel(min((sc:GetFrameLevel() or 0) + 9600, 9900))
    box:SetMovable(true)
    box:SetClampedToScreen(true)
    setBackdrop(box, { 0.035, 0.055, 0.065, 0.92 }, { 0.063, 0.816, 0.627, 0.9 })

    -- 왼쪽 손잡이: 끌어서 옮기기, 오른쪽 클릭은 원래 자리
    local grip = CreateFrame("Button", nil, box)
    grip:SetSize(20, BOX_H - 4)
    grip:SetPoint("LEFT", 2, 0)
    local gt = grip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gt:SetPoint("CENTER")
    gt:SetText(ACCENT .. "≡|r")
    grip:RegisterForDrag("LeftButton")
    grip:RegisterForClicks("RightButtonUp")
    grip:SetScript("OnDragStart", function() box:StartMoving() end)
    grip:SetScript("OnDragStop", function()
        box:StopMovingOrSizing()
        savePos()
        placeBox()
    end)
    grip:SetScript("OnClick", function()
        if RS.db then RS.db.mapSearchPos = nil end
        placeBox()
    end)
    grip:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("장소 검색 (재료 획득처)")
        GameTooltip:AddLine("끌기: 검색창 옮기기", 1, 1, 1)
        GameTooltip:AddLine("오른쪽 클릭: 원래 자리로", 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    edit = CreateFrame("EditBox", nil, box)
    edit:SetPoint("TOPLEFT", 24, -2)
    edit:SetPoint("BOTTOMRIGHT", -24, 2)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal or GameFontHighlight)
    edit:SetMaxLetters(40)
    edit:SetTextInsets(2, 2, 0, 0)

    hint = edit:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 3, 0)
    hint:SetText("장소·NPC 검색 (예: 모건의 망루, 들창코)")

    clearBtn = CreateFrame("Button", nil, box)
    clearBtn:SetSize(20, BOX_H - 4)
    clearBtn:SetPoint("RIGHT", -2, 0)
    local ct = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ct:SetPoint("CENTER")
    ct:SetText(MUTED .. "×|r")
    clearBtn.text = ct
    clearBtn:SetScript("OnClick", function() resetSearch(); hideMarker() end)
    clearBtn:SetScript("OnEnter", function() ct:SetText("|cffffffff×|r") end)
    clearBtn:SetScript("OnLeave", function() ct:SetText(MUTED .. "×|r") end)
    clearBtn:Hide()

    list = CreateFrame("Frame", nil, box, template)
    list:SetWidth(LIST_W)
    list:SetPoint("TOP", box, "BOTTOM", 0, -2)
    list:SetFrameLevel((box:GetFrameLevel() or 0) + 5)
    setBackdrop(list, { 0.02, 0.035, 0.042, 0.95 }, { 0.20, 0.25, 0.28, 1 })
    list:Hide()

    local function updateHint()
        local has = (edit:GetText() or "") ~= ""
        if has then hint:Hide(); clearBtn:Show() else clearBtn:Hide(); if not edit:HasFocus() then hint:Show() end end
    end
    edit:SetScript("OnTextChanged", function(self)
        updateHint()
        if self.choosing then return end
        local ok, err = pcall(refreshList)
        if not ok then RS.Print("|cffff4444장소 검색 오류:|r " .. tostring(err)) end
    end)
    edit:SetScript("OnEditFocusGained", function() hint:Hide(); pcall(refreshList) end)
    edit:SetScript("OnEditFocusLost", function() updateHint() end)
    edit:SetScript("OnEscapePressed", function() resetSearch(); updateHint() end)
    edit:SetScript("OnEnterPressed", function(self)
        if results[1] and normalize(self:GetText()) ~= "" then choose(1) else self:ClearFocus() end
    end)
    placeBox()
end

---------------------------------------------------------------------------
-- 월드맵에 붙이기
---------------------------------------------------------------------------
local hooked = false

local function onMapShow()
    local wm = worldMap()
    if not wm then return end
    if not box then createBox(wm) else placeBox() end
    box:Show()
end

local function onMapHide()
    pending = nil
    resetSearch()
    hideMarker()
end

local function hookMap()
    if hooked then return true end
    local wm = worldMap()
    if not (wm and wm.HookScript) then return false end
    hooked = true
    wm:HookScript("OnShow", function() local ok, err = pcall(onMapShow); if not ok then RS.Print("|cffff4444장소 검색 오류:|r " .. tostring(err)) end end)
    wm:HookScript("OnHide", function() pcall(onMapHide) end)
    if wm:IsShown() then pcall(onMapShow) end
    return true
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then
            local e = pending
            pending = nil
            local wm = worldMap()
            if wm and wm:IsShown() then pcall(go, e) end
        end
        return
    end
    if event == "ADDON_LOADED" and arg1 ~= "Blizzard_WorldMap" then return end
    if hookMap() then
        self:UnregisterEvent("ADDON_LOADED")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- Reset: NPC 위치 기록이 바뀌면 다음 검색 때 목록을 다시 만듭니다(NpcSpots.lua에서 부름)
RS.MapSearch = { Search = search, Go = go, Normalize = normalize, Choose = choose,
    Reset = function() index = nil end, Results = function() return results end }
