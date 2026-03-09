@tool
extends Node
class_name MCPWebSocketServer

signal command_received(id: String, command: String, params: Dictionary)
signal client_connected()
signal client_disconnected()

const DEFAULT_PORT := 6550
const CLOSE_CODE_ALREADY_CONNECTED := 4001
const CLOSE_REASON_ALREADY_CONNECTED := "Another client is already connected"
const CLOSE_CODE_SESSION_TAKEN_OVER := 4002
const CLOSE_REASON_SESSION_TAKEN_OVER := "Connection taken over by a newer client"
const CLOSE_CODE_SERVER_DISCONNECT := 4003
const CLOSE_REASON_SERVER_DISCONNECT := "Disconnected by server command"
const HEARTBEAT_INTERVAL_SEC := 2.0
const CLOSE_GRACE_PERIOD_MSEC := 2000
const REJECTION_LOG_INTERVAL_MSEC := 5000

var _server: TCPServer
var _peer: StreamPeerTCP
var _ws_peer: WebSocketPeer
var _is_connected := false
var _rejected_connections := 0
var _pending_rejection: WebSocketPeer = null
var _pending_rejection_peer: StreamPeerTCP = null
var _pending_takeover_peer: StreamPeerTCP = null
var _pending_takeover_host: String = ""
var _pending_takeover_port: int = 0
var _connected_host: String = ""
var _connected_port: int = 0
var _closing_started_at_msec: int = -1
var _pending_rejection_closing_started_at_msec: int = -1
var _last_rejection_log_at_msec: int = -1
var _last_rejection_endpoint: String = ""
var _suppressed_rejection_logs := 0


func _process(_delta: float) -> void:
	if not _server:
		return

	_poll_active_connection()
	_process_pending_rejection()
	_process_pending_takeover()

	while _server and _server.is_connection_available():
		_accept_connection()


func start_server(port: int = DEFAULT_PORT, bind_address: String = "127.0.0.1") -> Error:
	_server = TCPServer.new()
	var err := _server.listen(port, bind_address)
	if err != OK:
		_server = null
		MCPLog.error("Failed to start server on %s:%d: %s" % [bind_address, port, error_string(err)])
		return err

	return OK


func stop_server() -> void:
	_cleanup_pending_rejection()
	_cleanup_pending_takeover()
	_cleanup_active_connection()

	if _server:
		_server.stop()
		_server = null

	_is_connected = false
	_rejected_connections = 0
	_connected_host = ""
	_connected_port = 0


func get_rejected_connection_count() -> int:
	return _rejected_connections


func get_connected_host() -> String:
	"""Returns the remote host IP address of the connected client."""
	return _connected_host


func get_connected_port() -> int:
	"""Returns the remote port of the connected client."""
	return _connected_port


func has_active_client() -> bool:
	return _has_active_connection()


func disconnect_active_client(close_code: int = CLOSE_CODE_SERVER_DISCONNECT, close_reason: String = CLOSE_REASON_SERVER_DISCONNECT) -> void:
	if not _has_active_connection():
		return

	_begin_active_close(close_code, close_reason)


func send_response(response: Dictionary) -> void:
	if not _ws_peer or _ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		MCPLog.warn("Cannot send response: not connected")
		return

	var json := JSON.stringify(response)
	_ws_peer.send_text(json)


func _accept_connection() -> void:
	var incoming := _server.take_connection()
	if not incoming:
		return

	_poll_active_connection()

	# New connections take over the current client instead of getting rejected.
	if _has_active_connection():
		_queue_takeover(incoming)
		return

	if _pending_takeover_peer != null:
		_replace_pending_takeover(incoming)
		return

	_activate_connection(incoming)


func _activate_connection(incoming: StreamPeerTCP) -> void:
	_peer = incoming
	_ws_peer = WebSocketPeer.new()
	_ws_peer.outbound_buffer_size = 16 * 1024 * 1024  # 16MB for screenshot data
	_ws_peer.heartbeat_interval = HEARTBEAT_INTERVAL_SEC
	var err := _ws_peer.accept_stream(_peer)
	if err != OK:
		MCPLog.error("Failed to accept WebSocket stream: %s" % error_string(err))
		_cleanup_active_connection()
		return

	_connected_host = _peer.get_connected_host()
	_connected_port = _peer.get_connected_port()
	MCPLog.info("TCP connection received from %s:%d, awaiting WebSocket handshake..." % [_connected_host, _connected_port])


func _queue_takeover(incoming: StreamPeerTCP) -> void:
	var takeover_host := incoming.get_connected_host()
	var takeover_port := incoming.get_connected_port()

	if _pending_takeover_peer != null:
		MCPLog.info("Replacing pending takeover client %s:%d with newer connection from %s:%d" % [
			_pending_takeover_host,
			_pending_takeover_port,
			takeover_host,
			takeover_port,
		])
		_cleanup_pending_takeover()

	_pending_takeover_peer = incoming
	_pending_takeover_host = takeover_host
	_pending_takeover_port = takeover_port

	MCPLog.info("Taking over active client %s:%d with new connection from %s:%d" % [
		_connected_host,
		_connected_port,
		takeover_host,
		takeover_port,
	])
	_begin_active_close(CLOSE_CODE_SESSION_TAKEN_OVER, CLOSE_REASON_SESSION_TAKEN_OVER)


func _replace_pending_takeover(incoming: StreamPeerTCP) -> void:
	var takeover_host := incoming.get_connected_host()
	var takeover_port := incoming.get_connected_port()
	MCPLog.info("Replacing pending takeover client %s:%d with newer connection from %s:%d" % [
		_pending_takeover_host,
		_pending_takeover_port,
		takeover_host,
		takeover_port,
	])
	_cleanup_pending_takeover()
	_pending_takeover_peer = incoming
	_pending_takeover_host = takeover_host
	_pending_takeover_port = takeover_port


func _reject_connection(incoming: StreamPeerTCP) -> void:
	_rejected_connections += 1

	var remote_host := incoming.get_connected_host()
	var remote_port := incoming.get_connected_port()

	# If we're already processing a rejection, just drop this one at TCP level
	if _pending_rejection != null:
		incoming.disconnect_from_host()
		_log_rejection("Rejected connection at TCP level (busy processing previous rejection)", remote_host, remote_port)
		return

	# Accept WebSocket to send proper close code with reason
	_pending_rejection_peer = incoming
	_pending_rejection = WebSocketPeer.new()
	_pending_rejection.heartbeat_interval = HEARTBEAT_INTERVAL_SEC
	var err := _pending_rejection.accept_stream(_pending_rejection_peer)
	if err != OK:
		# Fall back to TCP disconnect
		incoming.disconnect_from_host()
		_cleanup_pending_rejection()
		_log_rejection("Rejected connection at TCP level (WebSocket accept failed)", remote_host, remote_port)
		return

	_log_rejection("Rejecting connection (another client already connected)", remote_host, remote_port)


func _process_pending_rejection() -> void:
	if _pending_rejection == null:
		return

	if _pending_rejection_peer:
		_pending_rejection_peer.poll()
		var pending_tcp_status := _pending_rejection_peer.get_status()
		if pending_tcp_status == StreamPeerSocket.STATUS_NONE or pending_tcp_status == StreamPeerSocket.STATUS_ERROR:
			_cleanup_pending_rejection()
			return

	_pending_rejection.poll()
	var state := _pending_rejection.get_ready_state()
	var now := Time.get_ticks_msec()

	match state:
		WebSocketPeer.STATE_CONNECTING:
			# Still waiting for handshake, will send close once ready
			_pending_rejection_closing_started_at_msec = -1

		WebSocketPeer.STATE_OPEN:
			# Handshake complete, now send close with our custom code
			_pending_rejection_closing_started_at_msec = now
			_pending_rejection.close(CLOSE_CODE_ALREADY_CONNECTED, CLOSE_REASON_ALREADY_CONNECTED)

		WebSocketPeer.STATE_CLOSING:
			# Waiting for close to complete
			if _pending_rejection_closing_started_at_msec < 0:
				_pending_rejection_closing_started_at_msec = now
			elif now - _pending_rejection_closing_started_at_msec >= CLOSE_GRACE_PERIOD_MSEC:
				MCPLog.warn("Force-cleaning stalled rejected connection close")
				_cleanup_pending_rejection()

		WebSocketPeer.STATE_CLOSED:
			# Done, clean up
			_cleanup_pending_rejection()


func _process_pending_takeover() -> void:
	if _pending_takeover_peer == null:
		return

	_pending_takeover_peer.poll()
	var takeover_status := _pending_takeover_peer.get_status()
	if takeover_status == StreamPeerSocket.STATUS_NONE or takeover_status == StreamPeerSocket.STATUS_ERROR:
		MCPLog.info("Pending takeover client %s:%d disconnected before activation" % [
			_pending_takeover_host,
			_pending_takeover_port,
		])
		_cleanup_pending_takeover()
		return

	if _has_active_connection():
		return

	var incoming := _pending_takeover_peer
	var takeover_host := _pending_takeover_host
	var takeover_port := _pending_takeover_port
	_pending_takeover_peer = null
	_pending_takeover_host = ""
	_pending_takeover_port = 0

	MCPLog.info("Accepting replacement client from %s:%d" % [takeover_host, takeover_port])
	_activate_connection(incoming)


func _process_websocket() -> void:
	if not _ws_peer:
		return

	var state := _ws_peer.get_ready_state()
	var now := Time.get_ticks_msec()

	match state:
		WebSocketPeer.STATE_CONNECTING:
			_closing_started_at_msec = -1

		WebSocketPeer.STATE_OPEN:
			_closing_started_at_msec = -1
			if not _is_connected:
				_is_connected = true
				client_connected.emit()
				MCPLog.info("WebSocket handshake complete")

			while _ws_peer.get_available_packet_count() > 0:
				var packet := _ws_peer.get_packet()
				_handle_packet(packet)

		WebSocketPeer.STATE_CLOSING:
			if _closing_started_at_msec < 0:
				_closing_started_at_msec = now
			elif now - _closing_started_at_msec >= CLOSE_GRACE_PERIOD_MSEC:
				MCPLog.warn("Force-cleaning stalled client close for %s:%d" % [_connected_host, _connected_port])
				_cleanup_active_connection()

		WebSocketPeer.STATE_CLOSED:
			_cleanup_active_connection()


func _begin_active_close(close_code: int, close_reason: String) -> void:
	if _ws_peer == null:
		_cleanup_active_connection()
		return

	var state := _ws_peer.get_ready_state()
	var now := Time.get_ticks_msec()

	match state:
		WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_OPEN:
			_closing_started_at_msec = now
			_ws_peer.close(close_code, close_reason)
			_ws_peer.poll()
		WebSocketPeer.STATE_CLOSING:
			if _closing_started_at_msec < 0:
				_closing_started_at_msec = now
		WebSocketPeer.STATE_CLOSED:
			_cleanup_active_connection()


func _poll_active_connection() -> void:
	if _peer:
		_peer.poll()
		var tcp_status := _peer.get_status()
		if tcp_status == StreamPeerSocket.STATUS_NONE or tcp_status == StreamPeerSocket.STATUS_ERROR:
			MCPLog.info("Releasing stale TCP connection from %s:%d (status: %s)" % [_connected_host, _connected_port, _socket_status_name(tcp_status)])
			_cleanup_active_connection()
			return

	if _ws_peer:
		_ws_peer.poll()
		_process_websocket()


func _has_active_connection() -> bool:
	if _ws_peer == null:
		return false

	var state := _ws_peer.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		_cleanup_active_connection()
		return false

	if _peer == null:
		_cleanup_active_connection()
		return false

	return true


func _cleanup_active_connection() -> void:
	if _ws_peer:
		_ws_peer = null

	if _peer:
		_peer.disconnect_from_host()
		_peer = null

	if _is_connected:
		_is_connected = false
		client_disconnected.emit()

	_connected_host = ""
	_connected_port = 0
	_closing_started_at_msec = -1


func _cleanup_pending_rejection() -> void:
	if _pending_rejection:
		_pending_rejection = null

	if _pending_rejection_peer:
		_pending_rejection_peer.disconnect_from_host()
		_pending_rejection_peer = null

	_pending_rejection_closing_started_at_msec = -1


func _cleanup_pending_takeover() -> void:
	if _pending_takeover_peer:
		_pending_takeover_peer.disconnect_from_host()
		_pending_takeover_peer = null

	_pending_takeover_host = ""
	_pending_takeover_port = 0


func _log_rejection(prefix: String, remote_host: String, remote_port: int) -> void:
	var endpoint := "%s:%d" % [remote_host, remote_port]
	var now := Time.get_ticks_msec()
	var can_log := _last_rejection_log_at_msec < 0
	can_log = can_log or endpoint != _last_rejection_endpoint
	can_log = can_log or (now - _last_rejection_log_at_msec) >= REJECTION_LOG_INTERVAL_MSEC

	if not can_log:
		_suppressed_rejection_logs += 1
		return

	var suppressed_suffix := ""
	if _suppressed_rejection_logs > 0:
		suppressed_suffix = " | suppressed %d similar rejection(s)" % _suppressed_rejection_logs

	MCPLog.info("%s from %s - total rejections: %d%s" % [
		prefix,
		endpoint,
		_rejected_connections,
		suppressed_suffix,
	])

	_last_rejection_log_at_msec = now
	_last_rejection_endpoint = endpoint
	_suppressed_rejection_logs = 0


func _socket_status_name(status: int) -> String:
	match status:
		StreamPeerSocket.STATUS_NONE:
			return "none"
		StreamPeerSocket.STATUS_CONNECTING:
			return "connecting"
		StreamPeerSocket.STATUS_CONNECTED:
			return "connected"
		StreamPeerSocket.STATUS_ERROR:
			return "error"
		_:
			return "unknown"


func _handle_packet(packet: PackedByteArray) -> void:
	var text := packet.get_string_from_utf8()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		MCPLog.error("Failed to parse command: %s" % json.get_error_message())
		_send_error_response("", "PARSE_ERROR", "Invalid JSON: %s" % json.get_error_message())
		return

	if not json.data is Dictionary:
		MCPLog.error("Invalid command format: expected JSON object")
		_send_error_response("", "INVALID_FORMAT", "Expected JSON object")
		return

	var data: Dictionary = json.data
	if not data.has("id") or not data.has("command"):
		MCPLog.error("Invalid command format")
		_send_error_response(data.get("id", ""), "INVALID_FORMAT", "Missing 'id' or 'command' field")
		return

	var id: String = str(data.get("id"))
	var command: String = data.get("command")
	var params: Dictionary = data.get("params", {})

	command_received.emit(id, command, params)


func _send_error_response(id: String, code: String, message: String) -> void:
	send_response({
		"id": id,
		"status": "error",
		"error": {
			"code": code,
			"message": message
		}
	})
