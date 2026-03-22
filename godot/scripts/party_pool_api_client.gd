extends Node
class_name PartyPoolApiClient

@export var base_url: String = "http://127.0.0.1:8000"


func create_room() -> Dictionary:
	return await _request_json(HTTPClient.METHOD_POST, _api_url("/api/create-room"), {})


func start_round_ready_phase(room_code: String, host_token: String) -> Dictionary:
	var payload := {
		"room_code": room_code.strip_edges().to_upper(),
		"host_token": host_token.strip_edges()
	}
	return await _request_json(HTTPClient.METHOD_POST, _api_url("/api/start-round"), payload)


func room_state(room_code: String, token: String) -> Dictionary:
	var query := _encode_query({
		"room_code": room_code.strip_edges().to_upper(),
		"token": token.strip_edges()
	})
	return await _request_json(HTTPClient.METHOD_GET, _api_url("/api/room-state?" + query))


func wait_state(room_code: String, token: String, after_version: int) -> Dictionary:
	var query := _encode_query({
		"room_code": room_code.strip_edges().to_upper(),
		"token": token.strip_edges(),
		"after_version": after_version
	})
	return await _request_json(HTTPClient.METHOD_GET, _api_url("/api/wait-state?" + query))


func fetch_raw(url: String) -> Dictionary:
	return await _request_raw(HTTPClient.METHOD_GET, url)


func _request_json(method: int, url: String, payload: Variant = null) -> Dictionary:
	var headers := PackedStringArray()
	var body := ""
	if payload != null:
		headers.append("Content-Type: application/json")
		body = JSON.stringify(payload)

	var raw_result: Dictionary = await _request_raw(method, url, headers, body)
	if not bool(raw_result.get("ok", false)):
		var parsed_error: Variant = _parse_json_or_null(raw_result.get("body", PackedByteArray()))
		var error_message := str(raw_result.get("error", "request_failed"))
		if typeof(parsed_error) == TYPE_DICTIONARY and (parsed_error as Dictionary).has("error"):
			error_message = str((parsed_error as Dictionary)["error"])
		return {
			"ok": false,
			"status": int(raw_result.get("status", 0)),
			"error": error_message
		}

	var parsed: Variant = _parse_json_or_null(raw_result.get("body", PackedByteArray()))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"status": int(raw_result.get("status", 0)),
			"error": "invalid_json"
		}
	return {
		"ok": true,
		"status": int(raw_result.get("status", 200)),
		"data": parsed
	}


func _request_raw(
	method: int,
	url: String,
	headers: PackedStringArray = PackedStringArray(),
	body: String = ""
) -> Dictionary:
	var request := HTTPRequest.new()
	add_child(request)

	var start_error := request.request(url, headers, method, body)
	if start_error != OK:
		request.queue_free()
		return {
			"ok": false,
			"status": 0,
			"error": "request_start_failed_%s" % error_string(start_error),
			"body": PackedByteArray()
		}

	var completed: Array = await request.request_completed
	request.queue_free()

	var result_code := int(completed[0])
	var response_code := int(completed[1])
	var response_headers: PackedStringArray = completed[2]
	var response_body: PackedByteArray = completed[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"status": response_code,
			"error": "network_error_%d" % result_code,
			"headers": response_headers,
			"body": response_body
		}

	if response_code < 200 or response_code >= 300:
		return {
			"ok": false,
			"status": response_code,
			"error": "http_%d" % response_code,
			"headers": response_headers,
			"body": response_body
		}

	return {
		"ok": true,
		"status": response_code,
		"headers": response_headers,
		"body": response_body
	}


func _parse_json_or_null(raw: PackedByteArray) -> Variant:
	if raw.is_empty():
		return {}
	var text := raw.get_string_from_utf8()
	if text.is_empty():
		return {}
	return JSON.parse_string(text)


func _encode_query(params: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in params.keys():
		parts.append("%s=%s" % [str(key).uri_encode(), str(params[key]).uri_encode()])
	return "&".join(parts)


func _api_url(path: String) -> String:
	if path.begins_with("http://") or path.begins_with("https://"):
		return path

	var normalized := base_url.strip_edges()
	while normalized.ends_with("/"):
		normalized = normalized.substr(0, normalized.length() - 1)

	if path.begins_with("/"):
		return normalized + path
	return normalized + "/" + path
