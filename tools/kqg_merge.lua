-- 퀘스트 길잡이 취합: FoundData.lua(기존) + SavedVariables(KQuestGuide.lua 여러 개) → 새 FoundData.lua
-- 사용: texlua kqg_merge.lua 출력 기존FoundData.lua(없으면 -) SV1.lua [SV2.lua ...]
local out, base = arg[1], arg[2]
local F = {}
if base ~= "-" then local env = {} assert(loadfile(base, "t", env))() F = env.KQG_FOUND or {} end
local add = { q = 0, e = 0, o = 0 }
for i = 3, #arg do
  local env = {} assert(loadfile(arg[i], "t", env))()
  for qid, f in pairs((env.KQGDB or {}).found or {}) do
    local d = F[qid] or {}
    if f.title and f.start and not (d.title and d.start) then
      d.title, d.lvl, d.start, d.after = f.title, f.lvl, f.start, f.after; add.q = add.q + 1
    elseif f.title and not d.title then d.title, d.lvl = f.title, f.lvl end
    if f["end"] and not d["end"] then d["end"] = f["end"]; add.e = add.e + 1 end
    for k, o in pairs(f.obj or {}) do
      d.obj = d.obj or {}
      local cur = d.obj[k]
      if o.pts and #o.pts > 0 and not (cur and cur.pts and #cur.pts > 0) then
        d.obj[k] = { type = o.type, name = o.name, need = o.need, pts = o.pts }; add.o = add.o + 1
      elseif not cur then d.obj[k] = { type = o.type, name = o.name, need = o.need, pts = {} } end
    end
    if next(d) then F[qid] = d end
  end
end
local function q(s) return string.format("%q", tostring(s)) end
local function loc(l)
  if not l then return "nil" end
  return string.format("{ %q, %d, %d, %s, %s, %s, %s }", l[1] or "n", l[2] or 0, l[3] or 0, l[4] or 0, l[5] or 0, q(l[6] or "?"), l[7] and q(l[7]) or "nil")
end
local ids = {} for k in pairs(F) do ids[#ids + 1] = k end table.sort(ids)
local L = { "-- 퀘스트 길잡이 수집 취합 데이터 (게임 안에서 모은 KQuestGuide.lua 를 합친 결과 - 자동 생성)",
  "-- 직접 수정하지 말고, 취합 도구로 다시 만드세요. 지역 번호 대신 지도 번호(uiMap)를 씁니다.",
  "KQG_FOUND = {" }
for _, id in ipairs(ids) do
  local d = F[id]
  local p = {}
  if d.title then p[#p + 1] = "title = " .. q(d.title) end
  if d.lvl then p[#p + 1] = "lvl = " .. d.lvl end
  if d.after then p[#p + 1] = "after = " .. d.after end
  if d.start then p[#p + 1] = "start = " .. loc(d.start) end
  if d["end"] then p[#p + 1] = '["end"] = ' .. loc(d["end"]) end
  if d.obj then
    local os_ = {}
    local ks = {} for k in pairs(d.obj) do ks[#ks + 1] = k end table.sort(ks)
    for _, k in ipairs(ks) do
      local o = d.obj[k]
      local pts = {}
      for _, pt in ipairs(o.pts or {}) do pts[#pts + 1] = string.format("{ %d, %s, %s }", pt[1], pt[2], pt[3]) end
      os_[#os_ + 1] = string.format("[%d] = { type = %q, name = %s, need = %s, pts = { %s } }", k, o.type or "k", q(o.name or "?"), o.need or 0, table.concat(pts, ", "))
    end
    p[#p + 1] = "obj = { " .. table.concat(os_, ", ") .. " }"
  end
  L[#L + 1] = "  [" .. id .. "] = { " .. table.concat(p, ", ") .. " },"
end
L[#L + 1] = "}"
local f = assert(io.open(out, "w")) f:write(table.concat(L, "\n") .. "\n") f:close()
print("퀘스트", #ids, "새로 받은 곳 +" .. add.q, "제출 곳 +" .. add.e, "목표 위치 +" .. add.o)
