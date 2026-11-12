/*******************************************************************************
*  QNetConnection
*
*  One remote peer. You receive these from QNetwork callbacks and message handlers;
*  QNet creates and destroys them, never call the constructor yourself.
*
*  HOW RELIABILITY WORKS
*  ---------------------
*  Two layers, each simple on its own:
*
*  1. Packets. Every packet carries a sequence number, plus the latest sequence number
*     we have received from the peer and a 32-bit mask of the 32 before it. So every
*     packet in either direction acknowledges recent packets the other way. That tells
*     each side which of its packets arrived, and gives a round-trip time for free.
*
*  2. Messages. Messages are queued by Send() and packed into the next packet:
*       UNRELIABLE   written once, forgotten.
*       SEQUENCED    stamped with a counter; the receiver drops anything older than the
*                    newest it has seen.
*       RELIABLE     stamped with a message id and kept until a packet containing it is
*                    acknowledged. If no ack comes within max(100ms, rtt * 1.5) it is
*                    written into a later packet again. The receiver holds messages that
*                    arrive early and releases them strictly in id order, once each.
*
*  Nothing here blocks: a lost packet only delays the reliable messages behind it.
*******************************************************************************/

/// feather ignore all

/// @param {Struct.QNetwork} _network
/// @param {Real} _id Remote peer id: 0 is always the host, clients are 1..max_clients.
/// @param {String} _ip
/// @param {Real} _port
function QNetConnection(_network, _id, _ip, _port) constructor
{
	#region ---- Public, read-only ---------------------------------------------------

	/// The QNetwork that owns this connection.
	network = _network;
	/// The remote peer's id. 0 is the host; clients are 1..max_clients.
	id = _id;
	ip = _ip;
	port = _port;
	/// @type {Enum.QNET_STATE}
	state = QNET_STATE.DISCONNECTED;
	/// Smoothed round-trip time in milliseconds.
	rtt = 0;
	/// Smoothed fraction (0..1) of our packets that were never acknowledged.
	packet_loss = 0;
	stats = {
		packets_sent:     0,
		packets_received: 0,
		packets_lost:     0,
		bytes_sent:       0,
		bytes_received:   0,
		/// Reliable messages written again because their first packet was not acknowledged.
		resends:          0,
	};

	#endregion

	#region ---- Public methods ------------------------------------------------------

	/// Queue a message for this peer. It goes out on QNet's next update, packed with anything
	/// else queued this frame.
	/// @param {Struct} _message An instance of a registered message type.
	/// @param {Enum.QNET_CHANNEL} [_channel] Defaults to QNET_CHANNEL.RELIABLE.
	/// @returns {Bool} false if this connection is not connected.
	static Send = function(_message, _channel = QNET_CHANNEL.RELIABLE)
	{
		__qnet_check_channel(_channel);
		if (state != QNET_STATE.CONNECTED)
		{
			__qnet_warn_once($"send-{id}-{state}", $"Send() on connection {id} ignored: it is not connected. Wait for OnConnected.");
			return false;
		}
		__Enqueue(network.__EncodeMessage(_message), _channel);
		return true;
	}

	/// Close this connection. On a host this kicks the client; on a client this leaves the host.
	/// The peer is notified, and OnDisconnected (or OnConnectFailed while joining) fires locally.
	static Disconnect = function()
	{
		network.__Drop(self, QNET_REASON.LOCAL, true);
	}

	/// @returns {Bool}
	static IsConnected = function()
	{
		return state == QNET_STATE.CONNECTED;
	}

	static toString = function()
	{
		static _state_names = ["disconnected", "connecting", "challenged", "connected"];
		return $"#{id} {ip}:{port} {_state_names[state]} rtt {round(rtt)}ms loss {round(packet_loss * 100)}%";
	}

	#endregion

	#region ---- Internal state ------------------------------------------------------

	__session = 0;               // client_salt ^ server_salt, stamped on every packet after the handshake
	__client_salt = 0;
	__handshake_started = 0;
	__last_handshake_send = -1000000;
	__last_send_time = 0;
	__last_receive_time = 0;

	// Packet layer
	__send_seq      = 0;
	__sent_seq      = array_create(QNET_SEQUENCE_RING, -1);       // seq stored in each ring slot
	__sent_time     = array_create(QNET_SEQUENCE_RING, 0);
	__sent_acked    = array_create(QNET_SEQUENCE_RING, true);
	__sent_reliable = array_create(QNET_SEQUENCE_RING, undefined); // reliable message ids carried by that packet
	__recv_latest   = -1;
	__recv_seqs     = array_create(QNET_SEQUENCE_RING, -1);
	__ack_pending   = false;
	__rtt_sampled   = false;

	// Unreliable + sequenced messages waiting for the next flush: { channel, seq, buffer, size }
	__outgoing = [];
	__sequenced_send = 0;
	__sequenced_recv_latest = -1;

	// Reliable send side
	__rel_next_id = 0;                                           // id the next reliable message gets
	__rel_oldest  = 0;                                           // oldest unacknowledged id
	__rel_window  = array_create(QNET_RELIABLE_WINDOW, undefined); // { id, buffer, size, last_sent }
	__rel_backlog = [];                                          // bodies waiting for room in the window

	// Reliable receive side
	__rel_recv_next   = 0;                                         // next id to deliver
	__rel_recv_window = array_create(QNET_RELIABLE_WINDOW, undefined); // { id, message } that arrived early

	#endregion

	#region ---- Lifecycle -----------------------------------------------------------

	static __BeginConnect = function(_now, _client_salt)
	{
		state = QNET_STATE.CONNECTING;
		__client_salt = _client_salt;
		__handshake_started = _now;
		__last_handshake_send = -1000000;
	}

	static __OnChallenge = function(_server_salt, _observed_ip, _now)
	{
		__session = (__client_salt ^ _server_salt) & 0xFFFFFFFF;
		ip = _observed_ip; // Join() may have been given a hostname; use the address that actually answered.
		state = QNET_STATE.CHALLENGED;
		__last_handshake_send = _now;
	}

	static __Accept = function(_session, _now)
	{
		__session = _session;
		state = QNET_STATE.CONNECTED;
		__last_receive_time = _now;
		__last_send_time = _now;
	}

	/// Called while CONNECTING or CHALLENGED, every update.
	static __HandshakeTick = function(_now)
	{
		if (_now - __handshake_started >= network.__connect_timeout_ms)
		{
			network.__Drop(self, QNET_REASON.CONNECT_TIMEOUT, false);
			return;
		}
		if (_now - __last_handshake_send < QNET_HANDSHAKE_RETRY_MS) return;
		__last_handshake_send = _now;

		if (state == QNET_STATE.CONNECTING) network.__SendConnectRequest(self);
		else if (state == QNET_STATE.CHALLENGED) network.__SendChallengeResponse(self);
	}

	/// Frees every buffer this connection owns. The connection is dead afterwards.
	static __Destroy = function()
	{
		state = QNET_STATE.DISCONNECTED;
		for (var _i = 0; _i < array_length(__outgoing); _i++) buffer_delete(__outgoing[_i].buffer);
		for (var _i = 0; _i < array_length(__rel_backlog); _i++) buffer_delete(__rel_backlog[_i].buffer);
		for (var _i = 0; _i < QNET_RELIABLE_WINDOW; _i++)
		{
			if (__rel_window[_i] != undefined) buffer_delete(__rel_window[_i].buffer);
		}
		__outgoing = [];
		__rel_backlog = [];
		__rel_window = array_create(QNET_RELIABLE_WINDOW, undefined);
		__rel_recv_window = array_create(QNET_RELIABLE_WINDOW, undefined);
	}

	#endregion

	#region ---- Sending -------------------------------------------------------------

	/// Takes ownership of _body ({ buffer, size }).
	static __Enqueue = function(_body, _channel)
	{
		switch (_channel)
		{
			case QNET_CHANNEL.RELIABLE:
				// Keep order: once anything is backlogged, everything after it is too.
				if (array_length(__rel_backlog) > 0 || __qnet_seq_diff(__rel_next_id, __rel_oldest) >= QNET_RELIABLE_WINDOW)
				{
					array_push(__rel_backlog, _body);
				}
				else
				{
					__AddToReliableWindow(_body);
				}
				break;

			case QNET_CHANNEL.SEQUENCED:
				array_push(__outgoing, { channel: _channel, seq: __sequenced_send, buffer: _body.buffer, size: _body.size });
				__sequenced_send = __qnet_seq_next(__sequenced_send);
				break;

			default:
				array_push(__outgoing, { channel: QNET_CHANNEL.UNRELIABLE, seq: 0, buffer: _body.buffer, size: _body.size });
				break;
		}
	}

	static __AddToReliableWindow = function(_body)
	{
		__rel_window[__rel_next_id mod QNET_RELIABLE_WINDOW] = { id: __rel_next_id, buffer: _body.buffer, size: _body.size, last_sent: -1 };
		__rel_next_id = __qnet_seq_next(__rel_next_id);
	}

	static __PumpBacklog = function()
	{
		var _moved = 0;
		while (_moved < array_length(__rel_backlog) && __qnet_seq_diff(__rel_next_id, __rel_oldest) < QNET_RELIABLE_WINDOW)
		{
			__AddToReliableWindow(__rel_backlog[_moved]);
			_moved++;
		}
		if (_moved > 0) array_delete(__rel_backlog, 0, _moved);
	}

	/// Packs everything due into as few packets as possible and sends them.
	static __Flush = function(_now)
	{
		if (state != QNET_STATE.CONNECTED) return;

		var _packet = undefined;
		var _count = 0;
		var _ids = [];
		var _resend_ms = max(QNET_MIN_RESEND_MS, rtt * 1.5);

		// 1. Reliable messages never sent, or unacknowledged for longer than the resend interval.
		var _id = __rel_oldest;
		while (_id != __rel_next_id)
		{
			var _entry = __rel_window[_id mod QNET_RELIABLE_WINDOW];
			if (_entry != undefined && (_entry.last_sent < 0 || _now - _entry.last_sent >= _resend_ms))
			{
				if (_packet != undefined && _count > 0 && buffer_tell(_packet) + 5 + _entry.size > QNET_MAX_PACKET_SIZE)
				{
					__FinishPayload(_packet, _ids, _now);
					_packet = undefined;
				}
				if (_packet == undefined)
				{
					_packet = __BeginPayload();
					_count = 0;
					_ids = [];
				}
				if (_entry.last_sent >= 0) stats.resends++;
				__WriteMessage(_packet, QNET_CHANNEL.RELIABLE, _entry.id, _entry.buffer, _entry.size);
				array_push(_ids, _entry.id);
				_entry.last_sent = _now;
				_count++;
			}
			_id = __qnet_seq_next(_id);
		}

		// 2. Unreliable and sequenced messages queued since the last flush.
		for (var _i = 0; _i < array_length(__outgoing); _i++)
		{
			var _out = __outgoing[_i];
			if (_packet != undefined && _count > 0 && buffer_tell(_packet) + 5 + _out.size > QNET_MAX_PACKET_SIZE)
			{
				__FinishPayload(_packet, _ids, _now);
				_packet = undefined;
			}
			if (_packet == undefined)
			{
				_packet = __BeginPayload();
				_count = 0;
				_ids = [];
			}
			__WriteMessage(_packet, _out.channel, _out.seq, _out.buffer, _out.size);
			buffer_delete(_out.buffer);
			_count++;
		}
		__outgoing = [];

		// 3. Nothing to say: still acknowledge what we received, and keep the connection alive.
		if (_packet == undefined)
		{
			var _idle = _now - __last_send_time;
			if ((__ack_pending && _idle >= QNET_ACK_DELAY_MS) || _idle >= network.__heartbeat_ms)
			{
				_packet = __BeginPayload();
				_ids = [];
			}
		}

		if (_packet != undefined) __FinishPayload(_packet, _ids, _now);
	}

	static __BeginPayload = function()
	{
		var _packet = network.__BeginPacket(__QNET_PACKET.PAYLOAD);
		buffer_write(_packet, buffer_u32, __session);
		buffer_write(_packet, buffer_u16, __send_seq);
		// Before anything is received, 65535 / 0 acknowledges nothing: no packet with that seq was sent yet.
		buffer_write(_packet, buffer_u16, (__recv_latest < 0) ? 65535 : __recv_latest);
		buffer_write(_packet, buffer_u32, (__recv_latest < 0) ? 0 : __AckBits());
		return _packet;
	}

	static __AckBits = function()
	{
		var _bits = 0;
		for (var _i = 1; _i <= 32; _i++)
		{
			var _seq = (__recv_latest - _i + 65536) mod 65536;
			if (__recv_seqs[_seq mod QNET_SEQUENCE_RING] == _seq) _bits = _bits | (1 << (_i - 1));
		}
		return _bits;
	}

	static __WriteMessage = function(_packet, _channel, _seq, _body_buffer, _size)
	{
		buffer_write(_packet, buffer_u8, _channel);
		if (_channel != QNET_CHANNEL.UNRELIABLE) buffer_write(_packet, buffer_u16, _seq);
		buffer_write(_packet, buffer_u16, _size);
		var _position = buffer_tell(_packet);
		if (_position + _size > buffer_get_size(_packet)) buffer_resize(_packet, _position + _size + 256);
		buffer_copy(_body_buffer, 0, _size, _packet, _position);
		buffer_seek(_packet, buffer_seek_start, _position + _size);
	}

	static __FinishPayload = function(_packet, _reliable_ids, _now)
	{
		var _size = buffer_tell(_packet);

		// A packet 64 sends ago that is still unacknowledged has fallen out of every possible ack mask.
		var _old_seq = (__send_seq - 64 + 65536) mod 65536;
		var _old_slot = _old_seq mod QNET_SEQUENCE_RING;
		if (__sent_seq[_old_slot] == _old_seq && !__sent_acked[_old_slot])
		{
			__sent_acked[_old_slot] = true;
			__sent_reliable[_old_slot] = undefined;
			stats.packets_lost++;
			packet_loss = lerp(packet_loss, 1, 0.05);
		}

		var _slot = __send_seq mod QNET_SEQUENCE_RING;
		__sent_seq[_slot]      = __send_seq;
		__sent_time[_slot]     = _now;
		__sent_acked[_slot]    = false;
		__sent_reliable[_slot] = (array_length(_reliable_ids) > 0) ? _reliable_ids : undefined;
		__send_seq = __qnet_seq_next(__send_seq);

		__last_send_time = _now;
		__ack_pending = false;
		stats.packets_sent++;
		stats.bytes_sent += _size;

		network.__SendRaw(ip, port, _packet, _size, false);
		if (__QLOG_LEVEL >= QLOG_LEVEL.DEEP_DEBUG) q_log($"[SEND] to #{id} seq {__sent_seq[_slot]} {_size} bytes", QLOG_LEVEL.DEEP_DEBUG);
	}

	#endregion

	#region ---- Receiving -----------------------------------------------------------

	/// _buffer is positioned right after the session field.
	static __ReceivePayload = function(_buffer, _size, _now)
	{
		var _seq      = buffer_read(_buffer, buffer_u16);
		var _ack      = buffer_read(_buffer, buffer_u16);
		var _ack_bits = buffer_read(_buffer, buffer_u32);

		// Drop duplicates, and packets too old for the history ring to judge.
		var _slot = _seq mod QNET_SEQUENCE_RING;
		if (__recv_seqs[_slot] == _seq) return;
		if (__recv_latest >= 0 && __qnet_seq_greater(__recv_latest, _seq) && __qnet_seq_diff(__recv_latest, _seq) >= QNET_SEQUENCE_RING) return;

		__recv_seqs[_slot] = _seq;
		if (__recv_latest < 0 || __qnet_seq_greater(_seq, __recv_latest)) __recv_latest = _seq;
		__ack_pending = true;
		__last_receive_time = _now;
		stats.packets_received++;
		stats.bytes_received += _size;

		// What the peer says it received from us.
		__ProcessAck(_ack, _now);
		for (var _i = 1; _i <= 32; _i++)
		{
			if ((_ack_bits & (1 << (_i - 1))) != 0) __ProcessAck((_ack - _i + 65536) mod 65536, _now);
		}

		// Messages
		while (buffer_tell(_buffer) < _size)
		{
			if (state != QNET_STATE.CONNECTED) return; // a handler disconnected us

			var _remaining = _size - buffer_tell(_buffer);
			if (_remaining < 3) return;
			var _channel = buffer_read(_buffer, buffer_u8);
			var _channel_seq = 0;
			if (_channel == QNET_CHANNEL.SEQUENCED || _channel == QNET_CHANNEL.RELIABLE)
			{
				if (_remaining < 5) return;
				_channel_seq = buffer_read(_buffer, buffer_u16);
			}
			else if (_channel != QNET_CHANNEL.UNRELIABLE)
			{
				return; // malformed
			}
			var _length = buffer_read(_buffer, buffer_u16);
			var _start = buffer_tell(_buffer);
			if (_start + _length > _size) return; // malformed

			switch (_channel)
			{
				case QNET_CHANNEL.UNRELIABLE:
					__DeliverNow(_buffer, _start, _length);
					break;

				case QNET_CHANNEL.SEQUENCED:
					if (__sequenced_recv_latest < 0 || __qnet_seq_greater(_channel_seq, __sequenced_recv_latest))
					{
						__sequenced_recv_latest = _channel_seq;
						__DeliverNow(_buffer, _start, _length);
					}
					break;

				case QNET_CHANNEL.RELIABLE:
					__ReceiveReliable(_buffer, _start, _length, _channel_seq);
					break;
			}
			buffer_seek(_buffer, buffer_seek_start, _start + _length);
		}
	}

	static __DeliverNow = function(_buffer, _start, _length)
	{
		var _message = network.__DecodeMessage(_buffer, _start, _length);
		if (_message != undefined) network.__Dispatch(_message, self);
	}

	static __ReceiveReliable = function(_buffer, _start, _length, _message_id)
	{
		// Distance >= window: either already delivered (a resend whose ack was lost) or impossibly far ahead.
		if (__qnet_seq_diff(_message_id, __rel_recv_next) < QNET_RELIABLE_WINDOW)
		{
			var _slot = _message_id mod QNET_RELIABLE_WINDOW;
			if (__rel_recv_window[_slot] == undefined)
			{
				// Decoded now because GameMaker frees the async buffer after the event. A message that
				// cannot be decoded is stored as undefined so it does not block the ones behind it.
				__rel_recv_window[_slot] = { id: _message_id, message: network.__DecodeMessage(_buffer, _start, _length) };
			}
		}

		// Release everything that is now in order.
		while (true)
		{
			var _next_slot = __rel_recv_next mod QNET_RELIABLE_WINDOW;
			var _entry = __rel_recv_window[_next_slot];
			if (_entry == undefined || _entry.id != __rel_recv_next) break;
			__rel_recv_window[_next_slot] = undefined;
			__rel_recv_next = __qnet_seq_next(__rel_recv_next);
			if (_entry.message != undefined) network.__Dispatch(_entry.message, self);
			if (state != QNET_STATE.CONNECTED) return;
		}
	}

	static __ProcessAck = function(_seq, _now)
	{
		var _slot = _seq mod QNET_SEQUENCE_RING;
		if (__sent_seq[_slot] != _seq || __sent_acked[_slot]) return;
		__sent_acked[_slot] = true;

		var _sample = _now - __sent_time[_slot];
		rtt = __rtt_sampled ? lerp(rtt, _sample, 0.1) : _sample;
		__rtt_sampled = true;
		packet_loss = lerp(packet_loss, 0, 0.05);

		// Every reliable message that rode in this packet is delivered.
		var _ids = __sent_reliable[_slot];
		__sent_reliable[_slot] = undefined;
		if (_ids == undefined) return;

		for (var _i = 0; _i < array_length(_ids); _i++)
		{
			var _window_slot = _ids[_i] mod QNET_RELIABLE_WINDOW;
			var _entry = __rel_window[_window_slot];
			if (_entry != undefined && _entry.id == _ids[_i])
			{
				buffer_delete(_entry.buffer);
				__rel_window[_window_slot] = undefined;
			}
		}
		while (__rel_oldest != __rel_next_id && __rel_window[__rel_oldest mod QNET_RELIABLE_WINDOW] == undefined)
		{
			__rel_oldest = __qnet_seq_next(__rel_oldest);
		}
		__PumpBacklog();
	}

	#endregion
}

/// Errors on anything that is not a QNET_CHANNEL value.
function __qnet_check_channel(_channel)
{
	if (_channel != QNET_CHANNEL.UNRELIABLE && _channel != QNET_CHANNEL.SEQUENCED && _channel != QNET_CHANNEL.RELIABLE)
	{
		q_error($"{_channel} is not a QNET_CHANNEL.", "Use QNET_CHANNEL.RELIABLE, QNET_CHANNEL.SEQUENCED or QNET_CHANNEL.UNRELIABLE.",
		        "connection.Send(new PlayerMove(x, y), QNET_CHANNEL.SEQUENCED);");
	}
}
