/// @description QNet demo
// Run with the MultiClient extension (2+ instances): window 0 hosts, the others join it.
// Arrow keys move your square. Everyone sees everyone.

show_debug_log(true);

#macro DEMO_PORT 3000

network = new QNetwork({
	messages:    [PlayerState, CounterMessage, ChatMessage, TestVec, TestBlob, TestManual],
	max_clients: 7,
});

my_x = irandom_range(100, room_width - 100);
my_y = irandom_range(150, room_height - 100);
players = {};          // player id (as string) -> { px, py }
log = [];

// Reliable ordering check: each sender's counter must arrive 0, 1, 2, ... with nothing skipped or repeated.
counter_next_to_send = 0;
counter_expected = {}; // sender id (as string) -> next value we expect
counter_received = 0;
counter_errors = 0;

simulating = false;

Log = function(_text)
{
	array_push(log, _text);
	if (array_length(log) > 14) array_delete(log, 0, 1);
	show_debug_message(_text);
}

// ---- Callbacks ----------------------------------------------------------------------

network.OnConnected = function(_connection)
{
	if (network.IsHost()) Log($"Client #{_connection.id} joined");
	else Log($"Joined the host as #{network.local_id}");
}

network.OnDisconnected = function(_connection, _reason)
{
	Log($"#{_connection.id} disconnected: {qnet_reason_to_string(_reason)}");
	variable_struct_remove(players, string(_connection.id));
	variable_struct_remove(counter_expected, string(_connection.id));
	if (!network.IsHost()) players = {};
}

network.OnConnectFailed = function(_reason)
{
	Log($"Could not join: {qnet_reason_to_string(_reason)}");
}

// ---- Message handlers ----------------------------------------------------------------

network.On(PlayerState, function(_state, _from)
{
	if (network.IsHost())
	{
		// The host is the authority on who is who: never trust an id a client claims.
		_state.player_id = _from.id;
		network.SendToAll(_state, QNET_CHANNEL.SEQUENCED, _from);
	}
	if (_state.player_id == network.local_id) return;
	players[$ string(_state.player_id)] = { px: _state.px, py: _state.py };
});

network.On(CounterMessage, function(_counter, _from)
{
	var _key = string(_from.id);
	var _expected = counter_expected[$ _key];
	if (_expected == undefined) _expected = _counter.value; // first one we see from this sender
	if (_counter.value != _expected)
	{
		counter_errors++;
		Log($"ORDER ERROR from #{_from.id}: got {_counter.value}, expected {_expected}");
	}
	counter_expected[$ _key] = _counter.value + 1;
	counter_received++;
});

// ---- Start ----------------------------------------------------------------------------

if (MultiClientGetID() <= 0)
{
	if (network.Host(DEMO_PORT)) Log($"Hosting on port {DEMO_PORT}");
	else if (network.Join("127.0.0.1", DEMO_PORT)) Log("Port in use, joining it instead");
}
else
{
	network.Join("127.0.0.1", DEMO_PORT);
	Log($"Joining 127.0.0.1:{DEMO_PORT}");
}
