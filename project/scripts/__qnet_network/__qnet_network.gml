/*******************************************************************************
*   ____  _   _ ______ _______
*  / __ \| \ | |  ____|__   __|
* | |  | |  \| | |__     | |
* | |  | | . ` |  __|    | |
* | |__| | |\  | |____   | |
*  \___\_\_| \_|______|  |_|
*
*  QNetwork: UDP networking for GameMaker with reliable, sequenced and unreliable messages.
*
*  SETUP (one object, three events)
*
*    Create:
*        network = new QNetwork({ messages: [PlayerMove, ChatMessage] });
*        network.OnConnected    = function(_connection) { ... };
*        network.OnDisconnected = function(_connection, _reason) { ... };
*        network.On(ChatMessage, function(_message, _from) { ... });
*        network.Host(3000);                 // or: network.Join("127.0.0.1", 3000);
*
*    Async - Networking:
*        network.AsyncNetworking();
*
*    Clean Up:
*        network.Destroy();
*
*  SENDING
*        connection.Send(new ChatMessage("hi"));                          // reliable + ordered by default
*        network.SendToAll(new PlayerMove(x, y), QNET_CHANNEL.SEQUENCED);  // on a client, "all" is the host
*
*  GUARANTEES
*    - Every successful Join() ends in exactly one OnConnected or OnConnectFailed.
*    - Every OnConnected is followed by exactly one OnDisconnected, including on Shutdown().
*    - Messages from one peer are delivered in the order of the guarantees of their channel;
*      RELIABLE messages arrive exactly once, in send order.
*******************************************************************************/

/// feather ignore all

/// @param {Struct} _config
///   messages        {Array<Function>}  Required. Message constructors. Every peer must use the same list, in the same order.
///   max_clients     {Real}  Host only. Clients allowed at once. Default 8.
///   timeout         {Real}  Seconds of silence before a connection is dropped. Default 5.
///   connect_timeout {Real}  Seconds Join() keeps trying before giving up. Default 5.
///   heartbeat       {Real}  Seconds between keep-alive packets when there is nothing else to send. Default 0.5.
function QNetwork(_config) constructor
{
	#region ---- Public, read-only --------------------------------------------------

	/// @type {Enum.QNET_ROLE}
	role = QNET_ROLE.OFFLINE;
	/// Our id on the network: 0 when hosting, assigned by the host once a Join() succeeds, -1 otherwise.
	local_id = -1;
	/// The local UDP port in use, or -1.
	port = -1;

	#endregion

	#region ---- Callbacks: assign your own --------------------------------------------

	/// A peer is connected and messages can flow. On a host: a client joined. On a client: the host accepted us.
	/// @param {Struct.QNetConnection} _connection
	static OnConnected = function(_connection)
	{
		q_log($"Connected: {_connection}");
	}

	/// A connected peer is gone. _connection can no longer send.
	/// @param {Struct.QNetConnection} _connection
	/// @param {Enum.QNET_REASON} _reason
	static OnDisconnected = function(_connection, _reason)
	{
		q_log($"Disconnected: #{_connection.id} ({qnet_reason_to_string(_reason)})");
	}

	/// Client only. A Join() did not succeed.
	/// @param {Enum.QNET_REASON} _reason SERVER_FULL, SCHEMA_MISMATCH, CONNECT_TIMEOUT or LOCAL.
	static OnConnectFailed = function(_reason)
	{
		q_log($"Join failed: {qnet_reason_to_string(_reason)}");
	}

	#endregion

	#region ---- Starting and stopping ------------------------------------------------

	/// Start hosting: open _port and accept clients.
	/// @param {Real} _port
	/// @returns {Bool} false if already online or the port could not be opened.
	static Host = function(_port)
	{
		if (role != QNET_ROLE.OFFLINE)
		{
			q_warn("Host() ignored: this QNetwork is already online. Call Shutdown() first.");
			return false;
		}
		var _socket = network_create_socket_ext(network_socket_udp, _port);
		if (_socket < 0)
		{
			q_warn($"Host() could not open UDP port {_port}. Another program (or another copy of the game) may be using it.");
			return false;
		}
		__socket = _socket;
		port = _port;
		role = QNET_ROLE.HOST;
		local_id = 0;
		__connections = array_create(__max_clients + 1, undefined); // slot 0 is the host itself
		__address_lookup = {};
		__pending = {};
		__pending_count = 0;
		__rng.Mix(_port);
		q_log($"Hosting on port {_port} for up to {__max_clients} clients.");
		return true;
	}

	/// Join a host. The result arrives later through OnConnected or OnConnectFailed.
	/// @param {String} _ip Host address. "localhost" works.
	/// @param {Real} _port Host port.
	/// @param {Real} [_local_port] Local port to use. By default a free one is picked.
	/// @returns {Bool} false if already online or no local port could be opened (no callback fires).
	static Join = function(_ip, _port, _local_port = undefined)
	{
		if (role != QNET_ROLE.OFFLINE)
		{
			q_warn("Join() ignored: this QNetwork is already online. Call Shutdown() first.");
			return false;
		}
		var _socket = -1;
		var _bound_port = -1;
		if (_local_port != undefined)
		{
			_socket = network_create_socket_ext(network_socket_udp, _local_port);
			_bound_port = _local_port;
		}
		else
		{
			// Try ports in the dynamic range, starting somewhere random so several clients on one machine spread out.
			var _start = 49152 + (__rng.NextU32() mod 16000);
			for (var _i = 0; _i < 64 && _socket < 0; _i++)
			{
				_bound_port = _start + _i;
				_socket = network_create_socket_ext(network_socket_udp, _bound_port);
			}
		}
		if (_socket < 0)
		{
			q_warn("Join() could not open a local UDP port.");
			return false;
		}
		if (_ip == "localhost") _ip = "127.0.0.1";

		__socket = _socket;
		port = _bound_port;
		role = QNET_ROLE.CLIENT;
		local_id = -1;
		__rng.Mix(_bound_port);

		var _connection = new QNetConnection(self, 0, _ip, _port);
		__connections = [_connection];
		_connection.__BeginConnect(current_time, __rng.NextU32());
		q_log($"Joining {_ip}:{_port} from local port {_bound_port}.");
		return true;
	}

	/// Disconnect everyone and close the socket. Callbacks fire for every open connection.
	/// Host() or Join() can be called again afterwards, including from inside those callbacks.
	static Shutdown = function()
	{
		if (role == QNET_ROLE.OFFLINE) return;
		var _was_client = (role == QNET_ROLE.CLIENT);

		// Tear everything down first, then tell the game, so callbacks see a clean OFFLINE network.
		var _closed = [];
		for (var _i = 0; _i < array_length(__connections); _i++)
		{
			var _connection = __connections[_i];
			if (_connection == undefined) continue;
			var _was_connected = (_connection.state == QNET_STATE.CONNECTED);
			if (_was_connected) __SendDisconnect(_connection);
			_connection.__Destroy();
			array_push(_closed, { connection: _connection, was_connected: _was_connected });
		}
		__CloseSocket();
		q_log("Network shut down.");

		for (var _i = 0; _i < array_length(_closed); _i++)
		{
			__FireClosed(_closed[_i].connection, _closed[_i].was_connected, _was_client, QNET_REASON.LOCAL);
		}
	}

	/// Shutdown() and free everything. Call this in the owning object's Clean Up event.
	/// The QNetwork cannot be used afterwards.
	static Destroy = function()
	{
		Shutdown();
		if (__time_source != undefined)
		{
			time_source_stop(__time_source);
			time_source_destroy(__time_source);
			__time_source = undefined;
		}
		if (__packet != undefined)  { buffer_delete(__packet);  __packet = undefined; }
		if (__scratch != undefined) { buffer_delete(__scratch); __scratch = undefined; }
	}

	#endregion

	#region ---- Messages ---------------------------------------------------------------

	/// Handle every received message of one type. Replaces any earlier handler for that type,
	/// and takes priority over an OnReceive method declared on the message.
	/// @param {Function} _message_type A registered constructor, e.g. ChatMessage.
	/// @param {Function} _handler function(_message, _from_connection)
	static On = function(_message_type, _handler)
	{
		if (!__serializer.IsRegistered(_message_type))
		{
			q_error($"On() was given {_message_type}, which is not a registered message type.",
			        "Add it to the messages array when creating the QNetwork.",
			        "network.On(ChatMessage, function(_message, _from) { ... });");
		}
		if (!is_callable(_handler))
		{
			q_error("On() needs a function as its second argument.", "The handler receives the message and the connection it came from.",
			        "network.On(ChatMessage, function(_message, _from) { show_debug_message(_message.text); });");
		}
		__handlers[$ __qnet_function_name(_message_type)] = _handler;
	}

	/// Remove the handler for a message type.
	static Off = function(_message_type)
	{
		var _name = __qnet_function_name(_message_type);
		if (_name != undefined) variable_struct_remove(__handlers, _name);
	}

	/// Send a message to every connected peer. On a client that is just the host.
	/// @param {Struct} _message
	/// @param {Enum.QNET_CHANNEL} [_channel] Defaults to QNET_CHANNEL.RELIABLE.
	/// @param {Struct.QNetConnection} [_except] Skip this connection, e.g. when relaying what it sent.
	/// @returns {Real} How many peers it was queued for.
	static SendToAll = function(_message, _channel = QNET_CHANNEL.RELIABLE, _except = undefined)
	{
		__qnet_check_channel(_channel);
		if (role == QNET_ROLE.OFFLINE) return 0;
		var _body = __EncodeMessage(_message);
		var _count = 0;
		for (var _i = 0; _i < array_length(__connections); _i++)
		{
			var _connection = __connections[_i];
			if (_connection == undefined || _connection == _except || _connection.state != QNET_STATE.CONNECTED) continue;
			_connection.__Enqueue(__qnet_body_clone(_body), _channel);
			_count++;
		}
		buffer_delete(_body.buffer);
		return _count;
	}

	/// Send everything queued right now instead of on QNet's next update (the start of next frame).
	/// Optional: call it at the end of End Step to save up to a frame of latency.
	static Flush = function()
	{
		if (role == QNET_ROLE.OFFLINE) return;
		var _now = current_time;
		for (var _i = 0; _i < array_length(__connections); _i++)
		{
			var _connection = __connections[_i];
			if (_connection != undefined) _connection.__Flush(_now);
		}
	}

	#endregion

	#region ---- Queries ----------------------------------------------------------------

	static IsHost   = function() { return role == QNET_ROLE.HOST; }
	static IsClient = function() { return role == QNET_ROLE.CLIENT; }
	static IsOnline = function() { return role != QNET_ROLE.OFFLINE; }

	/// The connection to the peer with this id, or undefined. On a client, the host is id 0.
	/// @returns {Struct.QNetConnection,Undefined}
	static GetConnection = function(_id)
	{
		if (_id < 0 || _id >= array_length(__connections)) return undefined;
		return __connections[_id];
	}

	/// Every connected peer, as a new array.
	/// @returns {Array<Struct.QNetConnection>}
	static GetConnections = function()
	{
		var _result = [];
		for (var _i = 0; _i < array_length(__connections); _i++)
		{
			var _connection = __connections[_i];
			if (_connection != undefined && _connection.state == QNET_STATE.CONNECTED) array_push(_result, _connection);
		}
		return _result;
	}

	/// How many peers are connected.
	static ConnectionCount = function()
	{
		return array_length(GetConnections());
	}

	/// Simulate a bad network on packets this peer sends, to test your game (and QNet) on localhost.
	/// Packets can be delayed, reordered by jitter, and dropped. Call with no arguments to turn it off.
	/// @param {Real} [_latency_ms] Added one-way delay.
	/// @param {Real} [_jitter_ms] Random +/- variation on that delay.
	/// @param {Real} [_loss] Chance (0..1) that a packet is dropped.
	static Simulate = function(_latency_ms = 0, _jitter_ms = 0, _loss = 0)
	{
		__sim_latency = max(0, _latency_ms);
		__sim_jitter  = max(0, _jitter_ms);
		__sim_loss    = clamp(_loss, 0, 1);
		__sim_enabled = (__sim_latency > 0 || __sim_jitter > 0 || __sim_loss > 0);
	}

	static toString = function()
	{
		static _role_names = ["OFFLINE", "HOST", "CLIENT"];
		var _text = $"QNetwork {_role_names[role]} port {port} local id {local_id}";
		if (__sim_enabled) _text += $"  [simulating {__sim_latency}ms +/-{__sim_jitter}ms, {round(__sim_loss * 100)}% loss]";
		for (var _i = 0; _i < array_length(__connections); _i++)
		{
			if (__connections[_i] != undefined) _text += $"\n  {__connections[_i]}";
		}
		return _text;
	}

	/// Process received packets. Call this from the Async - Networking event.
	static AsyncNetworking = function()
	{
		if (__socket == undefined) return;
		if (async_load[? "id"] != __socket) return;            // another socket's event
		if (async_load[? "type"] != network_type_data) return;

		var _buffer = async_load[? "buffer"];
		var _size   = async_load[? "size"];
		var _ip     = async_load[? "ip"];
		var _port   = async_load[? "port"];
		if (_size < 3) return;

		buffer_seek(_buffer, buffer_seek_start, 0);
		if (buffer_read(_buffer, buffer_u16) != QNET_PROTOCOL_ID) return;
		var _type = buffer_read(_buffer, buffer_u8);
		var _now = current_time;

		if (role == QNET_ROLE.HOST) __HostReceive(_type, _buffer, _size, _ip, _port, _now);
		else if (role == QNET_ROLE.CLIENT) __ClientReceive(_type, _buffer, _size, _ip, _port, _now);
	}

	#endregion

	#region ---- Internal: receiving -----------------------------------------------------

	static __HostReceive = function(_type, _buffer, _size, _ip, _port, _now)
	{
		var _key = $"{_ip}:{_port}";
		var _connection = __address_lookup[$ _key];
		var _pending, _session, _client_salt;

		switch (_type)
		{
			case __QNET_PACKET.CONNECT_REQUEST:
				// u32 schema hash, u32 client salt
				if (_size < 11 || _connection != undefined) return;
				var _schema = buffer_read(_buffer, buffer_u32);
				_client_salt = buffer_read(_buffer, buffer_u32);
				if (_schema != __serializer.schema_hash)
				{
					__SendDenied(_ip, _port, _client_salt, QNET_REASON.SCHEMA_MISMATCH);
					return;
				}
				if (__FreeSlot() < 0)
				{
					__SendDenied(_ip, _port, _client_salt, QNET_REASON.SERVER_FULL);
					return;
				}
				_pending = __pending[$ _key];
				if (_pending == undefined || _pending.client_salt != _client_salt)
				{
					if (_pending == undefined)
					{
						if (__pending_count >= QNET_MAX_PENDING) return;
						__pending_count++;
					}
					_pending = { client_salt: _client_salt, server_salt: __rng.NextU32(), time: _now };
					__pending[$ _key] = _pending;
				}
				_pending.time = _now;
				__SendChallenge(_ip, _port, _pending.client_salt, _pending.server_salt);
				return;

			case __QNET_PACKET.CHALLENGE_RESPONSE:
				// u32 session
				if (_size < 7) return;
				_session = buffer_read(_buffer, buffer_u32);
				if (_connection != undefined)
				{
					// Our ACCEPTED was lost; send it again.
					if (_connection.__session == _session)
					{
						_connection.__last_receive_time = _now;
						__SendAccepted(_connection);
					}
					return;
				}
				_pending = __pending[$ _key];
				if (_pending == undefined || ((_pending.client_salt ^ _pending.server_salt) & 0xFFFFFFFF) != _session) return;
				variable_struct_remove(__pending, _key);
				__pending_count--;

				var _slot = __FreeSlot();
				if (_slot < 0)
				{
					__SendDenied(_ip, _port, _pending.client_salt, QNET_REASON.SERVER_FULL);
					return;
				}
				var _new_connection = new QNetConnection(self, _slot, _ip, _port);
				_new_connection.__Accept(_session, _now);
				__connections[_slot] = _new_connection;
				__address_lookup[$ _key] = _new_connection;
				__SendAccepted(_new_connection);
				q_log($"Client #{_slot} joined from {_key}", QLOG_LEVEL.DEBUG);
				OnConnected(_new_connection);
				return;

			case __QNET_PACKET.PAYLOAD:
				if (_connection == undefined || _size < 15) return;
				if (buffer_read(_buffer, buffer_u32) != _connection.__session) return;
				_connection.__ReceivePayload(_buffer, _size, _now);
				return;

			case __QNET_PACKET.DISCONNECT:
				if (_connection == undefined || _size < 7) return;
				if (buffer_read(_buffer, buffer_u32) != _connection.__session) return;
				__Drop(_connection, QNET_REASON.REMOTE, false);
				return;
		}
	}

	static __ClientReceive = function(_type, _buffer, _size, _ip, _port, _now)
	{
		if (array_length(__connections) == 0) return;
		var _connection = __connections[0];
		// The address is not compared because Join() may have used a hostname; salts and the session
		// do the authenticating. The port must still be the host's.
		if (_connection == undefined || _port != _connection.port) return;

		switch (_type)
		{
			case __QNET_PACKET.CHALLENGE:
				// u32 client salt, u32 server salt
				if (_size < 11 || _connection.state != QNET_STATE.CONNECTING) return;
				var _client_salt = buffer_read(_buffer, buffer_u32);
				var _server_salt = buffer_read(_buffer, buffer_u32);
				if (_client_salt != _connection.__client_salt) return;
				_connection.__OnChallenge(_server_salt, _ip, _now);
				__SendChallengeResponse(_connection);
				return;

			case __QNET_PACKET.ACCEPTED:
				// u32 session, u16 assigned id
				if (_size < 9 || _connection.state != QNET_STATE.CHALLENGED) return;
				var _session = buffer_read(_buffer, buffer_u32);
				var _assigned_id = buffer_read(_buffer, buffer_u16);
				if (_session != _connection.__session) return;
				_connection.__Accept(_session, _now);
				local_id = _assigned_id;
				q_log($"Joined as client #{_assigned_id}", QLOG_LEVEL.DEBUG);
				OnConnected(_connection);
				return;

			case __QNET_PACKET.DENIED:
				// u32 client salt, u8 reason
				if (_size < 8) return;
				if (_connection.state != QNET_STATE.CONNECTING && _connection.state != QNET_STATE.CHALLENGED) return;
				var _salt = buffer_read(_buffer, buffer_u32);
				var _reason = buffer_read(_buffer, buffer_u8);
				if (_salt != _connection.__client_salt) return;
				if (_reason != QNET_REASON.SERVER_FULL && _reason != QNET_REASON.SCHEMA_MISMATCH) _reason = QNET_REASON.NONE;
				__Drop(_connection, _reason, false);
				return;

			case __QNET_PACKET.PAYLOAD:
				if (_size < 15 || _connection.state != QNET_STATE.CONNECTED) return;
				if (buffer_read(_buffer, buffer_u32) != _connection.__session) return;
				_connection.__ReceivePayload(_buffer, _size, _now);
				return;

			case __QNET_PACKET.DISCONNECT:
				if (_size < 7 || _connection.state != QNET_STATE.CONNECTED) return;
				if (buffer_read(_buffer, buffer_u32) != _connection.__session) return;
				__Drop(_connection, QNET_REASON.REMOTE, false);
				return;
		}
	}

	/// Decodes one message body. Returns undefined (and logs) if it cannot be decoded.
	static __DecodeMessage = function(_buffer, _start, _length)
	{
		buffer_seek(_buffer, buffer_seek_start, _start);
		var _message = undefined;
		try
		{
			_message = __serializer.Read(_buffer);
		}
		catch (_exception)
		{
			q_error_quiet($"Dropped a message that could not be decoded: {_exception}");
			return undefined;
		}
		if (_message == undefined || buffer_tell(_buffer) != _start + _length)
		{
			__qnet_warn_once("decode-size", "Dropped a message whose size did not match its type. A MANUAL_SERIALIZATION Read() may not match its Write().");
			return undefined;
		}
		return _message;
	}

	static __Dispatch = function(_message, _connection)
	{
		var _name = instanceof(_message);
		var _handler = __handlers[$ _name];
		if (_handler != undefined)
		{
			_handler(_message, _connection);
			return;
		}
		var _type = __serializer.__types_by_name[$ _name];
		if (_type.has_on_receive)
		{
			_message.OnReceive(_connection);
			return;
		}
		__qnet_warn_once($"unhandled-{_name}", $"Received {_name} but nothing handles it. Use network.On({_name}, handler) or give it an OnReceive(_from) method.");
	}

	#endregion

	#region ---- Internal: sending -------------------------------------------------------

	/// Encodes a message into an exact-size body buffer: { buffer, size }.
	static __EncodeMessage = function(_message)
	{
		buffer_seek(__scratch, buffer_seek_start, 0);
		__serializer.Write(__scratch, _message);
		var _size = buffer_tell(__scratch);
		if (_size > 65535)
		{
			q_error($"{instanceof(_message)} is {_size} bytes. Messages are limited to 65535 bytes.", "Split large data across several messages.", "");
		}
		if (_size + 20 > QNET_MAX_PACKET_SIZE)
		{
			__qnet_warn_once($"large-{instanceof(_message)}", $"{instanceof(_message)} is {_size} bytes, more than fits in one {QNET_MAX_PACKET_SIZE} byte packet. It will be sent alone and is more likely to be lost.");
		}
		var _body = buffer_create(_size, buffer_fixed, 1);
		buffer_copy(__scratch, 0, _size, _body, 0);
		return { buffer: _body, size: _size };
	}

	/// Starts a packet in the shared packet buffer: u16 protocol id, u8 type.
	static __BeginPacket = function(_type)
	{
		buffer_seek(__packet, buffer_seek_start, 0);
		buffer_write(__packet, buffer_u16, QNET_PROTOCOL_ID);
		buffer_write(__packet, buffer_u8, _type);
		return __packet;
	}

	static __SendRaw = function(_ip, _port, _buffer, _size, _bypass_simulator)
	{
		if (__socket == undefined) return;
		if (__sim_enabled && !_bypass_simulator)
		{
			if (__rng.NextFloat() < __sim_loss) return;
			var _delay = max(0, __sim_latency + (__rng.NextFloat() * 2 - 1) * __sim_jitter);
			var _copy = buffer_create(_size, buffer_fixed, 1);
			buffer_copy(_buffer, 0, _size, _copy, 0);
			array_push(__sim_queue, { time: current_time + _delay, ip: _ip, port: _port, buffer: _copy, size: _size });
			return;
		}
		network_send_udp(__socket, _ip, _port, _buffer, _size);
	}

	static __PumpSimulator = function(_now)
	{
		if (array_length(__sim_queue) == 0) return;
		var _waiting = [];
		for (var _i = 0; _i < array_length(__sim_queue); _i++)
		{
			var _item = __sim_queue[_i];
			if (_item.time <= _now)
			{
				network_send_udp(__socket, _item.ip, _item.port, _item.buffer, _item.size);
				buffer_delete(_item.buffer);
			}
			else
			{
				array_push(_waiting, _item);
			}
		}
		__sim_queue = _waiting;
	}

	static __SendConnectRequest = function(_connection)
	{
		var _packet = __BeginPacket(__QNET_PACKET.CONNECT_REQUEST);
		buffer_write(_packet, buffer_u32, __serializer.schema_hash);
		buffer_write(_packet, buffer_u32, _connection.__client_salt);
		__SendRaw(_connection.ip, _connection.port, _packet, buffer_tell(_packet), false);
	}

	static __SendChallenge = function(_ip, _port, _client_salt, _server_salt)
	{
		var _packet = __BeginPacket(__QNET_PACKET.CHALLENGE);
		buffer_write(_packet, buffer_u32, _client_salt);
		buffer_write(_packet, buffer_u32, _server_salt);
		__SendRaw(_ip, _port, _packet, buffer_tell(_packet), false);
	}

	static __SendChallengeResponse = function(_connection)
	{
		var _packet = __BeginPacket(__QNET_PACKET.CHALLENGE_RESPONSE);
		buffer_write(_packet, buffer_u32, _connection.__session);
		__SendRaw(_connection.ip, _connection.port, _packet, buffer_tell(_packet), false);
	}

	static __SendAccepted = function(_connection)
	{
		var _packet = __BeginPacket(__QNET_PACKET.ACCEPTED);
		buffer_write(_packet, buffer_u32, _connection.__session);
		buffer_write(_packet, buffer_u16, _connection.id);
		__SendRaw(_connection.ip, _connection.port, _packet, buffer_tell(_packet), false);
	}

	static __SendDenied = function(_ip, _port, _client_salt, _reason)
	{
		var _packet = __BeginPacket(__QNET_PACKET.DENIED);
		buffer_write(_packet, buffer_u32, _client_salt);
		buffer_write(_packet, buffer_u8, _reason);
		__SendRaw(_ip, _port, _packet, buffer_tell(_packet), false);
	}

	/// Sent three times, skipping the simulator, because the socket may close right after.
	static __SendDisconnect = function(_connection)
	{
		var _packet = __BeginPacket(__QNET_PACKET.DISCONNECT);
		buffer_write(_packet, buffer_u32, _connection.__session);
		var _size = buffer_tell(_packet);
		repeat (3) __SendRaw(_connection.ip, _connection.port, _packet, _size, true);
	}

	#endregion

	#region ---- Internal: connection bookkeeping ----------------------------------------

	static __FreeSlot = function()
	{
		for (var _i = 1; _i < array_length(__connections); _i++)
		{
			if (__connections[_i] == undefined) return _i;
		}
		return -1;
	}

	/// Ends one connection. A client's only connection is the host, so a client goes OFFLINE.
	static __Drop = function(_connection, _reason, _notify_peer)
	{
		if (_connection.state == QNET_STATE.DISCONNECTED) return;
		var _was_connected = (_connection.state == QNET_STATE.CONNECTED);
		var _was_client = (role == QNET_ROLE.CLIENT);

		if (_notify_peer && _was_connected) __SendDisconnect(_connection);
		_connection.__Destroy();

		if (_was_client)
		{
			__CloseSocket();
		}
		else
		{
			if (_connection.id < array_length(__connections) && __connections[_connection.id] == _connection) __connections[_connection.id] = undefined;
			variable_struct_remove(__address_lookup, $"{_connection.ip}:{_connection.port}");
		}

		__FireClosed(_connection, _was_connected, _was_client, _reason);
	}

	static __FireClosed = function(_connection, _was_connected, _was_client, _reason)
	{
		if (_was_connected) OnDisconnected(_connection, _reason);
		else if (_was_client) OnConnectFailed(_reason);
	}

	static __CloseSocket = function()
	{
		if (__socket != undefined) network_destroy(__socket);
		__socket = undefined;
		role = QNET_ROLE.OFFLINE;
		local_id = -1;
		port = -1;
		__connections = [];
		__address_lookup = {};
		__pending = {};
		__pending_count = 0;
		for (var _i = 0; _i < array_length(__sim_queue); _i++) buffer_delete(__sim_queue[_i].buffer);
		__sim_queue = [];
	}

	/// Runs once per frame from a time source.
	static __Tick = function()
	{
		if (role == QNET_ROLE.OFFLINE) return;
		var _now = current_time;
		__PumpSimulator(_now);

		for (var _i = 0; _i < array_length(__connections); _i++)
		{
			var _connection = __connections[_i];
			if (_connection == undefined) continue;

			if (_connection.state == QNET_STATE.CONNECTED)
			{
				if (_now - _connection.__last_receive_time > __timeout_ms)
				{
					__Drop(_connection, QNET_REASON.TIMEOUT, false);
					continue;
				}
				_connection.__Flush(_now);
			}
			else
			{
				_connection.__HandshakeTick(_now);
			}
		}

		if (role == QNET_ROLE.HOST && _now - __last_pending_sweep >= 1000)
		{
			__last_pending_sweep = _now;
			var _keys = variable_struct_get_names(__pending);
			for (var _k = 0; _k < array_length(_keys); _k++)
			{
				if (_now - __pending[$ _keys[_k]].time > __connect_timeout_ms)
				{
					variable_struct_remove(__pending, _keys[_k]);
					__pending_count--;
				}
			}
		}
	}

	#endregion

	#region ---- Construction --------------------------------------------------------------

	if (!is_struct(_config) || !is_array(_config[$ "messages"]))
	{
		q_error("QNetwork needs a config struct with a messages array.",
		        ["List every message constructor your game sends.", "Every peer must use the same list in the same order."],
		        "network = new QNetwork({ messages: [PlayerMove, ChatMessage] });");
	}

	static __KNOWN_OPTIONS = ["messages", "max_clients", "timeout", "connect_timeout", "heartbeat"];
	var _given = variable_struct_get_names(_config);
	for (var _i = 0; _i < array_length(_given); _i++)
	{
		var _known = false;
		for (var _j = 0; _j < array_length(__KNOWN_OPTIONS); _j++)
		{
			if (_given[_i] == __KNOWN_OPTIONS[_j]) { _known = true; break; }
		}
		if (!_known) q_warn($"QNetwork option '{_given[_i]}' is not recognised and will be ignored. Options: {__KNOWN_OPTIONS}");
	}

	__serializer         = new QSerializer(_config.messages);
	__max_clients        = max(1, floor(__qnet_option(_config, "max_clients", 8)));
	__timeout_ms         = (__qnet_option(_config, "timeout", 5)) * 1000;
	__connect_timeout_ms = (__qnet_option(_config, "connect_timeout", 5)) * 1000;
	__heartbeat_ms       = (__qnet_option(_config, "heartbeat", 0.5)) * 1000;

	__socket          = undefined;
	__connections     = [];
	__address_lookup  = {};
	__pending         = {};
	__pending_count   = 0;
	__last_pending_sweep = 0;
	__handlers        = {};
	__rng             = new __QNetRandom();
	__packet          = buffer_create(QNET_MAX_PACKET_SIZE, buffer_grow, 1);
	__scratch         = buffer_create(256, buffer_grow, 1);

	__sim_enabled = false;
	__sim_latency = 0;
	__sim_jitter  = 0;
	__sim_loss    = 0;
	__sim_queue   = [];

	// QNet updates itself once per frame, so there is no Step event to remember.
	__time_source = time_source_create(time_source_game, 1, time_source_units_frames, method(self, __Tick), [], -1);
	time_source_start(__time_source);

	#endregion
}
