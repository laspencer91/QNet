/// Messages used by the demo and the self-test. Every peer registers the same list, in the same order.

/// A player's position. Sent every step on the SEQUENCED channel: if an old update arrives late it is dropped.
function PlayerState(_player_id = buffer_u8, _px = buffer_s16, _py = buffer_s16) constructor
{
	player_id = _player_id;
	px = _px;
	py = _py;
}

/// A numbered message sent on the RELIABLE channel. The receiver checks every number arrives once, in order.
function CounterMessage(_value = buffer_u32) constructor
{
	value = _value;
}

/// A chat line. Handled by its own OnReceive method instead of network.On(), to show both styles.
function ChatMessage(_from = buffer_u8, _text = buffer_string) constructor
{
	from = _from;
	text = _text;

	OnReceive = function(_connection)
	{
		with (obj_qnet_demo) Log($"[chat] #{other.from}: {other.text}");
		// The host relays chat to everyone else.
		if (_connection.network.IsHost()) _connection.network.SendToAll(self, QNET_CHANNEL.RELIABLE, _connection);
	}
}

// ---- Self-test only ------------------------------------------------------------------

function TestVec(_vx = buffer_s16, _vy = buffer_s16) constructor
{
	vx = _vx;
	vy = _vy;
}

/// Exercises every field kind: strings, bools, floats, nested structs, arrays of structs, arrays of arrays.
function TestBlob(_name = buffer_string, _origin = TestVec, _points = [TestVec], _grid = [[buffer_u8]], _flag = buffer_bool, _big = buffer_f64, _neg = buffer_s32) constructor
{
	name   = _name;
	origin = _origin;
	points = _points;
	grid   = _grid;
	flag   = _flag;
	big    = _big;
	neg    = _neg;
}

/// Hand-written serialization.
function TestManual(_count = 0, _label = "") constructor
{
	MANUAL_SERIALIZATION

	count = _count;
	label = _label;

	static Write = function(_buffer)
	{
		buffer_write(_buffer, buffer_u16, count);
		buffer_write(_buffer, buffer_string, label);
	}

	static Read = function(_buffer)
	{
		count = buffer_read(_buffer, buffer_u16);
		label = buffer_read(_buffer, buffer_string);
	}
}
