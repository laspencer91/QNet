show_debug_log(true);

role = "PEER";

network = new QNetworkManager([QConnectionRequest, QConnectionHeartbeat]);

network.OnPeerConnected = function(_connection) 
{
	q_log($"[NetManager GM INSTANCE] A new peer has connected with connection id {_connection.id}");
}

network.OnConnectionRequestRejected = function(_reason)
{
	q_log($"[NetManager] FAILED CONNECTION: {_reason}");
}

try {
	var _port = network.Start(1, 3000);
	q_log($"Socket initialized at port: {_port}");
	role = "SERVER";
} catch (_exception) {
	var _port = network.Start(1);
	q_log($"Socket at port {_port}");
	network.Connect("127.0.0.1", 3005);
	q_log($"Sent connection request to localhost:{3005}");
}

//var _buffer = serializer.Serialize(new PlayerPosition(10, 10), { reliable: false });
//var _received_deserialized = serializer.Deserialize(_buffer);
//show_debug_message($"Received: {_received_deserialized.struct}");
//show_debug_message($"Reliable? {_received_deserialized.header_data.reliable}");


// Connection ID is a local identifier for a Connection Object.
// Connection ID can be used to send a packet to a Connection, but cannot identify "players"
// for game syncronization.

// For game syncro, peer ids must be built on an additional layer.