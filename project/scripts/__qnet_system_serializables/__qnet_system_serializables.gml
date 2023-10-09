enum QCONNECTION_REQUEST_STATUS
{
	REQUESTED,
	SUCCESS,
	FAILED_MAX_CONNECTION,
}

function QConnectionRequest(_status = buffer_u8, _assigned_id = buffer_s16) constructor
{
	__status      = _status; 
	__assigned_id = _assigned_id;	// Only valid if __status is SUCCESS.
	
	/// @param {Struct.QNetworkManager} _network_manager
	OnReceive = function(_qnetwork_manager)
	{
		var _ip = async_load[? "ip"];
		var _port = async_load[? "port"];

		// Logic handled on the Requestees side.
	    if (__status == QCONNECTION_REQUEST_STATUS.REQUESTED)
		{
			show_debug_message($"Received Connection Request From {_ip}:{_port}");
			try
			{
				var _created_connection = _qnetwork_manager.AddConnection(_ip, _port);
				var _response = new QConnectionRequest(QCONNECTION_REQUEST_STATUS.SUCCESS, _created_connection.id);
				_qnetwork_manager.SendPacket(_response, _ip, _port);
			}
			catch (_exception)
			{
				if (_exception == QNET_EXCEPTION_MAX_CONNECTIONS)
				{
					var _response = new QConnectionRequest(QCONNECTION_REQUEST_STATUS.FAILED_MAX_CONNECTION, undefined);
					_qnetwork_manager.SendPacket(_response, _ip, _port);		
				}
			}
		}
		
		// Response Logic Executed On The Requesters Side
		if (__status == QCONNECTION_REQUEST_STATUS.SUCCESS)
		{
			show_debug_message($"Received Successful Connection Response - Assigned ID: {__assigned_id}");
		}
		if (__status == QCONNECTION_REQUEST_STATUS.FAILED_MAX_CONNECTION)
		{
			show_debug_message($"Received Failed Connection Response - Max Connections Reached");	
		}
	}
}


