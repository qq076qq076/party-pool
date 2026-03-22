extends Control
class_name PartyPoolHostMain

# Expected usage:
# 1. Attach this script to your host scene root (Control).
# 2. Set `base_url` to your prototype server URL.
# 3. Assign NodePaths in the Inspector, or keep default names.

const SETTINGS_PATH := "user://party_pool_host.cfg"
const SETTINGS_SECTION := "host"
const SETTINGS_LANG_KEY := "lang"

@export var base_url: String = "http://127.0.0.1:8000"

@export_group("Buttons")
@export var create_room_button_path: NodePath = ^"CreateRoomButton"
@export var start_round_button_path: NodePath = ^"StartRoundButton"
@export var lang_zh_button_path: NodePath = ^"LangZhButton"
@export var lang_en_button_path: NodePath = ^"LangEnButton"

@export_group("Panels")
@export var room_info_panel_path: NodePath = ^"RoomInfoPanel"

@export_group("Value Nodes")
@export var status_label_path: NodePath = ^"StatusLabel"
@export var room_code_value_path: NodePath = ^"RoomCodeValueLabel"
@export var join_url_value_path: NodePath = ^"JoinUrlValue"
@export var qr_texture_rect_path: NodePath = ^"QrTextureRect"
@export var phase_value_path: NodePath = ^"PhaseValueLabel"
@export var round_value_path: NodePath = ^"RoundValueLabel"
@export var mode_value_path: NodePath = ^"ModeValueLabel"
@export var ready_timer_value_path: NodePath = ^"ReadyTimerValueLabel"
@export var round_timer_value_path: NodePath = ^"RoundTimerValueLabel"
@export var players_view_path: NodePath = ^"PlayersList"
@export var result_view_path: NodePath = ^"ResultView"

@export_group("Optional Title Labels")
@export var title_label_path: NodePath = ^"TitleLabel"
@export var subtitle_label_path: NodePath = ^"SubtitleLabel"
@export var room_info_title_path: NodePath = ^"RoomInfoTitleLabel"
@export var room_code_title_path: NodePath = ^"RoomCodeTitleLabel"
@export var join_url_title_path: NodePath = ^"JoinUrlTitleLabel"
@export var live_state_title_path: NodePath = ^"LiveStateTitleLabel"
@export var phase_title_path: NodePath = ^"PhaseTitleLabel"
@export var round_title_path: NodePath = ^"RoundTitleLabel"
@export var mode_title_path: NodePath = ^"ModeTitleLabel"
@export var ready_timer_title_path: NodePath = ^"ReadyTimerTitleLabel"
@export var round_timer_title_path: NodePath = ^"RoundTimerTitleLabel"
@export var players_title_path: NodePath = ^"PlayersTitleLabel"
@export var last_round_title_path: NodePath = ^"LastRoundTitleLabel"

@onready var _create_room_button: Button = get_node_or_null(create_room_button_path) as Button
@onready var _start_round_button: Button = get_node_or_null(start_round_button_path) as Button
@onready var _lang_zh_button: Button = get_node_or_null(lang_zh_button_path) as Button
@onready var _lang_en_button: Button = get_node_or_null(lang_en_button_path) as Button

@onready var _room_info_panel: CanvasItem = get_node_or_null(room_info_panel_path) as CanvasItem

@onready var _status_node: Node = get_node_or_null(status_label_path)
@onready var _room_code_value_node: Node = get_node_or_null(room_code_value_path)
@onready var _join_url_value_node: Node = get_node_or_null(join_url_value_path)
@onready var _qr_texture_rect: TextureRect = get_node_or_null(qr_texture_rect_path) as TextureRect
@onready var _phase_value_node: Node = get_node_or_null(phase_value_path)
@onready var _round_value_node: Node = get_node_or_null(round_value_path)
@onready var _mode_value_node: Node = get_node_or_null(mode_value_path)
@onready var _ready_timer_value_node: Node = get_node_or_null(ready_timer_value_path)
@onready var _round_timer_value_node: Node = get_node_or_null(round_timer_value_path)
@onready var _players_view_node: Node = get_node_or_null(players_view_path)
@onready var _result_view_node: Node = get_node_or_null(result_view_path)

@onready var _title_label: Node = get_node_or_null(title_label_path)
@onready var _subtitle_label: Node = get_node_or_null(subtitle_label_path)
@onready var _room_info_title_label: Node = get_node_or_null(room_info_title_path)
@onready var _room_code_title_label: Node = get_node_or_null(room_code_title_path)
@onready var _join_url_title_label: Node = get_node_or_null(join_url_title_path)
@onready var _live_state_title_label: Node = get_node_or_null(live_state_title_path)
@onready var _phase_title_label: Node = get_node_or_null(phase_title_path)
@onready var _round_title_label: Node = get_node_or_null(round_title_path)
@onready var _mode_title_label: Node = get_node_or_null(mode_title_path)
@onready var _ready_timer_title_label: Node = get_node_or_null(ready_timer_title_path)
@onready var _round_timer_title_label: Node = get_node_or_null(round_timer_title_path)
@onready var _players_title_label: Node = get_node_or_null(players_title_path)
@onready var _last_round_title_label: Node = get_node_or_null(last_round_title_path)

var _api: PartyPoolApiClient
var _tick_timer: Timer

var _lang := "en"
var _room_code := ""
var _host_token := ""
var _snapshot: Dictionary = {}
var _last_version := 0
var _snapshot_received_at_msec := 0
var _wait_loop_running := false


func _ready() -> void:
	_api = PartyPoolApiClient.new()
	_api.base_url = base_url
	add_child(_api)

	_lang = _load_lang_setting()
	_wire_buttons()
	_apply_i18n()
	_set_status("")
	_set_room_info_visible(false)

	if _start_round_button != null:
		_start_round_button.disabled = true

	_tick_timer = Timer.new()
	_tick_timer.wait_time = 0.35
	_tick_timer.autostart = true
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_render_snapshot)
	add_child(_tick_timer)


func _exit_tree() -> void:
	_wait_loop_running = false


func _wire_buttons() -> void:
	if _create_room_button != null:
		_create_room_button.pressed.connect(_on_create_room_pressed)
	if _start_round_button != null:
		_start_round_button.pressed.connect(_on_start_round_pressed)
	if _lang_zh_button != null:
		_lang_zh_button.pressed.connect(func() -> void:
			_set_lang("zh-TW")
		)
	if _lang_en_button != null:
		_lang_en_button.pressed.connect(func() -> void:
			_set_lang("en")
		)


func _set_lang(value: String) -> void:
	_lang = value
	_save_lang_setting(_lang)
	_apply_i18n()
	_render_snapshot()


func _t(key: String) -> String:
	return PartyPoolI18n.host_t(_lang, key)


func _apply_i18n() -> void:
	_set_text(_title_label, _t("title"))
	_set_text(_subtitle_label, _t("subtitle"))
	_set_text(_room_info_title_label, _t("roomInfo"))
	_set_text(_room_code_title_label, _t("roomCode"))
	_set_text(_join_url_title_label, _t("joinUrl"))
	_set_text(_live_state_title_label, _t("liveState"))
	_set_text(_phase_title_label, _t("phase"))
	_set_text(_round_title_label, _t("round"))
	_set_text(_mode_title_label, _t("mode"))
	_set_text(_ready_timer_title_label, _t("readyTimer"))
	_set_text(_round_timer_title_label, _t("roundTimer"))
	_set_text(_players_title_label, _t("players"))
	_set_text(_last_round_title_label, _t("lastRound"))

	if _create_room_button != null:
		_create_room_button.text = _t("createRoom")
	if _start_round_button != null:
		_start_round_button.text = _t("startRound")


func _on_create_room_pressed() -> void:
	if _create_room_button != null:
		_create_room_button.disabled = true

	var response: Dictionary = await _api.create_room()
	if _create_room_button != null:
		_create_room_button.disabled = false

	if not bool(response.get("ok", false)):
		_set_status(str(response.get("error", "request_failed")))
		return

	var data_variant: Variant = response.get("data", {})
	if typeof(data_variant) != TYPE_DICTIONARY:
		_set_status("invalid_response")
		return
	var data: Dictionary = data_variant

	_room_code = str(data.get("room_code", ""))
	_host_token = str(data.get("host_token", ""))

	_set_room_info_visible(true)
	_set_text(_room_code_value_node, _room_code)
	_set_join_url(str(data.get("join_url", "")))
	await _load_qr_texture(str(data.get("qr_url", "")))

	_set_status(_t("statusCreated"))
	await _poll_state_once()
	_start_wait_loop()


func _on_start_round_pressed() -> void:
	if _room_code.is_empty() or _host_token.is_empty():
		_set_status(_t("statusNeedRoom"))
		return

	if _start_round_button != null:
		_start_round_button.disabled = true

	var response: Dictionary = await _api.start_round_ready_phase(_room_code, _host_token)
	if not bool(response.get("ok", false)):
		_set_status(str(response.get("error", "request_failed")))
		_render_snapshot()
		return

	_set_status(_t("statusStarted"))
	await _poll_state_once()


func _poll_state_once() -> void:
	if _room_code.is_empty() or _host_token.is_empty():
		return

	var response: Dictionary = await _api.room_state(_room_code, _host_token)
	if not bool(response.get("ok", false)):
		_set_status(str(response.get("error", "request_failed")))
		return

	var data_variant: Variant = response.get("data", {})
	if typeof(data_variant) == TYPE_DICTIONARY:
		_update_snapshot(data_variant)


func _start_wait_loop() -> void:
	if _wait_loop_running:
		return
	_wait_loop_running = true
	_wait_loop()


func _wait_loop() -> void:
	while _wait_loop_running and not _room_code.is_empty() and not _host_token.is_empty():
		var response: Dictionary = await _api.wait_state(_room_code, _host_token, _last_version)
		if bool(response.get("ok", false)):
			var data_variant: Variant = response.get("data", {})
			if typeof(data_variant) == TYPE_DICTIONARY:
				_update_snapshot(data_variant)
		else:
			await get_tree().create_timer(0.8).timeout
	_wait_loop_running = false


func _update_snapshot(snap: Dictionary) -> void:
	_snapshot = snap
	_last_version = int(snap.get("version", _last_version))
	_snapshot_received_at_msec = Time.get_ticks_msec()
	_render_snapshot()


func _render_snapshot() -> void:
	if _snapshot.is_empty():
		return

	var status := str(_snapshot.get("status", ""))
	var round_index := int(_snapshot.get("round_index", 0))
	var total_rounds := int(_snapshot.get("total_rounds", 0))

	_set_text(_phase_value_node, PartyPoolI18n.phase_label(_lang, status))
	_set_text(_round_value_node, "%d/%d" % [round_index, total_rounds])
	_set_text(_ready_timer_value_node, _seconds_left(_snapshot.get("ready_deadline_at", null), _snapshot.get("server_time", null)))
	_set_text(_round_timer_value_node, _seconds_left(_snapshot.get("round_end_at", null), _snapshot.get("server_time", null)))

	var mode_text := "-"
	var control_profile_variant: Variant = _snapshot.get("control_profile", {})
	if typeof(control_profile_variant) == TYPE_DICTIONARY:
		mode_text = str((control_profile_variant as Dictionary).get("mode", "-"))
	_set_text(_mode_value_node, mode_text)

	if _start_round_button != null:
		_start_round_button.disabled = not (status == "waiting" or status == "ended")

	var players_lines := PackedStringArray()
	var players_variant: Variant = _snapshot.get("players", [])
	if typeof(players_variant) == TYPE_ARRAY:
		for item in players_variant:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var player: Dictionary = item
			var line := "%s | %s:%s | %s:%s | %s:%d | %s:%d" % [
				str(player.get("nickname", "Player")),
				_t("connected"),
				_t("yes") if bool(player.get("connected", false)) else _t("no"),
				_t("ready"),
				_t("yes") if bool(player.get("ready_ok", false)) else _t("no"),
				_t("taps"),
				int(player.get("taps", 0)),
				_t("score"),
				int(player.get("score", 0))
			]
			players_lines.append(line)
	_set_players_lines(players_lines)

	var last_result: Variant = _snapshot.get("last_round_result", null)
	if typeof(last_result) == TYPE_DICTIONARY:
		_set_result_text(JSON.stringify(last_result, "  "))
	else:
		_set_result_text("-")


func _seconds_left(deadline_value: Variant, server_time_value: Variant) -> String:
	if deadline_value == null or server_time_value == null:
		return "-"

	var deadline := float(deadline_value)
	var server_time := float(server_time_value)
	if deadline <= 0.0 or server_time <= 0.0:
		return "-"

	var elapsed := float(Time.get_ticks_msec() - _snapshot_received_at_msec) / 1000.0
	var adjusted_server_time := server_time + max(0.0, elapsed)
	var left := int(max(0.0, ceil(deadline - adjusted_server_time)))
	return str(left)


func _load_qr_texture(url: String) -> void:
	if _qr_texture_rect == null or url.is_empty():
		return

	var response: Dictionary = await _api.fetch_raw(url)
	if not bool(response.get("ok", false)):
		return

	var body: PackedByteArray = response.get("body", PackedByteArray())
	var image := Image.new()
	var err := image.load_png_from_buffer(body)
	if err != OK:
		err = image.load_jpg_from_buffer(body)
	if err != OK:
		return

	_qr_texture_rect.texture = ImageTexture.create_from_image(image)


func _set_room_info_visible(visible: bool) -> void:
	if _room_info_panel != null:
		_room_info_panel.visible = visible


func _set_status(text: String) -> void:
	_set_text(_status_node, text)


func _set_join_url(url: String) -> void:
	if _join_url_value_node == null:
		return
	if _join_url_value_node is LinkButton:
		var link := _join_url_value_node as LinkButton
		link.text = url
		link.uri = url
		return
	_set_text(_join_url_value_node, url)


func _set_players_lines(lines: PackedStringArray) -> void:
	if _players_view_node == null:
		return

	var as_text := "\n".join(lines)
	if _players_view_node is ItemList:
		var list := _players_view_node as ItemList
		list.clear()
		for line in lines:
			list.add_item(line)
		return
	if _players_view_node is RichTextLabel:
		(_players_view_node as RichTextLabel).text = as_text
		return
	if _players_view_node is Label:
		(_players_view_node as Label).text = as_text
		return
	if _players_view_node is TextEdit:
		(_players_view_node as TextEdit).text = as_text
		return
	if _players_view_node is VBoxContainer:
		var box := _players_view_node as VBoxContainer
		for child in box.get_children():
			child.queue_free()
		for line in lines:
			var label := Label.new()
			label.text = line
			box.add_child(label)


func _set_result_text(text: String) -> void:
	if _result_view_node == null:
		return
	if _result_view_node is RichTextLabel:
		(_result_view_node as RichTextLabel).text = text
		return
	if _result_view_node is Label:
		(_result_view_node as Label).text = text
		return
	if _result_view_node is TextEdit:
		(_result_view_node as TextEdit).text = text
		return


func _set_text(node: Node, text: String) -> void:
	if node == null:
		return
	if node is Label:
		(node as Label).text = text
		return
	if node is Button:
		(node as Button).text = text
		return
	if node is RichTextLabel:
		(node as RichTextLabel).text = text
		return
	if node is LineEdit:
		(node as LineEdit).text = text
		return
	if node is TextEdit:
		(node as TextEdit).text = text
		return


func _load_lang_setting() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved := str(cfg.get_value(SETTINGS_SECTION, SETTINGS_LANG_KEY, ""))
		if saved == "en" or saved == "zh-TW":
			return saved
	return PartyPoolI18n.detect_default_lang()


func _save_lang_setting(lang: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SETTINGS_SECTION, SETTINGS_LANG_KEY, lang)
	cfg.save(SETTINGS_PATH)
