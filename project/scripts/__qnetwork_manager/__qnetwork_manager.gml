function QNetworkManager(_serializable_structs) constructor
{
	#macro QNET_EXCEPTION_CREATE_SOCKET_FAILED "Create Socket Failed"
	#macro QNET_EXCEPTION_MAX_CONNECTIONS      "Max Connections Reached"
	#macro QNET_EXCEPTION_ALREADY_CONNECTED    "Already Connected"
	
	__port = 3000;
	__max_connections = 1;
	__connections = [];
	__socket = undefined;

	__serializer = new QSerializer({
		structs: _serializable_structs,
		header_config: {
			reliable: buffer_bool,
		}
	});
	
	// feather ignore once GM1043 - Feather doesn't recognize "method" as valid type for Function arg.
	// Function runs periodically to take actions depending on a Connections' status.
	__connection_status_check = new QSimpleTimesource(2, method(self, function() {			
			q_log("Performing Connection Status Check");
			for (var _i = 0; _i < array_length(__connections); _i++)
			{
				var _iconnection = __connections[_i];
				if (is_undefined(_iconnection)) 
					continue;
				
				if (_iconnection.status = QCONNECTION_STATUS.TIMEOUT)
				{
					OnConnectionRequestTimeout(_iconnection);	
				}
			}
		})
	);
	
	/// Start the network. This initializes a socket and begins listening for incoming messages. THROWS - QNET_EXCEPTION_CREATE_SOCKET_FAILED
	function Start(_max_connections, _port = undefined)
	{
		var _socket_result;

		if (_port != undefined)
		{
			q_log($"ATTEMPTING TO BIND PORT {_port}")
			_socket_result = network_create_socket_ext(network_socket_udp, _port);
			q_log($"SOCKET RESULT {_socket_result}")
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
		__connections     = array_create(_max_connections, undefined);;
		
		return __port;
	}
	
	function Connect(_ip, _port) 
	{
		if (GetConnection(_ip, _port) != undefined)
		{
			q_warn("Attempting to send a connection request to a peer which we are already connected to.");
			return;	
		}
		var _new_connection = AddConnection(_ip, _port);
		_new_connection.AttemptConnection();
	}
	
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
				break;
			}
		}
		
		if (_new_connection == undefined)
		{
			throw(QNET_EXCEPTION_MAX_CONNECTIONS);
		}
		
		show_debug_message($"Added new connection: {_new_connection}");
		return _new_connection
	}
	
	function RemoveConnection(_connection)
	{
		for (var _i = 0; _i < array_length(__connections); _i++)
		{
			var _iconnection = __connections[_i];
			if (!is_undefined(_iconnection) && _iconnection.id == _connection.id)
			{
				__connections[_i] = undefined;
				_iconnection.Shutdown();
				q_log($"Connection {_i} removed.");
			}
		}
	}
	
	/// Get a connection instance with the provided ip and port.
	/// @param {String} _ip
	/// @param {Real} _port
	/// @return {Struct.QConnection, Undefined}
	function GetConnection(_ip, _port)
	{
		// Check if connection already exists for the incoming address.
		for (var _i = 0; _i < array_length(__connections); _i++)
		{
			var _iconnection = __connections[_i];
			if (_iconnection != undefined && _iconnection.ip == _ip && _iconnection.port == _port)
			{
				return _iconnection;
			}
		}
		
		return undefined;
	}
	
	function SendPacket(_struct_instance, _ip, _port)
	{
		var _buffer = __serializer.Serialize(_struct_instance, { reliable: false });
		network_send_udp(__socket, _ip, _port, _buffer, buffer_get_size(_buffer));	
	}
	
	function AsyncNetworkEvent()
	{
		if (__socket == undefined)
		{
			q_warn("Async Network Event Fired, but QNetworkManager does not have a socket.");
			return;
		}
		
		var _id = async_load[? "id"];
		var _ip = async_load[? "ip"];
		var _port = async_load[? "port"];
		var _buffer = async_load[? "buffer"];
			
		show_debug_message($"ID: {_id} | IP: {_ip} | PORT: {_port} | BUFFER: {_buffer}");
		var _received_packet = __serializer.Deserialize(_buffer);
		var _is_reliable = _received_packet.header_data.reliable;
		
		// Update the connections last communication time
		var _incoming_connection = GetConnection(_ip, _port);
		if (_incoming_connection != undefined)
		{
			_incoming_connection.last_communication_time = current_time;
		}
		
		_received_packet.struct.OnReceive(self, _incoming_connection);
	}
	
	/// Called when a new Peer makes connection to remote Host, or a remote Peer makes connection to local Host. 
	/// You may override this function with network_manager.OnPeerConnected = function(_connection) { your custom code }
	/// @param {Struct.QConnection} _connection The newly created connection.
	function OnPeerConnected(_connection)
	{	// Called from QConnectionRequest Serializable
		q_log($"[QNETWORK MANAGER] A new peer has connected with id {_connection.id}");
	}
	
	/// Called when this Peer has requested a connection, and the remote peer sent a connection rejection response.
	/// May override the default behavior of this function with network_manager.OnConnectionRequestRejected(_reason);
	/// @param {String} _reason Message with information on why the connection was rejected
	function OnConnectionRequestRejected(_reason)
	{   // Called from QConnectionRequest Serializable
		RemoveConnection(_connection);
		q_log($"[QNETWORK MANAGER] Connection request has failed - {_reason}");
	}
	
	/// Called when a connection attempt times out.
	/// May override the default behavior of this function with network_manager.OnConnectionRequestTimeout(_connection_id);
	/// @param {Struct.QConnection} _connection The connection instance that failed.
	function OnConnectionRequestTimeout(_connection)
	{
		RemoveConnection(_connection);
		q_log($"[CONNECTION FAILED] No Response From Remote Peer {_connection.id}");	
	}
}