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
function PlayerPosition(_x = buffer_u32, _y = buffer_u8) constructor
{
	xx = _x;
	yy = _y;

	function toString()
	{
		return $"Position: ({xx}, {yy})"	
	}
}

function PlayerData(_position = PlayerPosition, _name = buffer_string) constructor
{
	name = _name;
	positions = _position;
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

var serializer = new QSerializer({
	structs: [PlayerPosition, TestStruct],
	header_config: {
		reliable: buffer_bool,
	}
});

var _buffer = serializer.Serialize(new PlayerPosition(10, 10), { reliable: false });

var _received_deserialized = serializer.Deserialize(_buffer);

show_debug_message($"Received: {_received_deserialized.struct}");
show_debug_message($"Reliable? {_received_deserialized.header_data.reliable}");