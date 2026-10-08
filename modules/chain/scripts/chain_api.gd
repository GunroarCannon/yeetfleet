## The leaderboard Worker's HTTP API (services/leaderboard-worker), for
## [Chain] only: other modules go through Chain.
##
## Every call returns [code]{ok = true, …the JSON body}[/code] or
## [code]{ok = false, code, message, status}[/code]. [code]code[/code] is the
## Worker's error code, or "offline" when it couldn't be reached at all.
extends RefCounted

## A request gives up after this long (a phone on a bad signal).
const TIMEOUT_SEC := 12.0


static func post(base: String, path: String, body: Dictionary, token := "") -> Dictionary:
	return await send(base, HTTPClient.METHOD_POST, path, body, token)


static func fetch(base: String, path: String, token := "") -> Dictionary:
	return await send(base, HTTPClient.METHOD_GET, path, null, token)


static func send(base: String, method: int, path: String, body: Variant, token := "") -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or base == "":
		return {"ok": false, "code": "offline", "message": "No server", "status": 0}
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SEC
	tree.root.add_child.call_deferred(http)
	await tree.process_frame
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var data := JSON.stringify(body) if body != null else ""
	if http.request(base.trim_suffix("/") + path, headers, method, data) != OK:
		http.queue_free()
		return {"ok": false, "code": "offline", "message": "Could not start the request", "status": 0}
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": "offline", "message": "No answer from the server (%d)" % res[0], "status": 0}
	var parsed: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	var out: Dictionary = parsed if parsed is Dictionary else {}
	var status: int = res[1]
	if status >= 200 and status < 300:
		out["ok"] = true
		return out
	return {"ok": false, "code": String(out.get("error", "http_%d" % status)),
			"message": String(out.get("message", "HTTP %d" % status)), "status": status}
