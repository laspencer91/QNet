/// @description Drive the network checks

if (keyboard_check_pressed(vk_escape)) room_goto(rm_qnet_test);
if (host_port < 0 || stage < 0) exit;

var _elapsed = current_time - stage_started;
var _enter = !stage_entered;
stage_entered = true;

switch (stage)
{
	case 0: // Handshake + reliable ordering + sequenced, under loss
		if (_enter) client.Join("127.0.0.1", host_port);
		if (client_connected)
		{
			client.SendToAll(new PlayerState(0, sequenced_px++, 0), QNET_CHANNEL.SEQUENCED);
		}
		if (host_expect >= test_count && client_expect >= test_count)
		{
			Check("handshake under 20% loss", true);
			Check($"{test_count} reliable messages each way arrive in order under loss", order_errors == 0, $"{order_errors} order errors, {_elapsed}ms");
			Check("sequenced messages never go backwards", sequenced_backwards == 0, $"{sequenced_backwards} went backwards");
			var _connection = client.GetConnection(0);
			var _resends = (_connection == undefined) ? 0 : _connection.stats.resends;
			Check("reliable resends happened (proves the loss path ran)", _resends > 0, $"{_resends} resends");
			host.Simulate();
			client.Simulate();
			NextStage();
		}
		else if (_elapsed > 30000)
		{
			Check("handshake under 20% loss", host_connected && client_connected);
			Check($"{test_count} reliable messages each way arrive in order under loss", false, $"host got {host_expect}, client got {client_expect}, {order_errors} order errors");
			host.Simulate();
			client.Simulate();
			NextStage();
		}
		break;

	case 1: // Server full (the host allows 1 client and has one)
		if (_enter)
		{
			var _full = NewNet({ messages: messages });
			_full.OnConnectFailed = OnExtraFailed;
			_full.OnConnected = OnExtraConnected;
			_full.Join("127.0.0.1", host_port);
		}
		if (extra_result != -1 || _elapsed > 6000)
		{
			Check("a full host denies with SERVER_FULL", extra_result == QNET_REASON.SERVER_FULL, $"got {extra_result}");
			NextStage();
		}
		break;

	case 2: // Different message list
		if (_enter)
		{
			var _mismatch = NewNet({ messages: [CounterMessage] });
			_mismatch.OnConnectFailed = OnExtraFailed;
			_mismatch.OnConnected = OnExtraConnected;
			_mismatch.Join("127.0.0.1", host_port);
		}
		if (extra_result != -1 || _elapsed > 6000)
		{
			Check("a different message list is denied with SCHEMA_MISMATCH", extra_result == QNET_REASON.SCHEMA_MISMATCH, $"got {extra_result}");
			NextStage();
		}
		break;

	case 3: // Nobody listening
		if (_enter)
		{
			var _lonely = NewNet({ messages: messages, connect_timeout: 1 });
			_lonely.OnConnectFailed = OnExtraFailed;
			_lonely.OnConnected = OnExtraConnected;
			_lonely.Join("127.0.0.1", host_port + 100);
		}
		if (extra_result != -1 || _elapsed > 4000)
		{
			Check("joining nothing fails with CONNECT_TIMEOUT", extra_result == QNET_REASON.CONNECT_TIMEOUT, $"got {extra_result} after {_elapsed}ms");
			NextStage();
		}
		break;

	case 4: // Clean disconnect
		if (_enter)
		{
			host_disconnect_reason = -1;
			client.Shutdown();
			Check("Shutdown() fires OnDisconnected(LOCAL) immediately", client_disconnect_reason == QNET_REASON.LOCAL, $"got {client_disconnect_reason}");
		}
		if (host_disconnect_reason != -1 || _elapsed > 2000)
		{
			Check("the host sees the client leave with REMOTE", host_disconnect_reason == QNET_REASON.REMOTE, $"got {host_disconnect_reason}");
			NextStage();
		}
		break;

	case 5: // Timeout: a client that goes silent
		if (_enter)
		{
			host_disconnect_reason = -1;
			client = NewNet({ messages: messages, timeout: 3 });
			client.OnConnected = function(_connection) { client.Simulate(0, 0, 1); }; // 100% loss from now on
			client.Join("127.0.0.1", host_port);
		}
		if (host_disconnect_reason != -1 || _elapsed > 8000)
		{
			Check("a silent client times out on the host with TIMEOUT", host_disconnect_reason == QNET_REASON.TIMEOUT, $"got {host_disconnect_reason} after {_elapsed}ms");
			NextStage();
		}
		break;

	default:
		var _passed = 0;
		for (var _i = 0; _i < array_length(results); _i++)
		{
			if (results[_i].ok) _passed++;
		}
		show_debug_message($"[QNET SELFTEST] DONE: {_passed}/{array_length(results)} passed");
		for (var _n = 0; _n < array_length(nets); _n++) nets[_n].Shutdown();
		stage = -1;
		break;
}
