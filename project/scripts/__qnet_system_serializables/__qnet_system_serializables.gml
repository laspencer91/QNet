enum QCONNECTION_REQUEST_STATUS
{
	REQUESTED,
	SUCCESS,
	FAILED_MAX_CONNECTION,
	FAILED_ALREADY_CONNECTED,
}

function QConnectionRequest(_status = buffer_u8, _assigned_id = buffer_s16) constructor
{
	__status      = _status; 
	__assigned_id = _assigned_id;	// Only valid if __status is SUCCESS.
	
	/// @param {Struct.QNetworkManager} _qnetwork
	OnReceive = function(_qnetwork, _sender)
	{
		var _ip = async_load[? "ip"];
		var _port = async_load[? "port"];

		// Logic handled on the Remote Peers' side.
	    if (__status == QCONNECTION_REQUEST_STATUS.REQUESTED)
		{
			q_log($"Received Connection Request From {_ip}:{_port}");
			
			try
			{
				var _created_connection = _qnetwork.AddConnection(_ip, _port);
				var _response = new QConnectionRequest(QCONNECTION_REQUEST_STATUS.SUCCESS, _created_connection.id);
				//_created_connection.SendPacket(_response);
				_created_connection.MakeAlive();
				_qnetwork.OnPeerConnected(_created_connection);
			}
			catch (_exception)
			{
				if (_exception == QNET_EXCEPTION_MAX_CONNECTIONS)
				{
					var _response = new QConnectionRequest(QCONNECTION_REQUEST_STATUS.FAILED_MAX_CONNECTION, undefined);
					_qnetwork.SendPacket(_response, _ip, _port);		
				}
				else if (_exception == QNET_EXCEPTION_ALREADY_CONNECTED)
				{
					q_warn("A client who is already connected attempted to reconnect.")
					var _response = new QConnectionRequest(QCONNECTION_REQUEST_STATUS.FAILED_ALREADY_CONNECTED, undefined);
					_qnetwork.SendPacket(_response, _ip, _port);	
				}
				else
				{
					q_error(_exception.longMessage, _exception.message, "None");	
				}
			}
		}
		
		// [SUCCESS] Response Logic Executed On The Local Peers' Side
		if (__status == QCONNECTION_REQUEST_STATUS.SUCCESS)
		{
			show_debug_message($"Received Successful Connection Response - We Are Assigned ID: {__assigned_id}");
			// Call the OnPeerConnected Callback. The Connection was created when the request began.
			_sender.MakeAlive();
			_qnetwork.OnPeerConnected(_sender);
		}
		
		// [FAILURE] MAX CONNECTIONS
		if (__status == QCONNECTION_REQUEST_STATUS.FAILED_MAX_CONNECTION)
		{
			_qnetwork.OnConnectionRequestRejected("Max Connections Reached");
			_qnetwork.RemoveConnection(_sender);
		}
		
		// [FAILURE] MAX CONNECTIONS
		if (__status == QCONNECTION_REQUEST_STATUS.FAILED_ALREADY_CONNECTED)
		{
			_qnetwork.OnConnectionRequestRejected("You Already Have An Active Connection To This Remote Peer");
			_qnetwork.RemoveConnection(_sender);
		}
	}
}

function QConnectionHeartbeat() constructor
{
	OnReceive = function(_qnetwork, _sender)
	{
		q_log($"Received Heartbeat From {_sender.id} at time {_sender.last_communication_time}");
	}
}