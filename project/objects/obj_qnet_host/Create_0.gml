/**
* Specify an array type with [buffer_type]
* @example
* function TestStruct(_x = [buffer_u16]) constructor {
*	...
* }
* // This is serializable.
* var _struct_instance = TestStruct([10, 15, 13, 12]);
* var _buffer = qnet_serialize(_struct_inst);
* var _recreated_struct_inst = qnet_process_buffer(_buffer);
*
* Handles nested structs, and nested struct arrays!
*/
function PlayerPosition(_x = buffer_u8, _y = buffer_u8) constructor
{
	xx = _x;
	yy = _y;
	
	function toString()
	{
		return $"Position: ({xx}, {yy})"	
	}
}

function PlayerData(_positions = [PlayerPosition], _name = buffer_string) constructor
{
	name = _name;
	positions = _positions;
}

function TestStruct(_players = [PlayerData]) constructor 
{
	players = _players;
	
	OnReceive = function()
	{
		for (var _i = 0; _i < array_length(players); _i++) 
		{
		    show_debug_message(players[_i]);
		}
	}
}

qnet_serialization_init([TestStruct, PlayerPosition, PlayerData]);

var serializer = new QSerializer(
function(_buffer, _props) {
	buffer_write(_buffer, buffer_bool, _props.reliable);
}, 
function(_buffer) {
	var reliable = buffer_read(_buffer, buffer_bool);
	show_debug_message($"READING BUFFER HEADER {reliable} {buffer_tell(_buffer)}")
	return {
		reliable 
	}
});

var _buffer = serializer.Serialize(new PlayerPosition(10, 10), { reliable: true });

show_debug_message($"Buffer length {buffer_get_size(_buffer)}")

var _received_deserialized = serializer.Deserialize(_buffer);

_received_deserialized.struct.OnReceive();
show_debug_message($"Reliable? {_received_deserialized.reliable}")