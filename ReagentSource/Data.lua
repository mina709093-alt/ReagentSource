-- ReagentSource 정적 데이터 파일 (검증된 획득처만 넣는 곳)
--
-- 원칙: 실제로 확인한 정보만 적는다. 추측/다른 서버(클래식 등) 자료를 옮겨 적지 않는다.
-- 게임 안에서 상인 창을 열거나 몬스터를 루팅하면 자동 기록되며(ReagentSourceDB),
-- /획득처 내보내기 로 나온 줄을 그대로 아래 표에 붙여 넣으면 다른 캐릭터/친구와 공유할 수 있다.
--
-- 형식 (NPC 판매와 몬스터 드랍은 서로 다른 표로 관리):
--   vendors[아이템ID] = { { zone="지역명", name="NPC 이름", x=45.2, y=78.4, npc=NPC_ID, faction="Alliance"|"Horde"|"Neutral" }, ... }
--   drops[아이템ID]   = { { zone="지역명", name="몬스터 이름", x=52.3, y=65.1, npc=NPC_ID }, ... }
--   npc, faction 은 선택 항목. x, y 는 0~100 지도 좌표.
--
-- 예시(주석 처리됨 - 실제 데이터 아님):
--   vendors[3371] = {
--     { zone="스톰윈드", name="NPC 이름", x=45.2, y=78.4, npc=12345, faction="Alliance" },
--   }

local _, ns = ...
ns.StaticData = {
    -- 수집 데이터를 받는 사람 (채팅 알림에 표시됨)
    collectorName = "상수",
    -- 공유 안내 창에 보여줄 기본 게임 폴더 (대부분의 설치 위치)
    defaultGamePath = "C:\\Program Files (x86)\\World of Warcraft\\_forever_",

    vendors = {
    },

    drops = {
    },

    -- 분류(직업용품/재료)와 상관없이 항상 기록할 아이템 ID.
    -- 기본적으로 직업용품·재료 분류 아이템은 전부 기록되므로, 그 외 분류 아이템만 추가하면 된다.
    watch = {
        [3371]  = true, -- 유리 약병
        [8925]  = true, -- 수정 약병
        [17034] = true, -- 단풍나무 씨앗
    },
}
