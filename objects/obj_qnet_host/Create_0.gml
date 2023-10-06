function TestStruct(_x = buffer_u16, _y = buffer_u16) constructor 
{
	xx = _x;
	yy = _y;
	
	OnReceive = function()
	{
		show_debug_message($"Recieved {xx} {yy}");	
	}
}

function TestStructManual(_x = buffer_u16, _y = buffer_u16) constructor 
{
	MANUAL_SERIALIZATION
	
	xx = _x;
	yy = _y;

	OnReceive = function()
	{
		show_debug_message($"MANUAL !! Recieved {xx} {yy}");	
	}
	
	static Write = function(_buffer)
	{
		show_debug_message($"{xx} {yy}");
		buffer_write(_buffer, buffer_u16, xx);
		buffer_write(_buffer, buffer_u16, yy);
	}
	
	static Read = function(_buffer)
	{
		xx = buffer_read(_buffer, buffer_u16);
		yy = buffer_read(_buffer, buffer_u16);
	}
}

qnet_serialization_init([TestStruct, TestStructManual]);

var _buffer = qnet_serialize(new TestStruct(10, 15));
var _buffer_2 = qnet_serialize(new TestStructManual(11, 12));
var _test_buff = buffer_create(3, buffer_fixed, 1);
buffer_write(_test_buff, buffer_u8, 10);
var _received_struct_1 = qnet_process_packet(_test_buff);
var _received_struct_2 = qnet_process_packet(_buffer_2);

_received_struct_2.OnReceive();