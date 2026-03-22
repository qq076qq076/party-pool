# Godot Host Integration (GDScript)

這個資料夾提供可直接匯入 Godot 4 的主畫面整合腳本，對接目前 `prototype/server.py` API。

## 檔案
- `scripts/party_pool_api_client.gd`：HTTP API 封裝（create/start/room-state/wait-state）
- `scripts/party_pool_i18n.gd`：`en` / `zh-TW` 文案與 phase label
- `scripts/party_pool_host_main.gd`：主畫面流程控制（C1/C2/C3）

## 匯入方式
1. 把整個 `godot/scripts` 複製到你的 Godot 專案（例如 `res://scripts/`）。
2. 在 Host 場景的根節點（`Control`）掛上 `party_pool_host_main.gd`。
3. 在 Inspector 設定：
   - `base_url`：例如 `http://127.0.0.1:8000`
   - 各 NodePath（可用預設名稱，或改成你自己的節點路徑）

## 建議節點名稱（可直接用預設）
- `CreateRoomButton` (`Button`)
- `StartRoundButton` (`Button`)
- `LangZhButton` (`Button`)
- `LangEnButton` (`Button`)
- `RoomInfoPanel` (`Control` / `Panel`)
- `StatusLabel` (`Label`)
- `RoomCodeValueLabel` (`Label`)
- `JoinUrlValue` (`Label` 或 `LinkButton`)
- `QrTextureRect` (`TextureRect`)
- `PhaseValueLabel` (`Label`)
- `RoundValueLabel` (`Label`)
- `ModeValueLabel` (`Label`)
- `ReadyTimerValueLabel` (`Label`)
- `RoundTimerValueLabel` (`Label`)
- `PlayersList` (`ItemList` / `Label` / `RichTextLabel` / `TextEdit` / `VBoxContainer`)
- `ResultView` (`Label` / `RichTextLabel` / `TextEdit`)

## 對應任務拆分
- C1 房間畫面：房間碼、Join URL、QR、玩家清單、連線狀態
- C2 回合流程：ready 倒數、round 倒數、mode 顯示、即時同步
- C3 結算畫面：`last_round_result` 顯示

## 已知限制（目前原型 API 本身）
- 目前是 HTTP + long-poll（`/api/wait-state`），尚未升級正式 WSS。
- 主畫面與控制器 UI 視覺呈現需在你的場景中自行排版；腳本專注流程整合。
