extends SceneTree
## WebRTC add-on: the webrtc-native GDExtension is loaded on desktop, and two
## WebRTCPeerConnections in one process open an unreliable data channel and
## pass a message (no signalling server, no network). Run `make webrtc` first.
##   godot --headless --fixed-fps 120 --path . -s res://tests/webrtc_available_test.gd
##   make test-webrtc_available_test

const EXTENSION := "res://addons/webrtc_native/webrtc_native.gdextension"
const TIMEOUT_MSEC := 5000

var _ok := true


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var loaded := GDExtensionManager.is_extension_loaded(EXTENSION)
	_check("extension loaded", loaded)
	if loaded:
		_check("data channel opens and carries a message", await _loopback())
	print("webrtc_available_test %s" % ("PASSED" if _ok else "FAILED"))
	quit()


## Connects two peers directly and waits (wall-clock time) for "ping" to arrive.
## Always closes both peers: an open connection keeps webrtc-native's threads
## running and Godot then hangs on quit.
func _loopback() -> bool:
	var a := WebRTCPeerConnection.new()
	var b := WebRTCPeerConnection.new()
	if a.initialize({"iceServers": []}) != OK or b.initialize({"iceServers": []}) != OK:
		return false
	a.session_description_created.connect(func(type: String, sdp: String) -> void:
		a.set_local_description(type, sdp)
		b.set_remote_description(type, sdp))
	b.session_description_created.connect(func(type: String, sdp: String) -> void:
		b.set_local_description(type, sdp)
		a.set_remote_description(type, sdp))
	a.ice_candidate_created.connect(func(mid: String, index: int, sdp: String) -> void: b.add_ice_candidate(mid, index, sdp))
	b.ice_candidate_created.connect(func(mid: String, index: int, sdp: String) -> void: a.add_ice_candidate(mid, index, sdp))
	var options := {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0}
	var ca := a.create_data_channel("test", options)
	var cb := b.create_data_channel("test", options)
	a.create_offer()
	var got := false
	var start := Time.get_ticks_msec()
	while not got and Time.get_ticks_msec() - start < TIMEOUT_MSEC:
		a.poll()
		b.poll()
		if ca.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			ca.put_packet("ping".to_utf8_buffer())
		while cb.get_available_packet_count() > 0:
			if cb.get_packet().get_string_from_utf8() == "ping":
				got = true
		await process_frame
	_close([a, b], [ca, cb])
	return got


## Disconnects the lambdas (they hold both peers) and closes everything.
func _close(peers: Array[WebRTCPeerConnection], channels: Array[WebRTCDataChannel]) -> void:
	for pc in peers:
		for sig: StringName in [&"session_description_created", &"ice_candidate_created"]:
			for c: Dictionary in pc.get_signal_connection_list(sig):
				pc.disconnect(sig, c.callable)
	for ch in channels:
		ch.close()
	for pc in peers:
		pc.close()


func _check(what: String, ok: bool) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_ok = false
