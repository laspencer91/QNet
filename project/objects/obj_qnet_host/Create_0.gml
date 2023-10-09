show_debug_log(true);

network_manager = new QNetworkManager([QConnectionRequest]);

try {
	var _port = network_manager.Start(1, 3000);
	q_log($"Socket initialized at port: {_port}");
} catch (_exception) {
	var _port = network_manager.Start(1);
	q_log($"Socket at port {_port}");
	network_manager.Connect("127.0.0.1", 3000);
	q_log($"Sent connection request to localhost:{3000}");
}

//var _buffer = serializer.Serialize(new PlayerPosition(10, 10), { reliable: false });
//var _received_deserialized = serializer.Deserialize(_buffer);
//show_debug_message($"Received: {_received_deserialized.struct}");
//show_debug_message($"Reliable? {_received_deserialized.header_data.reliable}");