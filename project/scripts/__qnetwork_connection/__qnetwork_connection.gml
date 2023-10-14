function QNetworkConnection(_id, _ip, _port, _qnet_manager) constructor
{
	enum QCONNECTION_STATUS { DISCONNECTED, CONNECTED, CONNECTING, TIMEOUT }
	
	id					    = _id;
	ip						= _ip;
	port				    = _port;
	last_data_received_time = current_time;
	heartbeat_frequency     = 2;
	status					= QCONNECTION_STATUS.DISCONNECTED;
	ping                    = 0;
	
	__qnet_manager = _qnet_manager;
	// The socket id to communicate through.
	__socket = _qnet_manager.__socket;
	// QSerializer instance that comes from this Connections owning QNetworkManager
	__serializer = _qnet_manager.__serializer;
	// Counter used during the connection attempt process.
	__connect_attempts = 0;
	// The maximum amount of times to resend a connection request before timing out.
	__max_connection_attempts = 5;
	
	function OnConnect()
	{
		q_log("[MAKE ALIVE] CALLED! CONNECTED!");
		status = QCONNECTION_STATUS.CONNECTED;
	}
	
	function AttemptConnection()
	{
		if (status == QCONNECTION_STATUS.CONNECTED)
		{
			q_warn($"Connection {id} attempted a connection but is already connected.");
			return;
		}
		
		if (status == QCONNECTION_STATUS.CONNECTING) return;
		
		status = QCONNECTION_STATUS.CONNECTING;

		SendPacket(new QConnectionRequest(QCONNECTION_REQUEST_STATUS.REQUESTED));
	}
	
	function SendPacket(_struct_instance)
	{
		var _buffer = __serializer.Serialize(_struct_instance, { reliable: false });
		network_send_udp(__socket, ip, port, _buffer, buffer_get_size(_buffer));	
	}
	
	var __InternalPulse = function()
	{
		// Reuse this struct for each heartbeat. No reason to build a new one each time.
		static __heartbeat_packet = new QConnectionHeartbeat(current_time, false);

		if (status == QCONNECTION_STATUS.CONNECTING)
		{
			q_log($"Sending Connection Request {__connect_attempts++}");
			
			SendPacket(new QConnectionRequest(QCONNECTION_REQUEST_STATUS.REQUESTED));
			
			if (__connect_attempts >= __max_connection_attempts)
			{	
				// Timeout
				status = QCONNECTION_STATUS.TIMEOUT;
				__connect_attempts = 0;
			}	
		}
		else if (status == QCONNECTION_STATUS.CONNECTED)
		{
			// Set the heartbeat data.
			__heartbeat_packet.is_reply = false;
			__heartbeat_packet.sent_time = current_time;
			// Serialize and send.
			SendPacket(__heartbeat_packet);
		}
	}

	// The heartbeat keeps the connection alive by sending a keep alive packet every couple seconds.
	__pulse_timesource = new QSimpleTimesource(heartbeat_frequency, __InternalPulse).Start();
	
	/// Disconnects and shuts down communication to this connection. Calling this effectively destroys the connection
	/// and this instance cannot be reused. If this connection is currently connected, will also send a packet to the 
	/// peer, notifying them of the disconnection.
	function Disconnect()
	{
		__pulse_timesource.Destroy();
		
		if (status == QCONNECTION_STATUS.CONNECTED)
		{
			SendPacket(new QConnectionDisconnect());
		}
		
		status = QCONNECTION_STATUS.DISCONNECTED;
	}
}