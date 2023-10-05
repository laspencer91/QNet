
global.__struct_id_to_serializable_id_map = ds_map_create();
global.__manual_serialized_packet_map = ds_map_create();
global.__packet_layout_map = ds_map_create();
global.qnet_is_initialized = false;

function TestStruct(_x = buffer_u16, _y = buffer_u16) constructor {
	xx = _x;
	yy = _y;
	
	OnReceive = function()
	{
		show_debug_message($"Recieved {xx} {yy}");	
	}
}

qnet_register_serializable(TestStruct);	// REGISTER
global.qnet_is_initialized = true;


var _buffer = qnet_serialize(new TestStruct(10, 15));
show_debug_message(buffer_get_size(_buffer));

buffer_seek(_buffer, buffer_seek_start, 0);
var _t = buffer_read(_buffer, buffer_u8);
var _xx = buffer_read(_buffer, buffer_u16);
var _yy = buffer_read(_buffer, buffer_u16);
buffer_seek(_buffer, buffer_seek_start, 0);

var _packet_id = buffer_read(_buffer, buffer_u8); // PacketId	
var _layout = global.__packet_layout_map[? _packet_id];
if (_layout == undefined)
{
	show_error("A packet has been received with a packetId of {}, but has not been registered in qnet_packet_layouts() \n Make sure you register this packet type! No data read", true);
	return;
}

// If this packet has a registered layout lets read it in
var _manual_serialization_packet = global.__manual_serialized_packet_map[? _packet_id];
if (_manual_serialization_packet == undefined)
{
	var _received_data = __qnet_read_packet(_packet_id, _buffer);
	if (_received_data == undefined)
	{
		// Manually read the data
		show_debug_message("No registered layout for this packetId. Please register the packet int qnet_packet_layouts()");
		return;
	}

	_received_data.OnReceive(0);
}
else
{
	// Qnet hands over the unpacking of the buffer to the manual serialization.
	_manual_serialization_packet.OnReceive(0, _buffer);
}