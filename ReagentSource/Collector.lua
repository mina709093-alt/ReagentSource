-- ReagentSource Collector: 게임 안에서 실제로 확인된 획득처만 기록
--   · 상인 창을 열면  → 그 상인이 파는 재료를 "NPC 판매"로 기록 (현재 지역·좌표)
--   · 몬스터 시체를 루팅하면 → 나온 재료를 "몬스터 드랍"으로 기록 (루팅 위치 평균 좌표)
-- 낚시, 무두질/채광 등 채집, 소매치기, 상자(게임 오브젝트)는 드랍으로 기록하지 않는다.
local _, ns = ...
local RS = ns.RS

local GetTime, tonumber, type, pairs = GetTime, tonumber, type, pairs
local strsplit = strsplit

-- 12.x 클라이언트의 "비밀 값"(전투 중 등 애드온이 읽을 수 없는 값) 보호
local issecret = rawget(_G, "issecretvalue")
local function ok(v) return v ~= nil and not (issecret and issecret(v)) end
RS.Usable = ok

local function itemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- GUID → (npcID, 생물인지). 신형("Creature-0-...")과 3.3.5형("0xF130...") 모두 처리
local function parseGUID(guid)
    if not ok(guid) or type(guid) ~= "string" then return nil, false end
    if guid:sub(1, 2) == "0x" then
        local kind = guid:sub(3, 5):upper()
        if kind == "F13" or kind == "F15" then
            return tonumber(guid:sub(9, 12), 16), true
        end
        return nil, false
    end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" then
        return tonumber(npcID), true
    end
    return nil, false
end
RS.ParseGUID = parseGUID

---------------------------------------------------------------------------
-- NPC 이름 기억 (GUID/ID → 이름). 루팅 시점에 대상이 아닌 몹(광역 루팅)도 이름을 찾기 위함
---------------------------------------------------------------------------
local guidNames, guidCount = {}, 0

local function rememberUnit(unit)
    local exists = UnitExists(unit)
    if not ok(exists) or not exists then return end
    local isPlayer = UnitIsPlayer(unit)
    if not ok(isPlayer) or isPlayer then return end
    local guid, name = UnitGUID(unit), UnitName(unit)
    if not ok(guid) or not ok(name) then return end
    local npcID, isNPC = parseGUID(guid)
    if not isNPC or name == "" then return end
    if not guidNames[guid] then
        guidCount = guidCount + 1
        if guidCount > 400 then wipe(guidNames); guidCount = 1 end
    end
    guidNames[guid] = name
    RS.LearnNPCName(npcID, name)
    -- 외부 자료의 상인이 내 진영에 적대적이면 기억해 두고 판매처 목록에서 숨김
    local E = ns.ExternalData
    if npcID and E and E.vpos[npcID] and UnitReaction and RS.db then
        local r = UnitReaction(unit, "player")
        if not ok(r) then r = nil end
        local f = RS.PlayerFaction()
        if r and f and r <= 3 and RS.db.hostileNPC[npcID] ~= f then
            RS.db.hostileNPC[npcID] = f
            RS.Invalidate()
        end
    end
end

-- 게임에서 직접 본 이름으로 자료의 이름(영문 등)을 교체. 자료에 있는 NPC만 저장해 용량을 아낀다
function RS.LearnNPCName(npcID, name)
    if not (npcID and name and name ~= "" and RS.db) then return end
    local E = ns.ExternalData
    if not (E and E.npc[npcID]) and not RS.db.npcNames[npcID] then return end
    if RS.db.npcNames[npcID] ~= name then
        RS.db.npcNames[npcID] = name
        RS.Invalidate()
    end
end

-- 채집물/상자 이름: 마우스를 올렸을 때 툴팁 첫 줄을 기억했다가, 바로 열면(루팅) 그 오브젝트 ID에 연결
local lastWorldTip, lastWorldTipAt = nil, 0
GameTooltip:HookScript("OnShow", function(tt)
    pcall(function()
        if tt:IsForbidden() or tt:GetOwner() ~= UIParent then return end
        local _, unit = tt:GetUnit()
        if unit ~= nil then return end
        if tt.GetItem and tt:GetItem() then return end
        local fs = _G.GameTooltipTextLeft1
        local t = fs and fs:GetText()
        if ok(t) and t ~= "" then lastWorldTip, lastWorldTipAt = t, GetTime() end
    end)
end)

local function hasHangul(t) return type(t) == "string" and t:find("[\234-\237]") ~= nil end
RS.HasHangul = hasHangul

local function learnObjectName(guid)
    if not ok(guid) or type(guid) ~= "string" or not RS.db then return end
    local unitType, _, _, _, _, objID = strsplit("-", guid)
    objID = tonumber(objID)
    if unitType ~= "GameObject" or not objID then return end
    local E = ns.ExternalData
    if not (E and E.oloc and E.oloc[objID]) then return end
    -- 이미 정확한 한글 이름이 들어 있으면 배우지 않는다 (잘못 배우는 것 방지)
    if hasHangul(E.oname and E.oname[objID]) then return end
    local cm = ns.CommunityData
    if cm and cm.objNames and cm.objNames[objID] then return end
    -- 루팅하는 순간에도 같은 오브젝트 툴팁이 떠 있을 때만 (다른 오브젝트 이름을 잘못 붙이지 않게)
    local fs = _G.GameTooltipTextLeft1
    local now = GameTooltip:IsShown() and fs and fs:GetText()
    if not ok(now) then now = nil end
    local name
    if lastWorldTip and now == lastWorldTip and GetTime() - lastWorldTipAt < 10 then
        name = lastWorldTip
    elseif lastWorldTip and GetTime() - lastWorldTipAt < 1.5 then
        name = lastWorldTip
    end
    if name and RS.db.objNames[objID] ~= name then
        RS.db.objNames[objID] = name
        RS.Invalidate()
    end
end

local function nameFor(guid, npcID)
    return guidNames[guid] or (npcID and RS.db and RS.db.npcNames[npcID])
end

---------------------------------------------------------------------------
-- NPC 판매 기록
---------------------------------------------------------------------------
local function recordVendor(itemID, info)
    local list = RS.db.vendors[itemID]
    if not list then list = {}; RS.db.vendors[itemID] = list end
    local key = (info.npc and ("n" .. info.npc) or info.name) .. "@" .. info.zone
    local old = list[key]
    if old and old.x == info.x and old.y == info.y and old.name == info.name and old.faction == info.faction then
        return false
    end
    list[key] = { zone = info.zone, name = info.name, npc = info.npc, x = info.x, y = info.y, uiMap = info.uiMap, faction = info.faction }
    return true
end

local merchantScanned = {}

local function scanMerchant()
    if not RS.db or not UnitExists("npc") then return end
    local name = UnitName("npc")
    local guid = UnitGUID("npc")
    if not ok(name) or not ok(guid) then return end
    local npcID, isNPC = parseGUID(guid)
    if not isNPC or not name then return end -- 플레이어/오브젝트 상점 제외
    local zone, x, y, uiMap = RS.GetPlayerLocation()
    if not zone then return end

    -- 우호적이지 않은(중립) 상인은 양 진영 공용으로 표시
    local faction = RS.PlayerFaction()
    local reaction = UnitReaction and UnitReaction("npc", "player")
    if not ok(reaction) then reaction = nil end
    if reaction and reaction <= 4 then faction = "Neutral" end

    local info = { zone = zone, name = name, npc = npcID, x = x, y = y, uiMap = uiMap, faction = faction }
    local n, missing, changed = GetMerchantNumItems() or 0, 0, 0
    for i = 1, n do
        local link = GetMerchantItemLink(i)
        local itemID = itemIDFromLink(link)
        if not itemID then
            missing = missing + 1 -- 아직 아이템 정보가 안 온 칸: MERCHANT_UPDATE 때 다시 시도
        elseif RS.ShouldRecord(itemID) and recordVendor(itemID, info) then
            changed = changed + 1
            RS.Invalidate(itemID)
        end
    end
    merchantScanned[guid] = (missing == 0)
    RS.db.npcNames[npcID] = name
    if RS.debug and changed > 0 then RS.Print(("상인 %s: 재료 %d개 기록"):format(name, changed)) end
end

RS.On("MERCHANT_SHOW", function()
    wipe(merchantScanned)
    scanMerchant()
end)

RS.On("MERCHANT_UPDATE", function()
    local guid = UnitGUID("npc")
    if guid and merchantScanned[guid] == false then scanMerchant() end
end)

---------------------------------------------------------------------------
-- 몬스터 드랍 기록
---------------------------------------------------------------------------
-- 무두질/약초 채집/채광/소매치기 직후의 루팅은 "드랍"이 아니므로 제외
local gatherSpellNames = {}
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function loadGatherSpells()
    -- 8613 무두질, 2366 약초 채집, 2575 채광, 921 소매치기 (이름은 클라이언트 언어로 자동 변환)
    for _, id in ipairs({ 8613, 2366, 2575, 921 }) do
        local n = spellName(id)
        if n then gatherSpellNames[n] = true end
    end
end
local lastGatherCast = 0

local castFrame = CreateFrame("Frame")
if castFrame.RegisterUnitEvent then
    castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
else
    castFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end
castFrame:SetScript("OnEvent", function(_, _, unit, arg2, arg3)
    if unit ~= "player" then return end
    if not ok(arg3) then arg3 = nil end
    if not ok(arg2) then arg2 = nil end
    local name = (type(arg3) == "number") and spellName(arg3) or arg2
    if name and gatherSpellNames[name] then lastGatherCast = GetTime() end
end)

local function recordDrop(itemID, npcID, name, zone, x, y, uiMap)
    local list = RS.db.drops[itemID]
    if not list then list = {}; RS.db.drops[itemID] = list end
    local key = (npcID and ("n" .. npcID) or name) .. "@" .. zone
    local e = list[key]
    if not e then
        e = { zone = zone, name = name, npc = npcID, uiMap = uiMap, n = 0, sx = 0, sy = 0, seen = 0 }
        list[key] = e
    end
    e.name = name
    e.rx = nil -- 직접 루팅했으면 받은 데이터가 아니라 내 데이터
    if npcID then RS.db.npcNames[npcID] = name end
    e.seen = (e.seen or 0) + 1
    if x and y and (e.n or 0) < 50 then -- 좌표 평균은 최대 50회 관측까지만 반영
        e.n, e.sx, e.sy = (e.n or 0) + 1, (e.sx or 0) + x, (e.sy or 0) + y
    end
end

local lootDone = {} -- 같은 루팅 창에서 LOOT_READY/LOOT_OPENED 가 둘 다 와도 한 번만 기록

local function scanLoot()
    if not RS.db then return end
    if GetLootSourceInfo then
        for slot = 1, (GetNumLootItems() or 0) do
            local g = GetLootSourceInfo(slot)
            if ok(g) then learnObjectName(g) end
        end
    end
    if IsFishingLoot and IsFishingLoot() then return end
    if GetTime() - lastGatherCast < 3 then return end

    rememberUnit("target")
    rememberUnit("mouseover")
    local zone, x, y, uiMap = RS.GetPlayerLocation()
    if not zone then return end

    local targetGUID = UnitExists("target") and UnitIsDead("target") and UnitGUID("target")
    if not ok(targetGUID) then targetGUID = nil end
    local changed = 0
    for slot = 1, (GetNumLootItems() or 0) do
        local itemID = itemIDFromLink(GetLootSlotLink(slot))
        if itemID and RS.ShouldRecord(itemID) then
            local sources = {}
            if GetLootSourceInfo then
                local src = { GetLootSourceInfo(slot) } -- guid1, 수량1, guid2, 수량2 ...
                for i = 1, #src, 2 do if ok(src[i]) then sources[#sources + 1] = src[i] end end
            elseif targetGUID then
                sources[1] = targetGUID -- 구형 클라이언트: 죽은 대상 기준
            end
            for _, guid in pairs(sources) do
                local npcID, isNPC = parseGUID(guid)
                local lootKey = tostring(guid) .. ":" .. itemID
                if isNPC and not lootDone[lootKey] then
                    local name = nameFor(guid, npcID)
                    if name then
                        lootDone[lootKey] = true
                        recordDrop(itemID, npcID, name, zone, x, y, uiMap)
                        RS.Invalidate(itemID)
                        changed = changed + 1
                    end
                end
            end
        end
    end
    if RS.debug and changed > 0 then RS.Print(("드랍 %d건 기록 (%s)"):format(changed, zone)) end
end

RS.On("LOOT_OPENED", scanLoot)
if C_Loot or GetLootSourceInfo then
    pcall(RS.On, "LOOT_READY", scanLoot)
end
RS.On("LOOT_CLOSED", function()
    -- 오래된 기록 정리 (같은 시체 재루팅은 짧은 시간 안에만 중복 방지하면 충분)
    local n = 0
    for _ in pairs(lootDone) do n = n + 1 end
    if n > 300 then wipe(lootDone) end
end)

---------------------------------------------------------------------------
-- 이름 수집: 대상/마우스오버, 그리고 전투 기록의 사망 이벤트(광역 사냥 대비)
---------------------------------------------------------------------------
RS.On("PLAYER_LOGIN", loadGatherSpells)
RS.On("PLAYER_TARGET_CHANGED", function() rememberUnit("target") end)
RS.On("UPDATE_MOUSEOVER_UNIT", function() rememberUnit("mouseover") end)

-- 이름표가 화면에 나타날 때도 이름 수집 (광역 사냥 대비).
-- ※ 최신 클라이언트(12.x)에서는 애드온의 전투 기록(COMBAT_LOG_EVENT_UNFILTERED) 등록이 금지되어 사용하지 않는다.
RS.On("NAME_PLATE_UNIT_ADDED", function(_, unit) if unit then rememberUnit(unit) end end)

---------------------------------------------------------------------------
-- 퀘스트 제목: 퀘스트 창을 보거나 수락하면 한글 제목을 기억 (ETC 탭 퀘스트 보상용)
---------------------------------------------------------------------------
local function learnQuest(qid, title)
    local E = ns.ExternalData
    if not (qid and qid > 0 and title and title ~= "" and RS.db and E and E.qname and E.qname[qid]) then return end
    if RS.db.questNames[qid] ~= title then
        RS.db.questNames[qid] = title
        RS.Invalidate()
    end
end

RS.On("QUEST_DETAIL", function()
    local qid = GetQuestID and GetQuestID()
    learnQuest(qid, GetTitleText and GetTitleText())
end)

RS.On("QUEST_ACCEPTED", function(_, a, b)
    local qid = (type(b) == "number" and b) or a
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qid)
    learnQuest(qid, title)
end)
