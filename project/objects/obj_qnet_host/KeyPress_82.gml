/// @description Reconnect

try {
	var _port = network.Start(1);
	q_log($"Socket at port {_port}");
} catch (_qnetexception) {}

try {
	network.Connect("127.0.0.1", 3000);
	q_log($"Sent connection request to localhost:{3000}");
} catch (_qnetexception) {}	










