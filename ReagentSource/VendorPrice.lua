-- ReagentSource VendorPrice: 재료 툴팁에 상점 구매가 표시
--   · 판매 NPC가 있는 재료에만, 판매 NPC 줄 바로 아래에 "상점 구매가: 개당 ..." 줄을 붙입니다.
--   · 가격은 상인 창을 열었을 때 본 실제 가격(평판 할인 포함, 저장 데이터 vendorPrice)을 먼저 쓰고,
--     없으면 PriceData.lua(게임 테이블의 기본 가격)를 씁니다.
--   · 상인 창의 이벤트는 Collector.lua와 겹치지 않게 이 파일의 프레임으로 따로 받습니다.
local _, ns = ...
local RS = ns.RS

local floor, format = math.floor, string.format

RS.cfg.showVendorPrice = true                 -- 툴팁에 상점 구매가 표시
RS.cfg.priceColor = { 1.00, 0.25, 0.25 }      -- 상점 구매가 줄: 붉은색 (눈에 잘 띄게)

local function ok(v)
    return not (issecretvalue and issecretvalue(v))
end

-- 코퍼 → "1골드 2실버 3코퍼" (동전 그림 함수가 있으면 그림으로)
local function money(copper)
    copper = floor((copper or 0) + 0.5)
    if GetCoinTextureString then
        local good, s = pcall(GetCoinTextureString, copper)
        if good and type(s) == "string" and s ~= "" then return s end
    end
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "골드" end
    if s > 0 then parts[#parts + 1] = s .. "실버" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "코퍼" end
    return table.concat(parts, " ")
end

-- 가격: 묶음 가격(코퍼), 묶음 개수, 출처("seen" 상인 창에서 봄 / "table" 기본 가격)
function RS.GetVendorPrice(itemID)
    local db = RS.db
    local seen = db and type(db.vendorPrice) == "table" and db.vendorPrice[itemID]
    if type(seen) == "table" and type(seen.p) == "number" and seen.p > 0 then
        return seen.p, (type(seen.n) == "number" and seen.n > 0) and seen.n or 1, "seen"
    end
    local D = ns.VendorPriceData
    local d = D and D[itemID]
    if type(d) == "number" and d > 0 then return d, 1, "table" end
    if type(d) == "table" and type(d[1]) == "number" and d[1] > 0 then return d[1], d[2] or 1, "table" end
end

-- 툴팁 한 줄 글 (가격을 모르면 nil)
function RS.VendorPriceLine(itemID)
    if not RS.cfg.showVendorPrice then return nil end
    local price, count = RS.GetVendorPrice(itemID)
    if not price then return nil end
    if count <= 1 then
        return "  상점 구매가: " .. money(price)
    end
    local each = price / count
    local eachText = (each == floor(each)) and money(each) or ("약 " .. money(each))
    return format("  상점 구매가: 개당 %s (%d개 묶음 %s)", eachText, count, money(price))
end

---------------------------------------------------------------------------
-- 상인 창에서 실제 가격 기록 (평판 할인이 들어간 값)
---------------------------------------------------------------------------
local function merchantInfo(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local good, info = pcall(C_MerchantFrame.GetItemInfo, i)
        if good and type(info) == "table" then
            return info.price, info.stackCount, info.hasExtendedCost
        end
    end
    if GetMerchantItemInfo then
        local good, _, _, price, quantity, _, _, _, extended = pcall(GetMerchantItemInfo, i)
        if good then return price, quantity, extended end
    end
end

local function scanPrices()
    if not (RS.db and GetMerchantNumItems and GetMerchantItemLink) then return end
    RS.db.vendorPrice = type(RS.db.vendorPrice) == "table" and RS.db.vendorPrice or {}
    local n = GetMerchantNumItems() or 0
    for i = 1, n do
        local link = GetMerchantItemLink(i)
        local itemID = ok(link) and link and tonumber(link:match("item:(%d+)"))
        if itemID and (not RS.ShouldRecord or RS.ShouldRecord(itemID)) then
            local price, quantity, extended = merchantInfo(i)
            -- 토큰·명예 등 다른 화폐로 사는 물건은 빼고, 골드로 사는 것만
            if ok(price) and ok(quantity) and type(price) == "number" and price > 0 and not extended then
                RS.db.vendorPrice[itemID] = { p = price, n = (type(quantity) == "number" and quantity > 0) and quantity or 1 }
            end
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("MERCHANT_UPDATE")
ev:SetScript("OnEvent", function()
    local good, err = pcall(scanPrices)
    if not good and RS.debug then RS.Print("상점 가격 기록 오류: " .. tostring(err)) end
end)
