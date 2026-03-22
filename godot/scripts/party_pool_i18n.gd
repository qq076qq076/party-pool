extends RefCounted
class_name PartyPoolI18n

const HOST_TEXT := {
	"en": {
		"title": "Party Pool Host",
		"subtitle": "Survival Test party game prototype",
		"createRoom": "Create Room",
		"startRound": "Start Round",
		"roomInfo": "Room Info",
		"roomCode": "Room Code",
		"joinUrl": "Join URL",
		"liveState": "Live State",
		"phase": "Phase",
		"round": "Round",
		"mode": "Mode",
		"readyTimer": "Ready Timer",
		"roundTimer": "Round Timer",
		"players": "Players",
		"lastRound": "Last Round",
		"name": "Name",
		"connected": "Connected",
		"ready": "Ready",
		"taps": "Taps",
		"score": "Score",
		"statusCreated": "Room created.",
		"statusStarted": "Round prepare phase started.",
		"statusNeedRoom": "Create a room first.",
		"yes": "Yes",
		"no": "No",
		"round1.tap_fast": "Tap as fast as possible."
	},
	"zh-TW": {
		"title": "Party Pool 主畫面",
		"subtitle": "生存力測試派對遊戲原型",
		"createRoom": "開房間",
		"startRound": "開始回合",
		"roomInfo": "房間資訊",
		"roomCode": "房間碼",
		"joinUrl": "加入連結",
		"liveState": "即時狀態",
		"phase": "階段",
		"round": "回合",
		"mode": "模式",
		"readyTimer": "準備倒數",
		"roundTimer": "回合倒數",
		"players": "玩家",
		"lastRound": "上一回合結果",
		"name": "名稱",
		"connected": "連線",
		"ready": "已準備",
		"taps": "點擊數",
		"score": "分數",
		"statusCreated": "房間已建立。",
		"statusStarted": "已進入回合準備階段。",
		"statusNeedRoom": "請先建立房間。",
		"yes": "是",
		"no": "否",
		"round1.tap_fast": "在時間內盡可能快速點擊。"
	}
}

const PHASE_LABELS := {
	"en": {
		"waiting": "Waiting",
		"readying": "Readying",
		"playing": "Playing",
		"ended": "Ended"
	},
	"zh-TW": {
		"waiting": "等待中",
		"readying": "準備中",
		"playing": "進行中",
		"ended": "已結束"
	}
}

static func detect_default_lang(locale: String = "") -> String:
	var value := locale
	if value.is_empty():
		value = TranslationServer.get_locale()
	var normalized := value.to_lower()
	if normalized.begins_with("zh"):
		return "zh-TW"
	return "en"


static func host_t(lang: String, key: String) -> String:
	var table: Dictionary = HOST_TEXT.get(lang, HOST_TEXT["en"])
	return str(table.get(key, HOST_TEXT["en"].get(key, key)))


static func phase_label(lang: String, phase: String) -> String:
	var table: Dictionary = PHASE_LABELS.get(lang, PHASE_LABELS["en"])
	return str(table.get(phase, phase))
