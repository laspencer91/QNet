/// @description Move, send state, keys

var _speed = 4;
my_x = clamp(my_x + (keyboard_check(vk_right) - keyboard_check(vk_left)) * _speed, 16, room_width - 16);
my_y = clamp(my_y + (keyboard_check(vk_down) - keyboard_check(vk_up)) * _speed, 16, room_height - 16);

// Position goes out every step on SEQUENCED: losing one is fine, the next replaces it.
if (network.ConnectionCount() > 0)
{
	network.SendToAll(new PlayerState(max(network.local_id, 0), my_x, my_y), QNET_CHANNEL.SEQUENCED);
}

// SPACE: burst of 100 reliable numbered messages. Turn on the simulator (L) to watch them survive loss.
if (keyboard_check_pressed(vk_space))
{
	repeat (100)
	{
		network.SendToAll(new CounterMessage(counter_next_to_send++), QNET_CHANNEL.RELIABLE);
	}
	Log($"Sent 100 reliable counters (up to {counter_next_to_send - 1})");
}

// C: chat
if (keyboard_check_pressed(ord("C")))
{
	var _chat = new ChatMessage(max(network.local_id, 0), $"hello from #{network.local_id} at {current_time}");
	network.SendToAll(_chat);
	Log($"[chat] me: {_chat.text}");
}

// L: toggle a bad network: 120ms +/- 40ms latency, 15% packet loss, on what this window sends.
if (keyboard_check_pressed(ord("L")))
{
	simulating = !simulating;
	if (simulating) network.Simulate(120, 40, 0.15);
	else network.Simulate();
	Log(simulating ? "Simulator ON: 120ms +/-40, 15% loss" : "Simulator OFF");
}

// D: disconnect.  R: host or rejoin.
if (keyboard_check_pressed(ord("D")))
{
	network.Shutdown();
}
if (keyboard_check_pressed(ord("R")) && !network.IsOnline())
{
	if (!network.Host(DEMO_PORT)) network.Join("127.0.0.1", DEMO_PORT);
}

// T: self-test room.
if (keyboard_check_pressed(ord("T")))
{
	room_goto(rm_qnet_selftest);
}
