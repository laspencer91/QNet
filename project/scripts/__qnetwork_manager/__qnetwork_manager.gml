function QNetworkManager(_serializable_structs) constructor
{
	enum QNET_DELIVERY_TYPE { UNRELIABLE, SEQUENCED, RELIABLE_SEQENCED }
	#macro QNET_EXCEPTION_NETWORK_ALREADY_STARTED "Network Already Started"
	#macro QNET_EXCEPTION_CREATE_SOCKET_FAILED    "Create Socket Failed"
	#macro QNET_EXCEPTION_MAX_CONNECTIONS         "Max Connections Reached"
	#macro QNET_EXCEPTION_ALREADY_CONNECTED       "Already Connected"
	
	is_running = false;
	
	__port = 3000;
	__max_connections = 1;
	__connection_timeout = 5 * 1000;
	__connections = [];
	__connection_id_lookup = ds_map_create();
	__socket = undefined;

	#macro QNET_SEQ_BUFFER_TYPE buffer_u16

	// The buffer type used for serializing the sequence number value.
	__serializer = new QSerializer({
		structs: _serializable_structs,
		header_config: {
			delivery_type: buffer_u8,
			sequence: QNET_SEQ_BUFFER_TYPE,
			ack: QNET_SEQ_BUFFER_TYPE,
			ack_bits: buffer_u16
		}
	});
	
	/// Start the network. This initializes a socket and begins listening for incoming messages. 
	/// THROWS [QNET_EXCEPTION_CREATE_SOCKET_FAILED] - If a socket could not be created. 
	/// THROWS [QNET_EXCEPTION_NETWORK_ALREADY_STARTED] - If this network manager is already running.
	function Start(_max_connections, _port = undefined)
	{
		if (is_running)
		{
			q_warn("Cannot Start(). The Network Manager is already running.");
			throw(QNET_EXCEPTION_NETWORK_ALREADY_STARTED);
		}
		if (__socket != undefined)
		{
			q_warn("Cannot Start(). The Network Manager already has a socket initialized.");
			throw(QNET_EXCEPTION_NETWORK_ALREADY_STARTED);
		}
		
		var _socket_result;
		// Find Port and attempt to create scoket
		if (_port != undefined)
		{
			_socket_result = network_create_socket_ext(network_socket_udp, _port);
			if (_socket_result >= 0) 
			{
				__port   = _port;
				__socket = _socket_result;
			}
		}
		else 
		{
			// Search for a port between the port range above
			for (var _i = 3000; _i <= 6000; _i++)
			{
				_socket_result = network_create_socket_ext(network_socket_udp, _i);
				if (_socket_result >= 0)
				{
					__port = _i;
					__socket = _socket_result;
					break;
				}
			}
		}
		// If socket was not successfully initialized
		if (_socket_result < 0) throw(QNET_EXCEPTION_CREATE_SOCKET_FAILED);
		
		__max_connections = _max_connections;
		__connections     = array_create(_max_connections, undefined);
		
		__connection_status_check.Start();
		
		is_running = true;
		
		return __port;
	}
	
	// Shutdown the network manager. This closes the communication socket and shuts down all connections.
	// Start can be called again to restart network communication.
	function Shutdown()
	{
		// Stop connection status checker, and reset it for future use.
		__connection_status_check.Stop();
		__connection_status_check.Reset();
		
		// Disconnect all connections. Clear out our array.
		for (var _i = 0; _i < array_length(__connections); _i++)
		{
			var _iconnection/*: QNetworkConnection*/ = __connections[_i];
			if (is_undefined(_iconnection)) continue;
			_iconnection.Disconnect();
		}
		__connections = [];
		ds_map_clear(__connection_id_lookup);
		
		// Destroy Socket
		if (__socket != undefined)
		{
			network_destroy(__socket);
			__socket = undefined;
		}
		
		is_running = false;
		
		q_log("NetworkManager has shutdown.");
	}
	
	/// Begin a connection attempt to an ip and port.
	/// THROWS [QNET_EXCEPTION_ALREADY_CONNECTED] - if a connection to the provided address already exists.
	function Connect(_ip, _port) 
	{
		if (GetConnection(_ip, _port) != undefined)
		{
			q_warn($"Connection Request Failed. Already connected to {_ip}:{_port}.");
			throw (QNET_EXCEPTION_ALREADY_CONNECTED);
		}
		var _new_connection = AddConnection(_ip, _port);
		_new_connection.AttemptConnection();
	}
	
	/// Add a new connection to this network manager associated with an ip and port.
	function AddConnection(_ip, _port)
	{
		var _new_connection = undefined;
		
		// Check if connection already exists for the incoming address.	
		if (GetConnection(_ip, _port) != undefined)
		{
			throw(QNET_EXCEPTION_ALREADY_CONNECTED);	
		}
		
		for (var _id = 0; _id < array_length(__connections); _id++)
		{
			if (__connections[_id] == undefined)
			{
				_new_connection = new QNetworkConnection(_id, _ip, _port, self);
				__connections[_id] = _new_connection;
				__connection_id_lookup[? $"{_ip}:{_port}"] = _id;
				break;
			}
		}
		
		if (_new_connection == undefined)
		{
			throw(QNET_EXCEPTION_MAX_CONNECTIONS);
		}
		
		show_debug_message($"Added new connection: {_new_connection}");
		return _new_connection;
	}
	
	/// Effectively disconnects a connection and removes it from the QNetworks tracking. OnPeerDisconnected() will not be called.
	/// Will send a packet to the peer which is served by the connection instance unless "quietly" is true.
	/// @param {Struct.QConnection} _connection QConnection instance to disconnect.
	/// @param {Bool} _quietly Default: false. If true, will be removed without sending a disconnection notification to the peer.
	function RemoveConnection(_connection, _quietly = false)
	{
		if (is_undefined(_connection))
		{
			q_warn("RemoveConnection was called with an undefined connection param.");
			return;
		}
		__connections[_connection.id] = undefined;
		ds_map_delete(__connection_id_lookup, $"{_connection.ip}:{_connection.port}");
		if (_quietly) _connection.status = QCONNECTION_STATUS.DISCONNECTED;
		_connection.Disconnect();
	}
	
	/// Get a connection instance with the provided ip and port.
	/// @param {String} _ip
	/// @param {Real} _port
	/// @return {Struct.QConnection, Undefined}
	function GetConnection(_ip, _port)
	{
		var _connection_id = __connection_id_lookup[? $"{_ip}:{_port}"];
		return !is_undefined(_connection_id) ? __connections[_connection_id] : undefined;
	}
	
	/// Get a connection instance assigned to the specified id. Undefined is returned if no connection is assigned the id.
	/// @param {Real} _id The qnet connection id assigned to a connection instance.
	/// @return {Struct.QConnection, Undefined}
	function GetConnectionById(_id)
	{
		return __connections[_id];
	}
	
	/// Send a packet to an IP and PORT.
	function SendPacketToAddress(_struct_instance, _ip, _port)
	{
		var _buffer = __serializer.Serialize(_struct_instance, { delivery_type: QNET_DELIVERY_TYPE.UNRELIABLE, sequence: 0 });
		network_send_udp(__socket, _ip, _port, _buffer, buffer_get_size(_buffer));	
	}
	
	/// Receive and process data. Must be called in an objects Async event.
	function AsyncNetworkEvent()
	{
		static _name_of_connection_req_packet = instanceof(new QConnectionRequest());
		
		if (__socket == undefined)
		{
			q_warn("Async Network Event Fired, but QNetworkManager does not have a socket.");
			return;
		}
		
		var _id     = async_load[? "id"];
		var _ip     = async_load[? "ip"];
		var _port   = async_load[? "port"];
		var _buffer = async_load[? "buffer"];
			
		var _received_packet    = __serializer.Deserialize(_buffer);
		var _delivery_type      = _received_packet.header_data.delivery_type;
		var _incoming_sequence  = _received_packet.header_data.sequence;		// Incoming packets' sequence value.
		var _incoming_ack       = _received_packet.header_data.ack;				// Most recently acked packet from sender
		var _incoming_ack_bits  = _received_packet.header_data.ack_bits;		// Bits containing flags for previous acks
		var _is_newest_sequence = false;
		
		var _incoming_connection = GetConnection(_ip, _port);
		if (_incoming_connection != undefined)
		{
			_incoming_connection.last_data_received_time = current_time;
			
			_is_newest_sequence = _incoming_sequence > _incoming_connection.current_ack ||
								  _incoming_connection.current_ack - _incoming_sequence > 65530;
		}
		else if (instanceof(_received_packet.struct) != _name_of_connection_req_packet)
		{	// Do not process packets from unconnected addresses unless it is a connection request packet!
			q_warn("Recieving packets from an unconnected client!");
			return;
		}
		
		///////////////////////////////////////////////////
		//               Process the packet
		///////////////////////////////////////////////////
		if (_delivery_type == QNET_DELIVERY_TYPE.SEQUENCED)
		{
			q_log($"{_incoming_sequence} : {_incoming_connection.current_ack}");
			// If a packet with newer data beat this one here, forget about it.
			if (_is_newest_sequence)
			{
				_received_packet.struct.OnReceive(self, _incoming_connection);
			}
		}
		if (_delivery_type == QNET_DELIVERY_TYPE.RELIABLE_SEQENCED)
		{
			// TODO: IMPLEMENT INCOMING PACKET HANDLING
			// Get ACK number of the packet
			// Check - Have we processed the previous packet?
			// No? Add this packet to the ACKED packets DS. Do not process.
			// YES? Process the packet and add to the ACKED packets DS
			// Update the Connections 'current_ack' with this new value.
			
			// Because it is sequenced -> it should not process a packet until the previous one is received.
			// Because it is reliable -> It should save packets received out of order, and process them
			// when the completed order is received. And the completed order will be received because
			// if a packet is lost, the sending connection will be notified via 'ack_bits' and will
			// resend the packet.
			// The list of received and stored packets should exist on the Connection Object.
			// The list of sent but UNACKED packets should exist on the Connection Object.
			// When it is detected that a packet did not make it to its location, we should resend it.
			
		}
		if (_delivery_type == QNET_DELIVERY_TYPE.UNRELIABLE)
		{
			_received_packet.struct.OnReceive(self, _incoming_connection);	
		}
		
		// Update local incoming sequence only if this received packet is newer than the previous.
		if (_is_newest_sequence)
		{
			_incoming_connection.current_ack = _incoming_sequence;
		}
	}
	
	var __InternalConnectionCheck = function() 
	{			
		q_log("[NET MANAGER] Performing Connection Status Check", QLOG_LEVEL.DEEP_DEBUG);
		for (var _i = 0; _i < array_length(__connections); _i++)
		{
			var _iconnection = __connections[_i];
			if (is_undefined(_iconnection)) 
				continue;
				
			switch(_iconnection.status)
			{
				case QCONNECTION_STATUS.TIMEOUT:
					OnConnectionRequestTimeout(_iconnection);
					continue;
				case QCONNECTION_STATUS.CONNECTED:
					if (current_time - _iconnection.last_data_received_time > __connection_timeout)
					{
						OnConnectionTimeout(_iconnection);
						continue;
					}
					break;
			}
		}
	}
	
	// Periodically checks connections status and takes action dependent upon those statuses.
	__connection_status_check = new QSimpleTimesource(2, __InternalConnectionCheck);
	
	#region ------------------------ Overridable Callback Functions -------------------------------------------
	
	/// Called when a new Peer makes connection to remote Host, or a remote Peer makes connection to local Host. 
	/// You may override this function with network_manager.OnPeerConnected = function(_connection) { your custom code }
	/// @param {Struct.QConnection} _connection The newly created connection.
	function OnPeerConnected(_connection)
	{	// Called from QConnectionRequest Serializable
		q_log($"[QNETWORK MANAGER] A new peer has connected with id {_connection.id}");
	}
	
	/// Called when a QConnectionDisconnect message is received from a remote peer.
	/// You may override this function with network_manager.OnPeerDisconnected = function(_connection) { your custom code }
	/// @param {Struct.QConnection} _connection The disconnected connection.
	function OnPeerDisconnected(_connection)
	{	// Called from QConnectionRequest Serializable
		q_log($"[QNETWORK MANAGER] A new peer has disconnected with id {_connection.id}");
	}
	
	/// Called when this Peer has requested a connection, and the remote peer sent a connection rejection response.
	/// May override the default behavior of this function with network_manager.OnConnectionRequestRejected(_reason);
	/// @param {String} _reason Message with information on why the connection was rejected
	function OnConnectionRequestRejected(_reason)
	{   // Called from QConnectionRequest Serializable
		q_log($"[QNETWORK MANAGER] Connection request has failed - {_reason}");
	}
	
	/// Called when a connection attempt times out. Removes connection by default.
	/// May override the default behavior of this function with network_manager.OnConnectionRequestTimeout(_connection_id);
	/// @param {Struct.QConnection} _connection The connection instance that failed.
	function OnConnectionRequestTimeout(_connection)
	{
		RemoveConnection(_connection);
		q_log($"[CONNECTION FAILED] No Response From Remote Peer {_connection.id}");	
	}
	
	/// Called when an active connection times out. Removes the connection by default.
	/// May override the default behavior of this function with network_manager.OnConnectionTimeout(_connection_id);
	/// @param {Struct.QConnection} _connection The connection instance that failed.
	function OnConnectionTimeout(_connection)
	{
		RemoveConnection(_connection);
		q_log($"[CONNECTION TIMEOUT] No response detected from connection: {_connection.id}");	
	}
	
	#endregion --------------------- Overridable Callback Functions -------------------------------------------
	
	toString = function()
	{
		var _string = $"--- NETWORK MANAGER ---\n";
		var _status_text = is_running ? "RUNNING" : "STOPPED";
		var _active_connection_slots = ds_map_values_to_array(__connection_id_lookup);
		var _num_active_connections = !is_undefined(_active_connection_slots) ? array_length(_active_connection_slots) : 0;
		_string += $"Network is {_status_text}\n";
		_string += $"--- {_num_active_connections}/{__max_connections} Active Connections ---\n";
		for (var _i = 0; _i < _num_active_connections; _i++)
		{
			_string += $"{__connections[_active_connection_slots[_i]]}\n";
		}
		
		return _string;
	}
}