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
*/
function TestStruct(_x = [buffer_u16], _y = buffer_u16) constructor 
{
	xx = _x;
	yy = _y;
	
	OnReceive = function()
	{
		show_debug_message($"Recieved {xx} {yy}");	
	}
}


qnet_serialization_init([TestStruct]);

var _buffer = qnet_serialize(new TestStruct([10, 15, 12, 6], 15));
var _received_struct_1 = qnet_deserialize(_buffer);

_received_struct_1.OnReceive();