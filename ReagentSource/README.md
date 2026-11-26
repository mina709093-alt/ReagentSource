# ReagentSource (재료 획득처)

## 데이터 출처와 연락처 (Data sources & contact)

이 애드온은 아래에 적은 프로젝트들의 공개 데이터를 이용해 만들었습니다. 데이터를 만들고 공개해 주신 분들께 깊이 감사드립니다.

저작권자나 데이터를 제공하신 분께서 사용을 원하지 않으시면, 언제든 아래 메일로 알려 주십시오.
요청을 받는 즉시 해당 데이터의 사용을 멈추고, 이후 배포본에서 빼겠습니다. 그 밖에 필요하신 조치가 있으면 성심껏 협조하겠습니다.
미처 허락을 구하지 못한 부분이 있었다면 진심으로 사과드립니다.

- 연락처: mina709093@gmail.com

> This add-on is built with publicly available data from the projects listed below, and we are sincerely grateful to their authors.
> If you are a rights holder or data provider and would prefer that we not use your data, please contact us at any time at mina709093@gmail.com.
> We will stop using it immediately upon request, remove it from future releases, and cooperate fully with any further steps you may need.
> We apologize for any inconvenience this may have caused.

### 어떤 데이터를 어디서 가져오는지

| 데이터 | 가져온 곳 | 조건 | 들어 있는 파일 |
|---|---|---|---|
| 판매 NPC, 드랍 몬스터, 확률, 위치 | [EG Link output: World of Warcraft: Forever](https://github.com/JIVESCORP/eg-link-output-wowf) — Data from [Efficient Games](https://efficient.games) | CC BY 4.0 | `ExternalData.lua` |
| 한글 NPC·오브젝트 이름 | [QuestieDB](https://github.com/Questie/QuestieDB)의 Forever koKR 현지화 데이터, 그리고 설치된 갓존슨·KQuestGuide 애드온의 한글 NPC 이름 | GPLv3 (QuestieDB) | `ExternalData.lua` |
| 사용자들이 확인한 획득처 | 사용자들이 게임 안에서 직접 기록해 보내 준 자료를 취합 | 보내 준 분들의 동의 | `CommunityData.lua` |
| 퀘스트 보상의 한글 제목·NPC 위치 (실시간) | 설치된 KQuestGuide 애드온의 데이터(`KQG_DATA`)를 읽기만 함 | KQuestGuide 조건 (GPLv3) | `Core.lua` |
| 길 안내 (선택) | 설치된 Shortest Path Forever 애드온의 공개 API를 읽기만 함 | 해당 애드온 조건 | `Popup.lua` |
| 월드맵 장소 검색의 지명·좌표 (한글·영문) | 게임 클라이언트 자체 테이블(WorldMapOverlay, AreaTable, UiMap, UiMapXMapArt, UiMapAssignment, WMOAreaTable)과 지형·건물 배치 파일(ADT, WMO), [wago.tools](https://wago.tools)에서 받은 빌드 1.60.1.70888. 좌표는 지역 지도에서 그 지명의 탐험 영역 중심, 없으면 그 지명 땅이나 건물의 가운데 | 지명과 지도 자료의 권리는 Blizzard Entertainment | `MapSearchData.lua` |
| 월드맵 이동·확대 (선택) | 설치된 OpenMap 애드온의 공개 API(`OpenMapAPI`)를 읽기만 함 | 해당 애드온 조건 (MIT) | `MapSearch.lua` |
| 상점 구매가 (기본 가격) | 게임 클라이언트 자체 테이블 ItemSparse(BuyPrice, VendorStackCount), [wago.tools](https://wago.tools)에서 받은 빌드 1.60.1.70888. 상인 창을 열면 실제 가격으로 바꿔 씀 | 아이템 자료의 권리는 Blizzard Entertainment | `PriceData.lua` |
| 월드맵 NPC 검색의 NPC 이름·부제·위치 | [QuestieDB](https://github.com/Questie/QuestieDB)의 Forever 자료(1.1.6): NPC 한글 이름·부제(koKR)와 스폰 좌표. 지도마다 스폰들의 가운데에 가장 가까운 한 곳. 사용자들이 게임 안에서 본 실제 위치(취합)가 있으면 그것을 먼저 씀 | GPLv3 (QuestieDB) | `NpcSearchData.lua`, `CommunityData.lua` |
| 월드맵 던전·공격대·전장 입구 검색의 입구 위치 | [QuestieDB](https://github.com/Questie/QuestieDB)의 Forever 던전 표(1.1.6, `support/Forever/Zones/dungeons.lua`): 입구 좌표와 영어 이름. 한글 이름과 종류(던전·공격대·전장)는 게임 클라이언트 자체 테이블 AreaTable·Map, [wago.tools](https://wago.tools)에서 받은 빌드 1.60.1.70888 | GPLv3 (QuestieDB), 이름의 권리는 Blizzard Entertainment | `DungeonEntranceData.lua` |

### 데이터를 어떻게 확인하는지

- **실제로 확인한 정보만 넣습니다.** 다른 서버(클래식 등)의 자료나 추측은 넣지 않습니다.
- 게임 안에서 상인 창을 열거나 몬스터를 루팅하면 실제 결과를 기록합니다. 파티원·길드원과 주고받을 수 있습니다.
- **사용자 수집 자료는 취합 도구로 합친 뒤 검사합니다.** 기존 항목이 사라지지 않았는지, 좌표가 0~100 안인지, 파일이 정상적으로 읽히는지 확인한 다음에만 넣습니다.
- 외부 데이터 파일(`ExternalData.lua`) 맨 위에 출처, 라이선스, 바꾼 내용, 만든 날짜가 적혀 있습니다.
- 장소 검색 자료(`MapSearchData.lua`)는 게임 테이블과 지형·건물 배치 파일에서 자동으로 만듭니다. 어디에서도 위치를 알 수 없는 지명은 넣지 않습니다(지역 중앙으로 대신하지 않음).
- NPC 검색 자료(`NpcSearchData.lua`)는 QuestieDB Forever 자료에서 자동으로 만듭니다. 게임 안에서 사용자들이 직접 본 NPC 위치(자료에 없는 NPC, 자료와 다른 위치)는 따로 기록해 취합하고, 그 위치를 먼저 씁니다.
- 던전 입구 자료(`DungeonEntranceData.lua`)는 QuestieDB Forever 던전 표에서 자동으로 만듭니다. QuestieDB에 Forever 위치가 확인되지 않았다고 적힌 입구와, 게임 테이블에 한글 이름이 없는(이 클라이언트에 없는) 던전은 넣지 않습니다.

## 사용 방법

마우스를 올린 제작 재료의 툴팁 맨 아래에 **가장 가까운** 획득처 하나씩을 표시합니다.
판매 NPC 1명, 드랍 몬스터 1종입니다. 재료에 마우스를 올린 채 **F12**를 누르면 전체 목록 창이 열립니다.

- 하늘색: NPC 판매. 형식은 `지역명 - NPC 이름 (좌표)`
- 주황색: 몬스터 드랍. 형식은 `지역명 - 몬스터 이름 (좌표)`
- 회색: `[F12] 전체 보기 (판매 N · 드랍 N)` 안내. 획득처가 2곳 이상일 때만 나옵니다.
- 획득처가 확인되지 않은 아이템에는 아무것도 표시하지 않습니다.

## 전체 보기 창 (F12)

- 전문기술 창의 재료, 가방 아이템 등 아이템 툴팁이 떠 있는 상태에서 단축키를 누르면 열립니다.
- 탭으로 나눠서 보여줍니다. 내용이 있는 탭만 나오고, 모든 탭이 현재 위치에서 가까운 순으로 정렬됩니다.
  - **NPC 판매**
  - **몬스터 드랍**: 확률이 함께 나옵니다.
  - **ETC**: 그 외 획득 방법입니다. 생물 무두질/채광/약초 채집, 광맥·약초·상자, 낚시, 다른 아이템 열기, 퀘스트 보상이 들어갑니다.
    퀘스트 보상은 퀘스트 길잡이(KQuestGuide)가 켜져 있으면 한글 제목과 퀘스트 주는 NPC 위치까지 나옵니다.
  - 아무 정보도 없으면 ETC 탭에 "습득 경로 알 수 없음"이 나옵니다.
- **파란 좌표 `[x, y]`를 클릭하면 길 안내**를 시작합니다.
  - Shortest Path Forever가 켜져 있으면 퀘스트 길잡이(KQuestGuide)와 같은 방식으로 안내합니다. 핀, 점선 경로, 화살표가 나오고, 상인이면 도착했을 때 이름표가 강조됩니다.
  - 없으면 게임 기본 지도 핀을 찍고 추적합니다.
  - 안내가 시작되면 획득처 창은 닫히고, 화면 위쪽에 작은 표시줄이 뜹니다. 드래그로 옮길 수 있습니다.
    `NPC/몬스터 - 아이템 - 획득처로 안내 중`, 남은 거리, **[안내 종료]** 버튼이 들어 있습니다.
  - 목적지에서 **5야드 안**에 들어오면 안내(핀, 점선)가 자동으로 끝납니다. [안내 종료]를 눌러도 끝납니다.
  - 지역을 이동하면서 핀이나 점선이 지워져도, 이동 후 40초 안이면 같은 목적지로 자동으로 다시 표시합니다. (KQuestGuide와 같은 방식)
  - `/reload`나 재접속 뒤에도 진행 중이던 안내를 이어서 보여줍니다.
- 단축키(기본 **F12**)는 게임 단축키보다 **우선** 적용됩니다.
  - 아이템 툴팁이 떠 있을 때 누르면 → 획득처 창
  - 그 외에는 → 그 키의 원래 게임 기능(예: F12 가방 열기)이 그대로 실행됩니다.
  - 저장된 게임 단축키 설정은 바꾸지 않습니다. 접속할 때마다 다시 적용되며, 전투 중에 접속하면 전투 후에 적용됩니다.
  - 변경: `/획득처 단축키 F11`, 끄기: `/획득처 단축키 끔`
  - 설정 > 단축키 > 애드온 > "재료 획득처"에서 따로 키를 지정해도 됩니다.

## 데이터는 어디서 오나 (우선순위 순)

1. **Data.lua (정적 데이터)**: 검증된 정보만 손으로 넣는 표입니다. 처음에는 비어 있습니다.
2. **ExternalData.lua (EG Link 공개 자료)**: 포에버 플레이어들의 EG Link 애드온이 실제로 기록한 상인 판매 목록, 루팅 기록입니다.
   상인 311명, 판매 아이템 1,165종, 몬스터 764종, 드랍 아이템 836종이 들어 있습니다. 툴팁에는 직업용품·재료 분류만 표시합니다.
   - 지역명은 게임 클라이언트에서 한글로 받아옵니다.
   - NPC 한글 이름은 QuestieDB의 포에버 한글 이름표와 설치된 갓존슨·KQuestGuide 자료를 씁니다. 필요한 NPC의 약 85%가 들어 있습니다.
     없는 NPC는 게임에 NPC ID로 조회해서 바꾸고, 그것도 안 되면 영문으로 나옵니다.
   - **직접 확인한 이름이 최우선입니다.** NPC를 대상으로 잡거나 마우스를 올리거나 이름표가 보이거나, 상인 창을 열거나 루팅하면 그 한글 이름으로 바뀌어 계속 저장됩니다.
     채집물·상자는 마우스를 올린 뒤 열면, 퀘스트는 퀘스트 창을 보거나 수락하면 바뀝니다.
   - 원본에는 상인 진영 정보가 거의 없습니다. 그래서 내 위치에서 가까운 순으로 정렬하고, 마우스를 올리거나 대상으로 잡았을 때 적대적이었던 상인은 기억해서 숨깁니다.
   - 판매처는 내 위치에서 가까운 순으로 보여줍니다. 드랍처는 현재 지역 몬스터를 먼저, 그 안에서 드랍률 높은 순으로 보여줍니다.
3. **게임 안 자동 기록 (ReagentSourceDB, 계정 공용)**
   - 상인 창을 열면 그 상인이 파는 재료(직업용품·재료 분류)를 기록합니다. 위치는 열었을 때의 내 위치입니다.
   - 몬스터 시체를 루팅하면 나온 재료를 기록합니다. 좌표는 루팅 위치의 평균입니다.
   - 낚시, 무두질·약초 채집·채광, 소매치기, 상자·채집물(게임 오브젝트)은 드랍으로 기록하지 않습니다.

추측하거나 다른 서버(클래식) 자료를 넣지 않습니다. 직접 본 것만 표시됩니다.

## 명령어 (`/획득처` 또는 `/rsrc`)

| 명령 | 기능 |
|---|---|
| `/획득처 상태` | 기록 수, 툴팁 연결 방식 |
| `/획득처 보기 <아이템ID/링크>` | 전체 보기 창 열기 |
| `/획득처 내보내기` | 기록을 Data.lua 형식으로 복사 (친구와 공유) |
| `/획득처 삭제 <아이템ID/링크>` | 해당 아이템 기록 삭제 |
| `/획득처 초기화 확인` | 기록 전체 삭제 (Data.lua는 유지) |
| `/획득처 단축키 <키>` | 획득처 창 단축키 변경 (기본 F12) |
| `/획득처 경로 <폴더>` | 공유 창에 보여줄 SavedVariables 폴더 경로 저장 (`초기화`로 기본값) |
| `/획득처 외부` | EG Link 자료 사용 켜기/끄기 |
| `/획득처 출처` | 데이터 출처, 라이선스 |
| `/획득처 진단` | 동작 상태 확인 (문제 신고용) |
| `/획득처 디버그` | 기록될 때마다 채팅 알림 |

## 데이터 공유 (여러 사람이 함께 모으기)

- 애드온에 아직 없는 데이터(새 판매처, 새 드랍, 한글 이름, 적대 상인)가 쌓이면 채팅창에 알림이 뜹니다.
  > 새로 수집한 획득처 데이터가 N건 있습니다. 상수님에게 파일을 보내주세요!
  채팅 알림은 접속 직후에 한 번, 플레이 중에는 새 데이터가 늘었을 때 최대 30분에 한 번 뜹니다.
- 동시에 **안내 창**이 열립니다. 순서대로 따라 하면 됩니다.
  1. **[저장]** 버튼을 누릅니다. 화면이 잠깐 다시 불러와지면서 파일에 저장됩니다.
  2. 창에 적힌 폴더의 `ReagentSource.lua` 파일을 상수님에게 보냅니다.
     경로를 복사해서 탐색기 주소창에 붙여넣으면 폴더가 바로 열립니다.
     기본값은 `C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account`이고, 이 안의 숫자#1 폴더 → SavedVariables 순서로 들어가면 됩니다.
     `/획득처 경로 <SavedVariables 폴더 전체 경로>`로 한 번 저장해 두면, 그 폴더까지 바로 열리는 경로가 표시됩니다.
     파일 이름은 바꾸지 않아도 됩니다. 누구의 데이터인지(캐릭터-서버)와 저장 시각이 파일 안에 기록됩니다.
  3. 다 보냈으면 **[완료]** 버튼을 누릅니다.
  - **[나중에]**나 닫기(X)를 누르면 화면에 빨간 ! 동그라미 아이콘(퀵슬롯 한 칸 크기)으로 남습니다. 아이콘을 누르면 창이 다시 열리고, 드래그로 옮길 수 있습니다.
  - 창이나 아이콘은 [완료]를 누르거나, 취합된 새 버전을 설치해서 보낼 데이터가 없어질 때까지 남아 있습니다.
  - 전투 중에는 큰 창을 띄우지 않고, 전투가 끝난 뒤에 띄웁니다.
- `/획득처 공유`: 안내 창 다시 열기 · `/획득처 완료`: 완료 표시
- `/획득처 알림`: 공유 알림 켜기/끄기
- 받은 파일을 합친 결과는 `CommunityData.lua`로 애드온에 들어갑니다. 새 버전을 설치하면 이미 반영된 데이터는 알림에서 자동으로 빠집니다.
- 받는 사람 이름은 `Data.lua`의 `collectorName`에서 바꿀 수 있습니다.

## 파일 구성

| 파일 | 역할 |
|---|---|
| ReagentSource.toc | 애드온 정보 (Interface 16001, SavedVariables) |
| Data.lua | 정적 획득처 표 (vendors / drops 분리), 항상 기록할 아이템(watch) |
| ExternalData.lua | EG Link 자료를 변환한 표 (자동 생성, CC BY 4.0) |
| CommunityData.lua | 사용자들이 보낸 데이터를 합친 표 (자동 생성) |
| Contrib.lua | 새 데이터 세기, 공유 알림 |
| Core.lua | 저장소, 좌표 계산, 조회, 결과 캐시, 정렬(현재 지역 우선), 중복 제거 |
| Popup.lua | 전체 보기 창, 길 안내, 단축키 처리 |
| Bindings.xml | 단축키 등록 (설정 > 단축키 > 애드온) |
| Tooltip.lua | 툴팁에 줄 추가 (TooltipDataProcessor, 없으면 OnTooltipSetItem), 중복 추가 방지 |
| Collector.lua | 상인 창 / 루팅 자동 기록 |
| Commands.lua | 슬래시 명령, 내보내기 창 |

## 데이터 출처, 라이선스

ExternalData.lua의 판매·드랍 자료:
Data from [Efficient Games](https://efficient.games), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
원본은 <https://github.com/JIVESCORP/eg-link-output-wowf> 입니다.
변경 사항: 제품 `wowf`의 모든 빌드를 합쳤고, 위치를 지역별 대표 좌표 하나로 줄였습니다.
퀘스트 전용 드랍, 무두질, 소매치기, 채집물, 낚시는 빼고 Lua 표로 변환했습니다.
게임 내 이름 등 게임 콘텐츠의 권리는 Blizzard Entertainment에 있습니다.

한글 NPC·오브젝트 이름: [QuestieDB](https://github.com/Questie/QuestieDB) `l10n/Forever` koKR. 월드맵 NPC 검색 자료(`NpcSearchData.lua`)의 NPC 이름·부제·스폰 좌표와 던전 입구 자료(`DungeonEntranceData.lua`)의 입구 좌표도 QuestieDB Forever 자료입니다. QuestieDB 팀이 허용한 GPLv3 조건으로 사용했습니다.
이 데이터가 들어 있으므로 ReagentSource를 다른 사람에게 배포할 때는 GPLv3 조건(소스 공개, 같은 라이선스)을 따라야 합니다.

## 호환성 메모 (12.x 엔진 기반 포에버 클라이언트)

- 애드온의 전투 기록(`COMBAT_LOG_EVENT_UNFILTERED`) 등록은 금지되어 있습니다(차단 경고창 발생). 그래서 사용하지 않습니다.
- 전투 중에 읽을 수 없는 "비밀 값"은 건너뛰도록 처리했습니다.
