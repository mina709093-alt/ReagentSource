-- ReagentSource Tooltip: 아이템 툴팁 맨 아래에 획득처 줄 추가
-- 기존 툴팁 내용은 건드리지 않고 AddLine 으로 덧붙이기만 한다.
-- 다른 애드온의 Hook 을 덮어쓰지 않도록 SetScript 대신
-- TooltipDataProcessor.AddTooltipPostCall(신형) / HookScript(구형)만 사용한다.
local _, ns = ...
local RS = ns.RS

-- 획득처를 표시할 툴팁 (마우스오버 기본 툴팁 + 채팅 링크 툴팁)
local TARGET_TOOLTIPS = {}
local function isTarget(tt)
    return TARGET_TOOLTIPS[tt] == true
end

-- 툴팁별로 "이미 추가한 아이템" 기록 → 같은 툴팁에 두 번 추가되지 않게
local added = setmetatable({}, { __mode = "k" })

local function itemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function getItemID(tt, data)
    if type(data) == "table" and data.id and Enum and Enum.TooltipDataType
       and data.type == Enum.TooltipDataType.Item then
        return data.id
    end
    if tt.GetItem then
        local _, link = tt:GetItem()
        return itemIDFromLink(link)
    end
end

local function append(tt, data)
    if not tt or not isTarget(tt) then return end
    if tt.IsForbidden and tt:IsForbidden() then return end
    local itemID = getItemID(tt, data)
    if not itemID then return end
    RS.lastTooltipItem = itemID
    if tt == GameTooltip then RS.hoverItemID = itemID end -- 단축키(전체 보기 창)용
    if added[tt] == itemID then return end
    added[tt] = itemID
    local lines = RS.GetLines(itemID)
    if not lines then return end -- 획득처가 확인되지 않은 아이템: 아무것도 표시 안 함
    for i = 1, #lines do
        local l = lines[i]
        tt:AddLine(l[1], l[2], l[3], l[4])
    end
    tt:Show() -- 줄이 늘어난 만큼 크기 갱신
end

local reported = false
local function safeAppend(tt, data)
    RS.tooltipCalls = (RS.tooltipCalls or 0) + 1
    -- 이 애드온 오류가 다른 애드온의 툴팁 처리까지 막지 않도록 보호
    local ok, err = pcall(append, tt, data)
    if not ok then
        RS.lastTooltipError = tostring(err)
        if not reported or RS.debug then
            reported = true
            RS.Print("|cffff4444툴팁 오류:|r " .. RS.lastTooltipError .. "  (이 문구를 상수님께 알려주세요)")
        end
    end
end

local function registerTooltip(tt)
    if not tt or TARGET_TOOLTIPS[tt] then return end
    TARGET_TOOLTIPS[tt] = true
    -- 툴팁 내용이 지워지면(다른 아이템으로 바뀌면) 중복 방지 기록도 초기화
    if tt.HasScript and tt:HasScript("OnTooltipCleared") then
        tt:HookScript("OnTooltipCleared", function(self)
            added[self] = nil
            if self == GameTooltip then RS.hoverItemID = nil end
        end)
    end
    tt:HookScript("OnHide", function(self)
        added[self] = nil
        if self == GameTooltip then RS.hoverItemID = nil end
    end)
    return true
end

function RS.InstallTooltipHooks()
    local fresh = {}
    if registerTooltip(GameTooltip) then fresh[#fresh + 1] = GameTooltip end
    if registerTooltip(ItemRefTooltip) then fresh[#fresh + 1] = ItemRefTooltip end

    if RS.hooked then return end
    RS.hooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
       and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        RS.hookMode = "TooltipDataProcessor"
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, safeAppend)
    else
        RS.hookMode = "OnTooltipSetItem"
        for _, tt in ipairs(fresh) do
            tt:HookScript("OnTooltipSetItem", function(self) safeAppend(self) end)
        end
    end
end
