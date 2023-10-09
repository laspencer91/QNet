function QNetConnection(_id, _ip, _port) constructor
{
	id = _id;
	ip = _ip;
	port = _port;
}

function QNetworkManager(_serializable_structs) constructor
{
	#macro QNET_EXCEPTION_CREATE_SOCKET_FAILED "Create Socket Failed"
	#macro QNET_EXCEPTION_MAX_CONNECTIONS      "Max Connections Reached"
	
	__port = 3000;
	__max_connections = 1;
	__connections = [];
	__socket = undefined;

	serializer = new QSerializer({
		structs: _serializable_structs,
		header_config: {
			reliable: buffer_bool,
		}
	});
	
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
	
	function AddConnection(_ip, _port)
	{
		var _new_connection = undefined;
		for (var _id = 0; _id < array_length(__connections); _id++)
		{
			if (__connections[_id] == undefined)
			{
				_new_connection = new QNetConnection(_id, _ip, _port);
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
	
	function SendPacket(_struct_instance, _ip, _port)
	{
		var _buffer = serializer.Serialize(_struct_instance, { reliable: false });
		network_send_udp(__socket, _ip, _port, _buffer, buffer_get_size(_buffer));	
	}
	
	function Connect(_ip, _port) 
	{
		var _connection_request = new QConnectionRequest(QCONNECTION_REQUEST_STATUS.REQUESTED);
		var _buffer = serializer.Serialize(_connection_request, { reliable: false });
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
		var _received_packet = serializer.Deserialize(_buffer);
		var _is_reliable = _received_packet.header_data.reliable;
		_received_packet.struct.OnReceive(self);
	}
}