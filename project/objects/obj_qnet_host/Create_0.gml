show_debug_log(true);

role = "PEER";
game_protocol_id = 54232;
network = new QNetworkManager(game_protocol_id, [
	QConnectionRequest, 
	QConnectionHeartbeat, 
	QConnectionDisconnect
]);

network.OnPeerConnected = function(_connection) 
{
	q_log($"[NetManager GM INSTANCE] A new peer has connected with connection id {_connection.id}");
}

network.OnConnectionRequestRejected = function(_reason)
{
	q_log($"[NetManager] FAILED CONNECTION: {_reason}");
}

network.OnConnectionTimeout = function(_connection)
{
	q_log($"[CUSTOM NET MANAGER] Connection {_connection.id} timed out!");
	network.RemoveConnection(_connection);
}

try {
	var _port = network.Start(10, 3000);
	//network.Connect("127.0.0.1", 3001);
	q_log($"Socket initialized at port: {_port}");
	role = "SERVER";
} catch (_exception) {
	var _port = network.Start(1);
	q_log($"Socket at port {_port}");
	network.Connect("127.0.0.1", 3000);
	q_log($"Sent connection request to localhost:{3000}");
}