-- ReagentSource Sync: 파티 / 길드원끼리 새로 모은 획득처 데이터를 자동으로 주고받기
--
-- 검증(RSyncProbe)에서 확인한 것
--   · 파티, 길드, 전투 중 모두 전달됨. 성공(결과값 0)으로 나간 메시지는 빠짐없이 도착
--   · 너무 빨리 보내면 게임이 결과값 3(너무 빠름)으로 거절. 처음 약 10개 이후로는 1초에 1개 정도만 나감
--   · 자기 메시지가 자기에게 돌아오는 경우가 있어, 접속마다 만드는 표식(token)으로 걸러냄
--
-- 동작
--   1) 파티를 맺거나 접속하면 "인사(H)"로 내 데이터 요약(개수, 해시)을 알린다
--   2) 요약이 다르면 서로 "목록(I)"을 보낸다. 목록에는 애드온 자료에 없는 데이터의 키만 들어 있다
--   3) 상대 목록에서 내가 모르는 키를 "요청(Q)"하면, 가진 사람이 "데이터(V/D/N/X)"를 1초에 1개씩 보낸다
--   4) 받은 데이터는 내 기록(ReagentSourceDB)에 rx 표시와 함께 합쳐져 바로 툴팁에 나온다
--   5) 받는 사람(상수) 계정의 목록에 내 데이터가 들어 있으면 → 전달 완료로 보고 "파일 보내주세요" 알림에서 뺀다
local _, ns = ...
local RS = ns.RS

local PREFIX = "RSrcSync"
local SEND_GAP = 1.1          -- 메시지 간격(초). 게임 제한(초당 1개)보다 살짝 느리게
local THROTTLE_WAIT = 3       -- "너무 빠름"으로 거절되면 쉬는 시간
local ERROR_WAIT = 30         -- 그 밖의 실패(인스턴스 제한 등)면 쉬는 시간
local INV_GAP = 10 * 60       -- 같은 채널에 목록을 다시 보내는 최소 간격
local MAX_LEN = 240
local MAX_WANT = 300          -- 한 사람에게 한 번에 요청하는 최대 개수

local format, pairs, ipairs, tonumber, tostring, type = string.format, pairs, ipairs, tonumber, tostring, type
local concat, sort = table.concat, table.sort
local issecret = rawget(_G, "issecretvalue")
local function usable(v) return v ~= nil and not (issecret and issecret(v)) end

local token = format("%04x", math.random(0, 65535)) -- 이번 접속의 표식 (자기 메시지 거르기, 요청 대상 지정)

local Sync = { sent = 0, received = 0, peers = {} }
RS.Sync = Sync

---------------------------------------------------------------------------
-- 보내기 대기열 (1.1초에 1개, 거절되면 잠시 쉬었다가 다시)
---------------------------------------------------------------------------
local queue, queued = {}, {}
local pauseUntil = 0

local function enqueue(msg, ch, dedupe)
    if not ch or #queue > 800 then return end
    local k = dedupe and (ch .. dedupe)
    if k then
        if queued[k] then return end
        queued[k] = true
    end
    queue[#queue + 1] = { msg = msg, ch = ch, key = k }
end

local function rawSend(msg, ch)
    local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not fn then return false end
    local ok, res = pcall(fn, PREFIX, msg, ch)
    return ok, res
end

local pump = CreateFrame("Frame")
local acc = 0
pump:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if acc < SEND_GAP then return end
    acc = 0
    if #queue == 0 or GetTime() < pauseUntil then return end
    local item = queue[1]
    local ok, res = rawSend(item.msg, item.ch)
    if ok and (res == nil or res == true or res == 0) then
        table.remove(queue, 1)
        if item.key then queued[item.key] = nil end
        Sync.sent = Sync.sent + 1
    elseif ok and res == 3 then
        pauseUntil = GetTime() + THROTTLE_WAIT -- 너무 빠름: 같은 메시지를 잠시 뒤 다시
    else
        table.remove(queue, 1)                -- 그 밖의 실패: 이 메시지는 버리고 잠시 쉼
        if item.key then queued[item.key] = nil end
        pauseUntil = GetTime() + ERROR_WAIT
        Sync.lastError = tostring(res)
    end
end)

---------------------------------------------------------------------------
-- 채널
---------------------------------------------------------------------------
local function groupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local function channels()
    local t = {}
    local g = groupChannel()
    if g then t[#t + 1] = g end
    if IsInGuild and IsInGuild() then t[#t + 1] = "GUILD" end
    return t
end

---------------------------------------------------------------------------
-- 내 데이터 목록 (애드온 자료에 없는 것만: 내가 모은 것 + 받은 것)
---------------------------------------------------------------------------
local myKeys, myList, myHash
local function checksum(s)
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 16777213 end
    return h
end

local function refreshKeys()
    if myKeys then return end
    local _, _, keys = RS.CountContributions(true)
    myKeys, myList = keys or {}, {}
    for k in pairs(myKeys) do myList[#myList + 1] = k end
    sort(myList)
    myHash = checksum(concat(myList, ","))
end

local function isCollector() return RS.db and RS.db.isCollector and 1 or 0 end

---------------------------------------------------------------------------
-- 인사 / 목록 / 요청 보내기
---------------------------------------------------------------------------
local lastInv, lastHello = {}, {}

local function sendHello(ch, force)
    refreshKeys()
    if not force and lastHello[ch] and GetTime() - lastHello[ch] < 60 then return end
    lastHello[ch] = GetTime()
    enqueue(format("H|%s|%d|%d|%d", token, #myList, myHash, isCollector()), ch, "H")
end

local function sendInventory(ch, force)
    refreshKeys()
    if #myList == 0 and isCollector() == 0 then return end
    if not force and lastInv[ch] and GetTime() - lastInv[ch] < INV_GAP then return end
    lastInv[ch] = GetTime()
    local head = format("I|%s|%d|", token, isCollector())
    local cur = head
    for _, k in ipairs(myList) do
        if #cur + #k + 1 > MAX_LEN then
            enqueue(cur, ch)
            cur = head
        end
        cur = cur .. (cur == head and "" or ",") .. k
    end
    enqueue(cur, ch) -- 목록이 비어 있어도(받는 사람) 한 번은 보내서 "받는 사람이 있다"를 알린다
end

function Sync.Hello()
    for _, ch in ipairs(channels()) do sendHello(ch, true) end
end

---------------------------------------------------------------------------
-- 데이터 한 건 → 메시지
---------------------------------------------------------------------------
local function clean(s) return (tostring(s or ""):gsub("|", "/")) end
local function num(v) return v and tostring(v) or "" end

local function dataMessage(key)
    local db = RS.db
    local kind, a, b = key:match("^(%a):(%d+):?(%d*)$")
    a, b = tonumber(a), tonumber(b)
    if kind == "v" then
        for _, e in pairs(db.vendors[a] or {}) do
            if e.npc == b then
                return format("V|%s|%d|%d|%s|%s|%s|%s|%s|%s", token, a, b, num(e.uiMap), num(e.x), num(e.y), clean(e.faction), clean(e.name), clean(e.zone))
            end
        end
    elseif kind == "d" then
        for _, e in pairs(db.drops[a] or {}) do
            if e.npc == b then
                local x, y, n = "", "", e.n or 0
                if n > 0 and e.sx then x, y = RS.round1(e.sx / n), RS.round1(e.sy / n) end
                return format("D|%s|%d|%d|%s|%s|%s|%d|%s|%s", token, a, b, num(e.uiMap), num(x), num(y), n, clean(e.name), clean(e.zone))
            end
        end
    elseif kind == "n" and db.npcNames[a] then
        return format("N|%s|n|%d|%s", token, a, clean(db.npcNames[a]))
    elseif kind == "o" and db.objNames[a] then
        return format("N|%s|o|%d|%s", token, a, clean(db.objNames[a]))
    elseif kind == "q" and db.questNames[a] then
        return format("N|%s|q|%d|%s", token, a, clean(db.questNames[a]))
    elseif kind == "h" and db.hostileNPC[a] then
        return format("X|%s|%d|%s", token, a, clean(db.hostileNPC[a]))
    elseif kind == "p" and b and RS.NpcSpots then
        local x, y, name = RS.NpcSpots.Get(a, b)
        if x then return format("P|%s|%d|%d|%s|%s|%s", token, a, b, num(x), num(y), clean(name)) end
    end
end

---------------------------------------------------------------------------
-- 받은 데이터 합치기
---------------------------------------------------------------------------
local gotFrom = {}  -- 이름 -> 이번 묶음에서 받은 개수
local summaryAt

local function noteReceived(who, itemID)
    Sync.received = Sync.received + 1
    gotFrom[who] = (gotFrom[who] or 0) + 1
    summaryAt = GetTime() + 10
    myKeys = nil
    RS.Invalidate(itemID)
end

local function hasNpcEntry(list, npc)
    for _, e in pairs(list or {}) do if e.npc == npc then return true end end
end

local function applyData(kind, who, f)
    local db = RS.db
    if kind == "V" then
        local item, npc = tonumber(f[3]), tonumber(f[4])
        local zone = f[10]
        if not (item and npc and zone and zone ~= "") or hasNpcEntry(db.vendors[item], npc) then return end
        local list = db.vendors[item] or {}
        db.vendors[item] = list
        list["n" .. npc .. "@" .. zone] = { zone = zone, name = f[9], npc = npc, uiMap = tonumber(f[5]),
            x = tonumber(f[6]), y = tonumber(f[7]), faction = f[8] ~= "" and f[8] or nil, rx = who }
        noteReceived(who, item)
    elseif kind == "D" then
        local item, npc = tonumber(f[3]), tonumber(f[4])
        local zone = f[10]
        if not (item and npc and zone and zone ~= "") or hasNpcEntry(db.drops[item], npc) then return end
        local x, y, n = tonumber(f[6]), tonumber(f[7]), tonumber(f[8]) or 0
        if not (x and y) then n = 0 end
        local list = db.drops[item] or {}
        db.drops[item] = list
        list["n" .. npc .. "@" .. zone] = { zone = zone, name = f[9], npc = npc, uiMap = tonumber(f[5]),
            n = n, sx = (x or 0) * n, sy = (y or 0) * n, seen = math.max(n, 1), rx = who }
        noteReceived(who, item)
    elseif kind == "N" then
        local which, id, name = f[3], tonumber(f[4]), f[5]
        local t = (which == "n" and db.npcNames) or (which == "o" and db.objNames) or (which == "q" and db.questNames)
        if not (t and id and name and name ~= "") or t[id] then return end
        t[id] = name
        db.rx[which][id] = who
        noteReceived(who)
    elseif kind == "X" then
        local id, fac = tonumber(f[3]), f[4]
        if not (id and fac and fac ~= "") or db.hostileNPC[id] then return end
        db.hostileNPC[id] = fac
        db.rx.h[id] = who
        noteReceived(who)
    elseif kind == "P" then
        -- NPC 위치 (1.11.0): P|token|NPC번호|지도|x|y|이름
        if RS.NpcSpots and RS.NpcSpots.Apply(tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), f[7], who) then
            noteReceived(who)
        end
    end
end

---------------------------------------------------------------------------
-- 받기
---------------------------------------------------------------------------
local wants = {}    -- 상대 token -> { keys = {}, n, ch, who, at }

local function split(msg)
    local f = {}
    for part in (msg .. "|"):gmatch("([^|]*)|") do f[#f + 1] = part end
    return f
end

local function markDeliveredFrom(keysCsv)
    local sent = RS.db.sentKeys
    local changed = false
    for k in keysCsv:gmatch("[^,]+") do
        if not sent[k] then sent[k] = true; changed = true end
    end
    if changed then RS.Invalidate() end -- 알림/아이콘 다시 계산
end

local function onMessage(prefix, msg, ch, sender)
    if prefix ~= PREFIX or not RS.db or not usable(msg) or type(msg) ~= "string" then return end
    local f = split(msg)
    local kind, from = f[1], f[2]
    if not from or from == token then return end -- 내가 보낸 것
    local who = usable(sender) and sender or "?"
    if Ambiguate then who = Ambiguate(who, "none") end
    Sync.peers[from] = { who = who, at = GetTime(), col = Sync.peers[from] and Sync.peers[from].col }
    if (kind == "H" and f[5] == "1") or (kind == "I" and f[3] == "1") or Sync.peers[from].col then
        Sync.collectorSeenAt = GetTime() -- 받는 사람이 같은 파티/길드에 있음
    end

    if kind == "H" then
        local count, hash, col = tonumber(f[3]), tonumber(f[4]), f[5] == "1"
        Sync.peers[from].col = col
        refreshKeys()
        if hash ~= myHash then
            sendHello(ch)          -- 내 요약도 알려 주고
            sendInventory(ch)      -- 내 목록도 보낸다 (10분에 한 번)
        end
    elseif kind == "I" then
        local col = f[3] == "1"
        local csv = f[4] or ""
        Sync.peers[from].col = col
        if col then markDeliveredFrom(csv) end -- 받는 사람이 가진 데이터는 전달 완료
        refreshKeys()
        local w = wants[from]
        if not w then w = { keys = {}, n = 0, ch = ch, who = who }; wants[from] = w end
        for k in csv:gmatch("[^,]+") do
            if w.n < MAX_WANT and not myKeys[k] and not w.keys[k] and not RS.HasKey(k) then
                w.keys[k] = true
                w.n = w.n + 1
            end
        end
        w.at = GetTime() + 3 -- 목록이 다 올 때까지 잠깐 기다렸다가 요청
    elseif kind == "Q" then
        if f[3] ~= token then return end -- 다른 사람에게 온 요청
        for k in (f[4] or ""):gmatch("[^,]+") do
            local m = dataMessage(k)
            if m then enqueue(m, ch, k) end
        end
    elseif kind == "V" or kind == "D" or kind == "N" or kind == "X" or kind == "P" then
        applyData(kind, who, f) -- 누구에게 온 데이터든, 내가 모르는 것이면 합친다
    end
end

-- 요청 보내기 / 받은 데이터 요약 알림
local ticker = CreateFrame("Frame")
local tacc = 0
ticker:SetScript("OnUpdate", function(_, e)
    tacc = tacc + e
    if tacc < 1 then return end
    tacc = 0
    local now = GetTime()
    for tok, w in pairs(wants) do
        if w.at and now >= w.at then
            w.at = nil
            local head = format("Q|%s|%s|", token, tok)
            local cur = head
            for k in pairs(w.keys) do
                if #cur + #k + 1 > MAX_LEN then enqueue(cur, w.ch); cur = head end
                cur = cur .. (cur == head and "" or ",") .. k
            end
            if cur ~= head then enqueue(cur, w.ch) end
            wants[tok] = nil
        end
    end
    if summaryAt and now >= summaryAt then
        summaryAt = nil
        local parts, total = {}, 0
        for who, n in pairs(gotFrom) do parts[#parts + 1] = format("%s %d건", who, n); total = total + n end
        wipe(gotFrom)
        if total > 0 then
            RS.Print(format("파티/길드원에게서 새 획득처 데이터 %d건을 받았습니다. (%s)", total, concat(parts, ", ")))
            -- 받는 사람이면 받은 걸 바로 목록으로 알려서, 보낸 사람 쪽 알림이 사라지게 한다
            if isCollector() == 1 then
                for _, ch in ipairs(channels()) do
                    if not lastInv[ch] or now - lastInv[ch] > 15 then sendInventory(ch, true) end
                end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- 언제 인사하나: 접속, 파티 인원이 늘었을 때
---------------------------------------------------------------------------
local lastGroupSize = 0
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        onMessage(...)
    elseif event == "PLAYER_LOGIN" then
        local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
        if reg then pcall(reg, PREFIX) end
        lastGroupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
        C_Timer.After(20, Sync.Hello)
    elseif event == "GROUP_ROSTER_UPDATE" then
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        if n > lastGroupSize then
            local g = groupChannel()
            if g then C_Timer.After(5, function() sendHello(g, true) end) end
        end
        lastGroupSize = n
    end
end)

-- 내가 직접 모은 데이터가 늘면(상인 창, 루팅) 1분 안에 목록을 다시 알린다
--   (파티를 새로 맺지 않아도, 같이 사냥하는 중에 받는 사람에게 넘어가도록)
local lastOwn
local ownTicker = CreateFrame("Frame")
local oacc = 0
ownTicker:SetScript("OnUpdate", function(_, e)
    oacc = oacc + e
    if oacc < 60 then return end
    oacc = 0
    if not RS.db then return end
    local own = RS.CountContributions()
    if lastOwn and own > lastOwn then
        for _, ch in ipairs(channels()) do sendInventory(ch, true) end
    end
    lastOwn = own
end)

-- 기록이 바뀌면 목록을 다시 만든다
local origInvalidate = RS.Invalidate
function RS.Invalidate(itemID)
    myKeys = nil
    origInvalidate(itemID)
end

-- 최근 seconds 초 안에 받는 사람(상수)을 파티/길드에서 봤는지
--   봤으면 새 데이터는 자동으로 넘어가므로 "파일 보내주세요" 창을 띄우지 않는다
function Sync.CollectorNearby(seconds)
    return Sync.collectorSeenAt ~= nil and GetTime() - Sync.collectorSeenAt < (seconds or 1800)
end

-- /획득처 상태 에서 쓰는 요약
function Sync.Status()
    refreshKeys()
    local peers, cols = 0, 0
    for _, p in pairs(Sync.peers) do
        if GetTime() - p.at < 3600 then peers = peers + 1; if p.col then cols = cols + 1 end end
    end
    return format("공유: 내 공유 목록 %d건 · 보낸 메시지 %d · 받은 데이터 %d건 · 대기 %d · 최근 1시간 만난 사용자 %d명%s%s",
        #myList, Sync.sent, Sync.received, #queue, peers,
        cols > 0 and " (받는 사람 접속 중)" or "",
        RS.db.isCollector and " · |cff66ff66이 계정은 받는 사람|r" or "")
end
