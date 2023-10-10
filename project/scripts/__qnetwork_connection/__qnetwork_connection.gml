function QNetworkConnection(_id, _ip, _port, _qnet_manager) constructor
{
	enum QCONNECTION_STATUS { DISCONNECTED, CONNECTED, CONNECTING }
	
	id					    = _id;
	ip						= _ip;
	port				    = _port;
	last_communication_time = current_time;
	heartbeat_frequency     = 2;
	status					= QCONNECTION_STATUS.DISCONNECTED;
	
	__qnet_manager = _qnet_manager;
	// The socket id to communicate through.
	__socket = _qnet_manager.__socket;
	// QSerializer instance that comes from this Connections owning QNetworkManager
	__serializer = _qnet_manager.__serializer;
	
	function MakeAlive()
	{
		q_log("[MAKE ALIVE] CALLED! CONNECTED!");
		status = QCONNECTION_STATUS.CONNECTED;
		time_source_stop(__connect_attempt_repeater);
		time_source_start(__heartbeat);
	}
	
	function AttemptConnection(_on_connection_attempt_timeout)
	{
		if (status == QCONNECTION_STATUS.CONNECTED)
		{
			q_warn($"Connection {id} attempted a connection but is already connected.");
			time_source_stop(__connect_attempt_repeater);
			return;
		}
		
		if (status == QCONNECTION_STATUS.CONNECTING) return;
		
		status = QCONNECTION_STATUS.CONNECTING;

		SendPacket(new QConnectionRequest(QCONNECTION_REQUEST_STATUS.REQUESTED));
		
		__on_connection_attempt_timeout = _on_connection_attempt_timeout;
		__connect_attempts = 0;
		time_source_reset(__connect_attempt_repeater);	// RESET
		time_source_start(__connect_attempt_repeater);  // -> START
	}
	
	__connect_attempts = 0;
	__max_connection_attempts = 5;
	__on_connection_attempt_timeout = undefined;
	__connect_attempt_repeater = time_source_create(time_source_game, 1, time_source_units_seconds, function() {
		q_log($"Sending Connection Request {__connect_attempts++}");
		SendPacket(new QConnectionRequest(QCONNECTION_REQUEST_STATUS.REQUESTED));	
		if (__connect_attempts >= __max_connection_attempts)
		{	// Timeout
			__on_connection_attempt_timeout(self);
		}
	}, [], __max_connection_attempts, time_source_expire_nearest);
	
	function SendPacket(_struct_instance)
	{
		var _buffer = __serializer.Serialize(_struct_instance, { reliable: false });
		network_send_udp(__socket, ip, port, _buffer, buffer_get_size(_buffer));	
	}
	
	// The heartbeat keeps the connection alive by sending a keep alive packet every couple seconds.
	__heartbeat = time_source_create(time_source_game, heartbeat_frequency, time_source_units_seconds, function()
	{
		static __heartbeat_packet = new QConnectionHeartbeat();
		SendPacket(__heartbeat_packet);	
	}, [], -1);
}