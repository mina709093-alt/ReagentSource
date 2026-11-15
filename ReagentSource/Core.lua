-- ReagentSource Core: 저장 데이터, 좌표, 조회/캐시
local ADDON, ns = ...
local RS = {}
ns.RS = RS

RS.cfg = {
    showHint = true,                    -- 툴팁에 "[F12] 전체 보기" 안내 줄 표시
    vendorColor = { 0.40, 0.85, 1.00 }, -- NPC 판매: 하늘색
    dropColor   = { 1.00, 0.65, 0.25 }, -- 몬스터 드랍: 주황색
    moreColor   = { 0.60, 0.60, 0.60 },
    recordClasses = { [5] = true, [7] = true }, -- 5=재료(Reagent), 7=직업용품(Tradegoods)
    useSPF = true,                      -- Shortest Path Forever 길 안내 사용 (없으면 기본 지도 핀)
    useExternal = true,                 -- ExternalData.lua(EG Link 공개 자료) 사용
}

local floor, format, pairs, ipairs, type, tonumber, tostring =
      math.floor, string.format, pairs, ipairs, type, tonumber, tostring

local function round1(v) return floor(v * 10 + 0.5) / 10 end
RS.round1 = round1

---------------------------------------------------------------------------
-- 저장 데이터 (계정 공용 SavedVariables)
---------------------------------------------------------------------------
local DB_VERSION = 1

function RS.InitDB()
    local db = _G.ReagentSourceDB
    if type(db) ~= "table" or db.dbVersion ~= DB_VERSION then
        db = { dbVersion = DB_VERSION }
        _G.ReagentSourceDB = db
    end
    db.vendors  = type(db.vendors)  == "table" and db.vendors  or {}
    db.drops    = type(db.drops)    == "table" and db.drops    or {}
    db.npcNames = type(db.npcNames) == "table" and db.npcNames or {}
    db.hostileNPC = type(db.hostileNPC) == "table" and db.hostileNPC or {}
    db.objNames   = type(db.objNames)   == "table" and db.objNames   or {}
    db.questNames = type(db.questNames) == "table" and db.questNames or {}
    db.locale = GetLocale and GetLocale() or db.locale -- 취합 시 한글 클라이언트 이름만 쓰기 위해 기록
    db.addonVersion = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata or function() end)(ADDON, "Version")
    db.sentKeys = type(db.sentKeys) == "table" and db.sentKeys or {}
    RS.db = db
end

---------------------------------------------------------------------------
-- 현재 위치 (신형 C_Map / 구형 GetPlayerMapPosition 모두 지원)
---------------------------------------------------------------------------
function RS.GetPlayerLocation()
    local zone, x, y
    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
            zone = info and info.name
            local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
            if ok and pos then
                if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
            end
        end
    elseif GetPlayerMapPosition then
        if SetMapToCurrentZone and not (WorldMapFrame and WorldMapFrame:IsShown()) then
            SetMapToCurrentZone()
        end
        x, y = GetPlayerMapPosition("player")
    end
    if not zone or zone == "" then zone = GetRealZoneText and GetRealZoneText() or GetZoneText() end
    local uiMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if x and y and (x > 0 or y > 0) then
        return zone, round1(x * 100), round1(y * 100), uiMap
    end
    return zone, nil, nil, uiMap -- 인스턴스 안 등 좌표가 없는 곳
end

function RS.PlayerFaction()
    return UnitFactionGroup and UnitFactionGroup("player") or nil
end

---------------------------------------------------------------------------
-- 아이템 분류 판정 (기록 대상인지)
---------------------------------------------------------------------------
local getInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
-- 12.x 클라이언트에서는 옛 전역 함수가 없을 수 있으므로 C_Item 을 먼저 쓴다
RS.GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo or function() end

function RS.ShouldRecord(itemID)
    if not itemID then return false end
    local static = ns.StaticData
    if static and static.watch and static.watch[itemID] then return true end
    if getInstant then
        local _, _, _, _, _, classID = getInstant(itemID)
        if classID then return RS.cfg.recordClasses[classID] == true end
    end
    -- 분류를 알 수 없는 구형 클라이언트: 기록 (불필요하면 /획득처 삭제 로 정리)
    return true
end

---------------------------------------------------------------------------
-- 조회 + 캐시
--   같은 아이템을 다시 볼 때는 미리 만든 줄을 그대로 사용한다.
--   학습 데이터가 바뀌거나 지역이 바뀌면(현재 지역 우선 정렬) 캐시를 비운다.
---------------------------------------------------------------------------
local cache = {}
local NONE = {} -- "획득처 없음"도 캐시해서 매번 검색하지 않음

function RS.Invalidate(itemID)
    if itemID then cache[itemID] = nil else wipe(cache) end
end

---------------------------------------------------------------------------
-- 지역 이름 (uiMap 번호 → 게임 클라이언트 언어의 지역명)
---------------------------------------------------------------------------
local mapNames = {}
local function mapName(uiMap)
    local n = mapNames[uiMap]
    if n == nil then
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(uiMap)
        n = info and info.name or false
        mapNames[uiMap] = n
    end
    return n or nil
end

---------------------------------------------------------------------------
-- NPC 이름: 직접 본 이름 > 설치된 한글 자료 > 게임에 NPC ID로 조회한 이름 > 영문
--   게임 조회는 서버 응답이 늦을 수 있어 대기열로 천천히 처리하고,
--   한글 이름을 얻으면 해당 아이템 캐시를 비워 다음 툴팁부터 한글로 표시한다.
---------------------------------------------------------------------------
local nameQueue, queued, tries, waiting = {}, {}, {}, {}
local lookupBroken = false
local scanTip

local function lookupName(npcID)
    if lookupBroken then return end
    local link = ("unit:Creature-0-0-0-0-%d-0000000000"):format(npcID)
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if not ok then lookupBroken = true return end
        local line = data and data.lines and data.lines[1]
        if line and line.leftText == nil and TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, line) end
        return line and line.leftText
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "ReagentSourceScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    if not pcall(scanTip.SetHyperlink, scanTip, link) then lookupBroken = true return end
    local fs = _G.ReagentSourceScanTipTextLeft1
    return fs and fs:GetText()
end

local function queueName(npcID, itemID)
    waiting[npcID] = waiting[npcID] or {}
    waiting[npcID][itemID] = true
    if queued[npcID] or (tries[npcID] or 0) >= 4 or lookupBroken then return end
    queued[npcID] = true
    nameQueue[#nameQueue + 1] = npcID
    RS.nameTicker:Show()
end

RS.nameTicker = CreateFrame("Frame")
RS.nameTicker:Hide()
local elapsedSum = 0
RS.nameTicker:SetScript("OnUpdate", function(self, elapsed)
    elapsedSum = elapsedSum + elapsed
    if elapsedSum < 0.3 then return end
    elapsedSum = 0
    for _ = 1, 5 do
        local npcID = table.remove(nameQueue, 1)
        if not npcID then self:Hide() return end
        queued[npcID] = nil
        tries[npcID] = (tries[npcID] or 0) + 1
        local ok, name = pcall(lookupName, npcID)
        if ok and name and name ~= "" and name ~= UNKNOWNOBJECT and name ~= UNKNOWN then
            if RS.db then RS.db.npcNames[npcID] = name end
            for itemID in pairs(waiting[npcID] or {}) do cache[itemID] = nil end
            waiting[npcID] = nil
        elseif (tries[npcID] or 0) < 4 then
            nameQueue[#nameQueue + 1] = npcID -- 서버 응답 대기: 나중에 다시
            queued[npcID] = true
        end
    end
end)

local function community() return ns.CommunityData or {} end

local function npcName(npcID, en, ko, itemID)
    local known = RS.db and RS.db.npcNames[npcID]
    if known then return known end
    local cm = community().npcNames
    if cm and cm[npcID] then return cm[npcID] end
    if ko then return ko end
    if GetLocale and GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then queueName(npcID, itemID) end
    return en
end

---------------------------------------------------------------------------
-- 조회 결과 합치기
---------------------------------------------------------------------------
local function entryKey(e)
    return (e.npc and ("n" .. e.npc) or e.name or "?") .. "@" .. (e.zone or "?")
end

local function add(out, seen, e)
    local k = entryKey(e)
    if seen[k] then return end -- 중복 제거 (앞에 들어간 자료 우선)
    seen[k] = true
    out[#out + 1] = e
end

-- 손으로 넣은 Data.lua / 게임에서 기록한 자료
local function collect(out, seen, list, isLearned)
    if type(list) ~= "table" then return end
    for _, e in pairs(list) do
        if type(e) == "table" and e.zone and e.name then
            local x, y = e.x, e.y
            if isLearned and e.n and e.n > 0 and e.sx then -- 드랍 좌표는 평균
                x, y = round1(e.sx / e.n), round1(e.sy / e.n)
            end
            local hideFor
            if e.faction == "Alliance" then hideFor = "Horde" elseif e.faction == "Horde" then hideFor = "Alliance" end
            local cm = community().npcNames
            local name = (e.npc and RS.db and RS.db.npcNames[e.npc]) or (e.npc and cm and cm[e.npc]) or e.name
            add(out, seen, { zone = e.zone, name = name, x = x, y = y, uiMap = e.uiMap, npc = e.npc, hideFor = hideFor })
        end
    end
end

-- 외부 데이터(ExternalData.lua)는 제작 재료(직업용품/재료 분류)일 때만 사용
local function isMaterial(itemID)
    local st = ns.StaticData
    if st and st.watch and st.watch[itemID] then return true end
    if getInstant then
        local _, _, _, _, _, classID = getInstant(itemID)
        if classID then return RS.cfg.recordClasses[classID] == true end
    end
    return true
end

local function collectExternal(vendors, seenV, drops, seenD, itemID, checked)
    local E = ns.ExternalData
    if not E or not RS.cfg.useExternal then return end
    local vlist, dlist = E.vendors[itemID], E.drops[itemID]
    if not vlist and not dlist then return end
    if not checked and not isMaterial(itemID) then return end
    for _, npcID in ipairs(vlist or {}) do
        local p, n = E.vpos[npcID], E.npc[npcID]
        local zone = p and mapName(p[1])
        if zone and n then
            add(vendors, seenV, { zone = zone, name = npcName(npcID, n[1], n[2], itemID),
                x = p[2], y = p[3], uiMap = p[1], npc = npcID, hideFor = n[3] })
        end
    end
    if dlist then
        for i = 1, #dlist, 2 do
            local npcID, chance = dlist[i], dlist[i + 1]
            local l, n = E.dloc[npcID], E.npc[npcID]
            if l and n then
                for j = 1, #l, 3 do
                    local zone = mapName(l[j])
                    if zone then
                        add(drops, seenD, { zone = zone, name = npcName(npcID, n[1], n[2], itemID),
                            x = l[j + 1], y = l[j + 2], uiMap = l[j], npc = npcID, chance = chance })
                    end
                end
            end
        end
    end
end

-- 그 외 획득 방법 (ETC): 생물 채집(무두질 등), 채집물/상자, 낚시, 아이템 열기, 퀘스트 보상
local spellNames = {}
function RS.SpellName(id)
    local n = spellNames[id]
    if n == nil then
        if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(id)
        elseif GetSpellInfo then n = (GetSpellInfo(id)) end
        spellNames[id] = n or false
    end
    return n or nil
end

local function firstLoc(l, out, base)
    -- l = { uiMap, x, y, uiMap, x, y ... } → 지역별 항목
    for j = 1, #l, 3 do
        local zone = mapName(l[j])
        if zone then
            local e = {}
            for k, v in pairs(base) do e[k] = v end
            e.zone, e.uiMap, e.x, e.y = zone, l[j], l[j + 1], l[j + 2]
            out[#out + 1] = e
        end
    end
end

local function questGiver(qid)
    -- 설치된 KQuestGuide 자료가 있으면 한글 퀘스트 제목과 퀘스트 주는 NPC 위치를 사용
    local kq = rawget(_G, "KQG_DATA")
    local row = type(kq) == "table" and kq[qid]
    if type(row) ~= "table" then return end
    local title = type(row[1]) == "string" and row[1] or nil
    local st = row[11]
    if type(st) == "table" and st[1] == "n" then
        local km = rawget(_G, "KQG_MAP")
        local uiMap = type(km) == "table" and km[st[3]]
        return title, uiMap, st[4], st[5], st[6], st[7]
    end
    return title
end

local function collectEtc(out, seen, itemID)
    local E = ns.ExternalData
    local list = E and E.etc and E.etc[itemID]
    if not list then return end
    for _, r in ipairs(list) do
        local kind = r[1]
        local tmp = {}
        if kind == "g" then -- 생물에서 무두질/채광/약초 채집/소매치기
            local n, l = E.npc[r[2]], E.dloc[r[2]]
            local base = { method = RS.SpellName(r[3]) or "채집", npc = r[2], chance = r[4],
                name = n and npcName(r[2], n[1], n[2], itemID) or ("NPC " .. r[2]) }
            if l then firstLoc(l, tmp, base) else tmp[1] = base end
        elseif kind == "o" then -- 광맥/약초/상자 등 게임 오브젝트
            local l = E.oloc[r[2]]
            local base = { method = RS.SpellName(r[3]) or "채집", obj = r[2], chance = r[4],
                name = (E.oname[r[2]] and E.oname[r[2]]:find("[\234-\237]") and E.oname[r[2]]) -- 기본 한글 이름이 있으면 그것을 우선
                    or (community().objNames or {})[r[2]] or (RS.db and RS.db.objNames[r[2]]) or E.oname[r[2]] or ("오브젝트 " .. r[2]) }
            if l then firstLoc(l, tmp, base) else tmp[1] = base end
        elseif kind == "f" then -- 낚시
            tmp[1] = { method = RS.SpellName(7620) or "낚시", name = mapName(r[2]) or "낚시터",
                zone = mapName(r[2]), chance = r[3], noLoc = true }
        elseif kind == "i" then -- 다른 아이템을 열어서 획득
            local iname = RS.GetItemInfo(r[2]) or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(r[2]))
            tmp[1] = { method = "아이템 열기", name = iname or ("아이템 " .. r[2]), itemRef = r[2], chance = r[3], noLoc = true }
        elseif kind == "q" then -- 퀘스트 보상
            local title, uiMap, x, y, giver, fac = questGiver(r[2])
            local qt = title or (RS.db and RS.db.questNames[r[2]]) or (community().questNames or {})[r[2]]
            if not qt and C_QuestLog and C_QuestLog.GetTitleForQuestID then qt = C_QuestLog.GetTitleForQuestID(r[2]) end
            local e = { method = "퀘스트 보상", name = qt or E.qname[r[2]] or ("퀘스트 " .. r[2]), quest = r[2] }
            local zone = uiMap and mapName(uiMap)
            if zone and x and y then
                e.zone, e.uiMap, e.x, e.y, e.giver = zone, uiMap, x, y, giver
                if fac == "A" then e.hideFor = "Horde" elseif fac == "H" then e.hideFor = "Alliance" end
            end
            tmp[1] = e
        end
        for _, e in ipairs(tmp) do
            local k = kind .. ":" .. tostring(r[2]) .. "@" .. tostring(e.zone)
            if not seen[k] then seen[k] = true; out[#out + 1] = e end
        end
    end
end

-- 월드 좌표 (같은 대륙이면 실제 거리로 가까운 순 정렬)
local function worldPos(uiMap, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D and uiMap and x and y) then return end
    local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, uiMap, CreateVector2D(x / 100, y / 100))
    if ok and inst and pos then
        local wx, wy = pos.x, pos.y
        if pos.GetXY then wx, wy = pos:GetXY() end
        return inst, wx, wy
    end
end

local function playerWorld()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local m = C_Map.GetBestMapForUnit("player")
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
    if not (m and ok and pos) then return end
    local px, py = pos.x, pos.y
    if pos.GetXY then px, py = pos:GetXY() end
    return worldPos(m, px * 100, py * 100)
end

local FAR = 1e12
local function sortEntries(list, curZone, isDrop)
    local pi, pwx, pwy = playerWorld()
    for _, e in ipairs(list) do
        e.dist = FAR
        if pi and e.uiMap then
            local i, wx, wy = worldPos(e.uiMap, e.x, e.y)
            if i == pi then e.dist = (wx - pwx) ^ 2 + (wy - pwy) ^ 2 end
        elseif e.zone == curZone then
            e.dist = 0
        end
    end
    table.sort(list, function(a, b)
        local ah, bh = a.zone == curZone, b.zone == curZone
        if ah ~= bh then return ah end
        if isDrop and ah then -- 현재 지역 드랍은 드랍률 높은 순
            local ac, bc = a.chance or 0, b.chance or 0
            if ac ~= bc then return ac > bc end
        end
        if a.dist ~= b.dist then return a.dist < b.dist end -- 그 외는 가까운 순
        if a.zone ~= b.zone then return (a.zone or "\255") < (b.zone or "\255") end
        return (a.name or "") < (b.name or "")
    end)
end

local function formatEntry(e)
    if not e.zone then return e.name or "?" end
    if e.x and e.y then
        return format("%s - %s (%.1f, %.1f)", e.zone, e.name, e.x, e.y)
    end
    return format("%s - %s", e.zone, e.name)
end
RS.FormatEntry = formatEntry

local function filterSort(list, curZone, myFaction, isDrop)
    local hostile = RS.db and RS.db.hostileNPC or {}
    local chostile = community().hostile or {}
    local out = {}
    for _, e in ipairs(list) do
        local hidden = myFaction and (e.hideFor == myFaction or (e.npc and (hostile[e.npc] == myFaction or chostile[e.npc] == myFaction)))
        if isDrop or not hidden then out[#out + 1] = e end
    end
    sortEntries(out, curZone, isDrop)
    return out
end

-- 아이템 획득처 전체 (가까운 순 정렬). { vendors = {...}, drops = {...} } 또는 nil
local function build(itemID, all)
    local static, db = ns.StaticData or {}, RS.db or {}
    local vendors, drops, etcList = {}, {}, {}
    local seenV, seenD, seenE = {}, {}, {}
    local cm = community()
    collect(vendors, seenV, static.vendors and static.vendors[itemID], false)
    collect(vendors, seenV, db.vendors and db.vendors[itemID], true)
    collect(vendors, seenV, cm.vendors and cm.vendors[itemID], false)
    collect(drops, seenD, static.drops and static.drops[itemID], false)
    collect(drops, seenD, db.drops and db.drops[itemID], true)
    collect(drops, seenD, cm.drops and cm.drops[itemID], false)
    if all or isMaterial(itemID) then
        collectExternal(vendors, seenV, drops, seenD, itemID, true)
        if RS.cfg.useExternal then collectEtc(etcList, seenE, itemID) end
    end
    if #vendors == 0 and #drops == 0 and #etcList == 0 then return NONE end
    local curZone = select(1, RS.GetPlayerLocation())
    local myFaction = RS.PlayerFaction()
    vendors = filterSort(vendors, curZone, myFaction, false)
    drops = filterSort(drops, curZone, myFaction, true)
    etcList = filterSort(etcList, curZone, myFaction, false)
    if #vendors == 0 and #drops == 0 and #etcList == 0 then return NONE end
    return { vendors = vendors, drops = drops, etc = etcList, at = GetTime() }
end

-- 이동하면 "가장 가까운" 대상이 바뀌므로 일정 시간이 지나면 다시 계산
local REFRESH = 15
function RS.GetSources(itemID, all)
    if all then -- 전체 보기 창: 분류와 상관없이, 지금 위치 기준으로 새로 계산
        local c = build(itemID, true)
        return c ~= NONE and c or nil
    end
    local c = cache[itemID]
    if c == nil or (c ~= NONE and GetTime() - c.at > REFRESH) then
        c = build(itemID)
        cache[itemID] = c
    end
    if c == NONE then return nil end
    return c
end

-- 툴팁용 줄: 가장 가까운 판매 NPC 1명 + 가장 가까운 드랍 몬스터 1종 (+ 전체 보기 안내)
function RS.GetLines(itemID)
    local src = RS.GetSources(itemID)
    if not src then return nil end
    local lines = {}
    local v, d = src.vendors[1], src.drops[1]
    if v then local c = RS.cfg.vendorColor; lines[#lines + 1] = { formatEntry(v), c[1], c[2], c[3] } end
    if d then local c = RS.cfg.dropColor; lines[#lines + 1] = { formatEntry(d), c[1], c[2], c[3] } end
    local total = #src.vendors + #src.drops + #src.etc
    if RS.cfg.showHint and (total > #lines) then
        local c = RS.cfg.moreColor
        local key = RS.PopupKeyName and RS.PopupKeyName()
        local parts = {}
        if #src.vendors > 0 then parts[#parts + 1] = "판매 " .. #src.vendors end
        if #src.drops > 0 then parts[#parts + 1] = "드랍 " .. #src.drops end
        if #src.etc > 0 then parts[#parts + 1] = "기타 " .. #src.etc end
        lines[#lines + 1] = { format("[%s] 전체 보기 (%s)", key or "단축키", table.concat(parts, " · ")), c[1], c[2], c[3] }
    end
    return lines
end

---------------------------------------------------------------------------
-- 이벤트 진입점
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
RS.frame = frame
RS.handlers = {}

function RS.On(event, fn)
    RS.handlers[event] = fn
    frame:RegisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local fn = RS.handlers[event]
    if fn then fn(event, ...) end
end)

RS.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    RS.InitDB()
    RS.loaded = true
    frame:UnregisterEvent("ADDON_LOADED")
    if RS.OnReady then RS.OnReady() end
end)

-- 지역이 바뀌면 "현재 지역 우선" 정렬을 다시 하도록 캐시 비우기
RS.On("ZONE_CHANGED_NEW_AREA", function() RS.Invalidate() end)

function RS.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[재료 획득처]|r " .. tostring(msg))
end
