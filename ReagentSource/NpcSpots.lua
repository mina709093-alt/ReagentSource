-- ReagentSource NpcSpots: 게임 안에서 실제로 본 NPC 위치 기록 (월드맵 NPC 검색용, 1.11.0)
--   · 자료(NpcSearchData.lua = QuestieDB, CommunityData.lua의 npcSpots)에 없는 NPC를 가까이(약 10야드)에서 보면 → 새 NPC로 기록
--   · NPC와 대화(상인·퀘스트·훈련사·비행 조련사·은행 등)했는데 그 지도에 자료 위치가 없거나 30야드 넘게 다르면 → 실제 위치로 기록
--   · 플레이어가 서 있는 곳을 NPC 위치로 씁니다(대화 거리 안이므로 몇 야드 차이). 여러 번 보면 평균(최대 20번)을 씁니다.
--   · 기록은 ReagentSourceDB.npcSpots에 쌓이고, 파티/길드 공유(Sync.lua, 키 "p:NPC번호:지도번호")와
--     "파일 보내 주세요" 알림(Contrib.lua)에 함께 들어갑니다. 취합하면 CommunityData.lua의 npcSpots가 됩니다.
local _, ns = ...
local RS = ns.RS

local floor, sqrt, type, pairs, tonumber = math.floor, math.sqrt, type, pairs, tonumber
local MOVED_YARDS = 30        -- 자료 위치와 이만큼 넘게 다르면 "실제 위치"로 기록
local MOVED_UNITS = 2.0       -- 야드로 바꿀 수 없을 때: 지도 좌표(0~100) 차이
local MAX_AVG = 20            -- 위치 평균은 최대 20번 관측까지

local issecret = rawget(_G, "issecretvalue")
local function ok(v) return v ~= nil and not (issecret and issecret(v)) end
local function round1(v) return floor(v * 10 + 0.5) / 10 end

local NS = {}
RS.NpcSpots = NS

---------------------------------------------------------------------------
-- 애드온 자료 (처음 쓸 때 한 번 색인)
--   questie[번호] = { [지도] = { x, y } },  community = CommunityData.npcSpots
---------------------------------------------------------------------------
local questie
local function buildQuestie()
    questie = {}
    for _, r in ipairs(ns.NpcSearchData or {}) do
        local t = {}
        for i = 7, #r, 3 do t[r[i]] = { r[i + 1], r[i + 2] } end
        questie[r[1]] = t
    end
end

local function community()
    local cm = ns.CommunityData
    return cm and type(cm.npcSpots) == "table" and cm.npcSpots or {}
end

-- 이 NPC가 자료(QuestieDB 또는 취합 자료)에 있는지
function NS.InData(id)
    if not questie then buildQuestie() end
    return questie[id] ~= nil or community()[id] ~= nil
end

-- 두 점 사이 거리(야드). 바꿀 수 없으면 nil
local function yards(map, x1, y1, x2, y2)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local good, d = pcall(function()
        local _, a = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x1 / 100, y1 / 100))
        local _, b = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x2 / 100, y2 / 100))
        local ax, ay = a.x, a.y
        local bx, by = b.x, b.y
        if a.GetXY then ax, ay = a:GetXY() end
        if b.GetXY then bx, by = b:GetXY() end
        return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
    end)
    if good and type(d) == "number" then return d end
end

local function near(map, x1, y1, x2, y2)
    local d = yards(map, x1, y1, x2, y2)
    if d then return d <= MOVED_YARDS end
    return math.abs(x1 - x2) <= MOVED_UNITS and math.abs(y1 - y2) <= MOVED_UNITS
end

-- 애드온 자료의 이 지도 위치(취합 자료가 먼저)
local function shippedSpot(id, map)
    local c = community()[id]
    local s = c and c.m and c.m[map]
    if s then return s[1], s[2] end
    if not questie then buildQuestie() end
    local q = questie[id] and questie[id][map]
    if q then return q[1], q[2] end
end

-- 이 위치가 이미 애드온 자료와 맞는지
function NS.Shipped(id, map, x, y)
    local sx, sy = shippedSpot(id, map)
    return sx ~= nil and near(map, x, y, sx, sy)
end

---------------------------------------------------------------------------
-- 내 위치를 장소 검색 지도(MapSearchData.maps)의 좌표로
--   건물·동굴 같은 작은 지도에 있으면 그 위 지역 지도로 바꿉니다.
---------------------------------------------------------------------------
local function searchMaps()
    local D = ns.MapSearchData
    return D and D.maps or {}
end

function NS.PlayerSpot()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local map = C_Map.GetBestMapForUnit("player")
    if not ok(map) or not map then return end
    local good, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not (good and pos) then return end
    local x, y = pos.x, pos.y
    if pos.GetXY then x, y = pos:GetXY() end
    if not (ok(x) and ok(y) and x and y and (x > 0 or y > 0)) then return end
    local maps = searchMaps()
    local guard = 0
    while map and not maps[map] and guard < 5 do
        guard = guard + 1
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        local parent = info and info.parentMapID
        if not parent or parent == 0 or not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos) then return end
        local good2, px, py = pcall(function()
            local cont, world = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y))
            local _, p = C_Map.GetMapPosFromWorldPos(cont, world, parent)
            if p.GetXY then return p:GetXY() end
            return p.x, p.y
        end)
        if not (good2 and px and py) then return end
        map, x, y = parent, px, py
    end
    if not maps[map] or maps[map][3] == 2 then return end -- 대륙 지도 좌표는 쓰지 않음
    if x <= 0 or y <= 0 or x >= 1 or y >= 1 then return end
    return map, round1(x * 100), round1(y * 100)
end

---------------------------------------------------------------------------
-- 기록
---------------------------------------------------------------------------
local function changed()
    if RS.MapSearch and RS.MapSearch.Reset then RS.MapSearch.Reset() end
    RS.Invalidate()
end

-- fixed: 대화한 NPC(자리를 지키는 NPC). 아니면 자료에 없는 새 NPC만 기록합니다.
local function record(id, name, map, x, y, fixed)
    local db = RS.db
    if not (db and id and name and name ~= "" and map and x and y) then return false end
    local e = type(db.npcSpots) == "table" and db.npcSpots[id] or nil
    local s = e and e.m and e.m[map]
    if not s then
        local known = NS.InData(id)
        if known and not fixed then return false end          -- 아는 NPC는 대화했을 때만
        if known and NS.Shipped(id, map, x, y) then return false end -- 자료 위치와 같음
        db.npcSpots = type(db.npcSpots) == "table" and db.npcSpots or {} -- 처음 기록할 때 만듦
        if not e then e = { name = name, m = {} }; db.npcSpots[id] = e end
        e.m = type(e.m) == "table" and e.m or {}
        e.m[map] = { x = x, y = y, n = 1, sx = x, sy = y }
        e.name = name
        changed()
        return true
    end
    -- 이미 기록한 자리: 내 관측으로 평균을 다듬습니다(받은 기록이면 내 기록으로 바꿈)
    local wasRx = s.rx ~= nil
    s.rx = nil
    e.name = name
    if (s.n or 0) < MAX_AVG then
        s.n = (s.n or 0) + 1
        s.sx, s.sy = (s.sx or 0) + x, (s.sy or 0) + y
        s.x, s.y = round1(s.sx / s.n), round1(s.sy / s.n)
    end
    if wasRx then changed() end
    return true
end
NS.Record = record

local function unitInfo(unit)
    local exists = UnitExists(unit)
    if not ok(exists) or not exists then return end
    local isPlayer = UnitIsPlayer(unit)
    if not ok(isPlayer) or isPlayer then return end
    if UnitPlayerControlled then
        local pc = UnitPlayerControlled(unit)
        if not ok(pc) or pc then return end -- 소환수·토템 등은 빼기
    end
    local guid, name = UnitGUID(unit), UnitName(unit)
    if not (ok(guid) and ok(name)) or not name or name == "" then return end
    local id, isNPC = RS.ParseGUID(guid)
    if not isNPC or not id then return end
    return id, name
end

local function seeUnit(unit, fixed)
    local id, name = unitInfo(unit)
    if not id then return end
    if not fixed then
        -- 새 NPC는 가까이(약 10야드) 있을 때만. 전투 중에는 건너뜀
        if InCombatLockdown and InCombatLockdown() then return end
        if NS.InData(id) or not CheckInteractDistance then return end
        local good, inRange = pcall(CheckInteractDistance, unit, 3)
        if not (good and ok(inRange) and inRange) then return end
    end
    local map, x, y = NS.PlayerSpot()
    if not map then return end
    record(id, name, map, x, y, fixed)
end

-- 대화 창이 열리는 이벤트 (없는 이벤트는 건너뜀)
local ev = CreateFrame("Frame")
for _, event in ipairs({ "GOSSIP_SHOW", "MERCHANT_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
    "QUEST_COMPLETE", "TRAINER_SHOW", "TAXIMAP_OPENED", "BANKFRAME_OPENED", "AUCTION_HOUSE_SHOW", "PET_STABLE_SHOW",
    "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do
    pcall(ev.RegisterEvent, ev, event)
end
ev:SetScript("OnEvent", function(_, event)
    local good, err = pcall(function()
        if event == "PLAYER_TARGET_CHANGED" then seeUnit("target", false)
        elseif event == "UPDATE_MOUSEOVER_UNIT" then seeUnit("mouseover", false)
        else seeUnit("npc", true) end
    end)
    if not good and RS.debug then RS.Print("NPC 위치 기록 오류: " .. tostring(err)) end
end)

---------------------------------------------------------------------------
-- 새 데이터 세기 / 공유 (Contrib.lua, Sync.lua에서 씀)
---------------------------------------------------------------------------
-- 애드온 자료와 다른 내 기록: keys["p:번호:지도"] = true
function NS.Contributions(keys, includeReceived)
    local n = 0
    local db = RS.db
    for id, e in pairs(db and type(db.npcSpots) == "table" and db.npcSpots or {}) do
        for map, s in pairs(type(e.m) == "table" and e.m or {}) do
            if (includeReceived or not s.rx) and s.x and s.y and not NS.Shipped(id, map, s.x, s.y) then
                keys["p:" .. id .. ":" .. map] = true
                n = n + 1
            end
        end
    end
    return n
end

-- 공유 키를 이미 가지고 있는지 (내 기록이나 취합 자료에 그 지도 위치가 있으면)
function NS.HasKey(id, map)
    local db = RS.db
    local e = db and type(db.npcSpots) == "table" and db.npcSpots[id]
    if e and e.m and e.m[map] then return true end
    local c = community()[id]
    return (c and c.m and c.m[map]) ~= nil
end

-- 공유 메시지에 넣을 값: x, y, 이름
function NS.Get(id, map)
    local db = RS.db
    local e = db and type(db.npcSpots) == "table" and db.npcSpots[id]
    local s = e and e.m and e.m[map]
    if s and s.x and s.y then return s.x, s.y, e.name end
end

-- 받은 기록 합치기 (내가 모르는 자리만)
function NS.Apply(id, map, x, y, name, who)
    local db = RS.db
    if not (db and id and map and x and y and name and name ~= "") then return false end
    if not searchMaps()[map] or x <= 0 or y <= 0 or x >= 100 or y >= 100 then return false end
    if NS.HasKey(id, map) then return false end
    db.npcSpots = type(db.npcSpots) == "table" and db.npcSpots or {}
    local e = db.npcSpots[id]
    if not e then e = { name = name, m = {} }; db.npcSpots[id] = e end
    e.m = type(e.m) == "table" and e.m or {}
    e.m[map] = { x = x, y = y, n = 1, sx = x, sy = y, rx = who }
    if RS.MapSearch and RS.MapSearch.Reset then RS.MapSearch.Reset() end
    return true
end
