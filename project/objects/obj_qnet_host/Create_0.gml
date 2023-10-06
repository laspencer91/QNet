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

var _buffer = qnet_serialize(new TestStruct([
	new PlayerData([new PlayerPosition(5, 5), new PlayerPosition(92, 52), new PlayerPosition(11, 76)], "Logan"), 
	new PlayerData([new PlayerPosition(23, 15), new PlayerPosition(76, 205)], "Rob"), 
	new PlayerData([new PlayerPosition(1, 45)], "Mike")
]));

var _received_struct_1 = qnet_deserialize(_buffer);

_received_struct_1.OnReceive();