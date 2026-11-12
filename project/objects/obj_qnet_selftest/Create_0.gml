/// @description QNet self-test
// Unit checks first, then real networks talking over localhost, mostly through the simulator
// so that loss, delay and reordering actually happen. Results are drawn on screen and logged.
// ESC returns to the demo.

show_debug_log(true);

results = [];
messages = [PlayerState, CounterMessage, ChatMessage, TestVec, TestBlob, TestManual];

Check = function(_name, _ok, _detail = "")
{
	array_push(results, { name: _name, ok: _ok, detail: _detail });
	show_debug_message($"[QNET SELFTEST] {_ok ? "PASS" : "FAIL"}  {_name}  {_detail}");
}

#region ---- Unit checks ------------------------------------------------------------

Check("seq: 1 is newer than 0", __qnet_seq_greater(1, 0));
Check("seq: 0 is newer than 65535 (wrap)", __qnet_seq_greater(0, 65535));
Check("seq: 65535 is not newer than 0", !__qnet_seq_greater(65535, 0));
Check("seq: distance across the wrap", __qnet_seq_diff(2, 65534) == 4);

var _serializer = new QSerializer(messages);

var _blob = new TestBlob("hello world", new TestVec(-5, 7), [new TestVec(1, 2), new TestVec(-3, 4)], [[1, 2, 3], [], [255]], true, 1234.5678, -100000);
var _buffer = _serializer.Serialize(_blob);
var _copy = _serializer.Deserialize(_buffer);
buffer_delete(_buffer);
var _same = (_copy != undefined)
	&& instanceof(_copy) == "TestBlob"
	&& _copy.name == "hello world"
	&& _copy.origin.vx == -5 && _copy.origin.vy == 7
	&& array_length(_copy.points) == 2 && _copy.points[1].vx == -3 && _copy.points[1].vy == 4
	&& array_length(_copy.grid) == 3 && array_length(_copy.grid[0]) == 3 && _copy.grid[0][2] == 3
	&& array_length(_copy.grid[1]) == 0 && _copy.grid[2][0] == 255
	&& _copy.flag == true && _copy.big == 1234.5678 && _copy.neg == -100000;
Check("serializer: nested structs, arrays of structs, arrays of arrays", _same);

_buffer = _serializer.Serialize(new TestManual(42, "manual"));
_copy = _serializer.Deserialize(_buffer);
buffer_delete(_buffer);
Check("serializer: MANUAL_SERIALIZATION round trip", _copy != undefined && _copy.count == 42 && _copy.label == "manual");

var _same_list = new QSerializer(messages);
var _reordered = new QSerializer([CounterMessage, PlayerState, ChatMessage, TestVec, TestBlob, TestManual]);
Check("schema: same list gives the same hash", _same_list.schema_hash == _serializer.schema_hash);
Check("schema: a different order gives a different hash", _reordered.schema_hash != _serializer.schema_hash);

var _junk = buffer_create(4, buffer_fixed, 1);
buffer_write(_junk, buffer_u8, 250);
Check("serializer: unknown type id reads as undefined", _serializer.Deserialize(_junk) == undefined);
buffer_delete(_junk);

#endregion

#region ---- Network checks (driven from Step) --------------------------------------

nets = [];
NewNet = function(_config)
{
	var _net = new QNetwork(_config);
	array_push(nets, _net);
	return _net;
}

NextStage = function()
{
	stage++;
	stage_started = current_time;
	stage_entered = false;
	extra_result = -1;
}

// Networks created by a stage to probe a failure report through these.
OnExtraFailed = function(_reason) { extra_result = _reason; }
OnExtraConnected = function(_connection) { extra_result = 999; } // 999: unexpectedly connected

test_count = 500;
stage = 0;
stage_started = current_time;
stage_entered = false;

host = NewNet({ messages: messages, max_clients: 1, timeout: 3 });
host_port = -1;
for (var _port = 3500; _port < 3520; _port++)
{
	if (host.Host(_port))
	{
		host_port = _port;
		break;
	}
}
client = NewNet({ messages: messages, timeout: 3 });

// 20% loss and 60ms +/- 30ms each way: handshake retries, resends and reordering all get exercised.
host.Simulate(60, 30, 0.2);
client.Simulate(60, 30, 0.2);

host_connected = false;
client_connected = false;
host_next_send = 0;
client_next_send = 0;
host_expect = 0;
client_expect = 0;
order_errors = 0;
sequenced_px = 0;
sequenced_last = -1;
sequenced_backwards = 0;
host_disconnect_reason = -1;
client_disconnect_reason = -1;
extra_result = -1;

host.OnConnected = function(_connection)
{
	host_connected = true;
	repeat (test_count) _connection.Send(new CounterMessage(host_next_send++));
}
client.OnConnected = function(_connection)
{
	client_connected = true;
	repeat (test_count) _connection.Send(new CounterMessage(client_next_send++));
}
host.OnDisconnected = function(_connection, _reason) { host_disconnect_reason = _reason; }
client.OnDisconnected = function(_connection, _reason) { client_disconnect_reason = _reason; }

host.On(CounterMessage, function(_message, _from)
{
	if (_message.value != host_expect) order_errors++;
	host_expect = _message.value + 1;
});
client.On(CounterMessage, function(_message, _from)
{
	if (_message.value != client_expect) order_errors++;
	client_expect = _message.value + 1;
});
host.On(PlayerState, function(_message, _from)
{
	if (_message.px <= sequenced_last) sequenced_backwards++;
	sequenced_last = _message.px;
});

if (host_port < 0) Check("host: open a port in 3500..3519", false, "every port was in use");

#endregion
