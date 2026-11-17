-- ReagentSource 취합: CommunityData.lua + SavedVariables(ReagentSource.lua 여러 개) → 새 CommunityData.lua
-- 사용: texlua rs_merge.lua 출력파일 기존CommunityData.lua SV1.lua [SV2.lua ...]
local out, cdPath = arg[1], arg[2]
local ns = {}
assert(loadfile(cdPath, "t", setmetatable({}, { __index = _G })))(nil, ns)
local C = ns.CommunityData
for _, s in ipairs({ "vendors", "drops", "npcNames", "objNames", "questNames", "hostile" }) do C[s] = C[s] or {} end
local added = { vendors = 0, drops = 0, npcNames = 0, objNames = 0, questNames = 0, hostile = 0 }
local function r1(v) return v and math.floor(v * 10 + 0.5) / 10 end
local function has(list, npc) for _, e in ipairs(list) do if e.npc == npc then return e end end end
for i = 3, #arg do
  local env = {}
  assert(loadfile(arg[i], "t", env))()
  local db = env.ReagentSourceDB or {}
  for item, entries in pairs(db.vendors or {}) do
    for _, e in pairs(entries) do
      if e.npc and e.zone then
        C.vendors[item] = C.vendors[item] or {}
        if not has(C.vendors[item], e.npc) then
          table.insert(C.vendors[item], { zone = e.zone, name = e.name, x = r1(e.x), y = r1(e.y), uiMap = e.uiMap, npc = e.npc, faction = e.faction })
          added.vendors = added.vendors + 1
        end
      end
    end
  end
  for item, entries in pairs(db.drops or {}) do
    for _, e in pairs(entries) do
      if e.npc and e.zone then
        local n = e.n or 0
        local x, y = (n > 0 and e.sx) and r1(e.sx / n) or nil, (n > 0 and e.sy) and r1(e.sy / n) or nil
        C.drops[item] = C.drops[item] or {}
        local old = has(C.drops[item], e.npc)
        if not old then
          table.insert(C.drops[item], { zone = e.zone, name = e.name, x = x, y = y, n = math.max(n, 1), uiMap = e.uiMap, npc = e.npc })
          added.drops = added.drops + 1
        elseif (old.n or 0) < n and x then
          old.x, old.y, old.n = x, y, n
        end
      end
    end
  end
  for src, dst in pairs({ npcNames = "npcNames", objNames = "objNames", questNames = "questNames", hostileNPC = "hostile" }) do
    for k, v in pairs(db[src] or {}) do
      if C[dst][k] == nil then C[dst][k] = v; added[dst] = added[dst] + 1 end
    end
  end
end
local function q(s) return string.format("%q", s) end
local function sortedKeys(t) local k = {} for x in pairs(t) do k[#k + 1] = x end table.sort(k, function(a, b) return tostring(a) < tostring(b) end) return k end
local function entry(e, isDrop)
  local p = { "zone=" .. q(e.zone), "name=" .. q(e.name or "?") }
  if e.x then p[#p + 1] = "x=" .. e.x end
  if e.y then p[#p + 1] = "y=" .. e.y end
  if isDrop then p[#p + 1] = "n=" .. (e.n or 1) end
  if e.uiMap then p[#p + 1] = "uiMap=" .. e.uiMap end
  p[#p + 1] = "npc=" .. e.npc
  if e.faction then p[#p + 1] = "faction=" .. q(e.faction) end
  return "{ " .. table.concat(p, ", ") .. " }"
end
local L = { "-- ReagentSource 커뮤니티 취합 데이터 (여러 사용자가 보낸 ReagentSource.lua 를 합친 결과 - 자동 생성)",
  "-- 직접 수정하지 말고, 취합 도구로 다시 만드세요.", "local _, ns = ...", "ns.CommunityData = {",
  "    version = " .. q(os.date("%Y-%m-%d")) .. ",", "    contributors = " .. (C.contributors or 0) .. "," }
for _, s in ipairs({ "vendors", "drops" }) do
  L[#L + 1] = "    " .. s .. " = {"
  for _, item in ipairs(sortedKeys(C[s])) do
    local parts = {}
    for _, e in ipairs(C[s][item]) do parts[#parts + 1] = entry(e, s == "drops") end
    L[#L + 1] = "        [" .. item .. "] = { " .. table.concat(parts, ", ") .. " },"
  end
  L[#L + 1] = "    },"
end
for _, s in ipairs({ "npcNames", "objNames", "questNames", "hostile" }) do
  L[#L + 1] = "    " .. s .. " = {"
  for _, k in ipairs(sortedKeys(C[s])) do L[#L + 1] = "        [" .. k .. "] = " .. q(C[s][k]) .. "," end
  L[#L + 1] = "    },"
end
L[#L + 1] = "}"
local f = assert(io.open(out, "w")); f:write(table.concat(L, "\n") .. "\n"); f:close()
for k, v in pairs(added) do print(k, "+" .. v) end
