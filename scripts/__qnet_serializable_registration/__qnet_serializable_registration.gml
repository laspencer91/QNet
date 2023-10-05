/**
@desc Registers serializable data with the QNET system. This allows QNET to identify a packet across the network.
@example
	// QNET can now send and recieve qnet_packet_kill
	qnet_register_serializable(qnet_packet_kill);
*/
///@param {Function} _struct_id An id of a serializable struct. NOTE: By default, QNET has a limit of 255 registered structs.
function qnet_register_serializable(_struct_id) 
{
	if (global.qnet_is_initialized) 
	{
		show_debug_message("QNET Has already been initialized. Cannot register anymore serializable packets. " +
				  "The only time these are registered is upon initialization. Do not call qnet_register_serializable manually");
		return;
	}
	
	static __serializable_id = 0;
	
	if (ds_map_exists(global.__packet_layout_map, __serializable_id)) 
	{
		show_debug_message($"The serializable struct cannot be re-registered, it has already been done for type {__serializable_id}");	
		return -1;
	}
	
	var _struct = new _struct_id();
	var _struct_property_names = struct_get_variable_names(_struct);
	
	if (_struct[$ "__isQnetCustomPacketHandler"] == true)
	{
		global.__manual_serialized_packet_map[? __serializable_id] = _struct; // Struct is an instance of the struct that will be used for serialization.	
	}
	
	// If there is data we need to build the array
	var _array_of_types = array_create(array_length(_struct_property_names));
	for (var _i = 0; _i < array_length(_struct_property_names); _i++)
	{
		var _data_type = _struct[$ _struct_property_names[_i]];
		if (_data_type == CUSTOM_BUFFER_SERIALIZER)
		{
			_array_of_types[_i] = [CUSTOM_BUFFER_SERIALIZER, _struct];			// The struct itself is flagged as having custom serialize functions to be used for this data.
		}
		else
		{
			_array_of_types[_i] = _data_type;		// The data type is a regular GM buffer type
		}
	}

	global.__packet_layout_map[? __serializable_id]         = new QnetSerializationLayout(_struct_id, _array_of_types);
	global.__struct_id_to_serializable_id_map[? _struct_id] = __serializable_id;

	show_debug_message($"REGISTERED {_struct_id} to {__serializable_id}");

	return __serializable_id++;
}

function QnetSerializationLayout(structId, dataTypes) constructor {
	self.structId = structId;
	self.dataTypes = dataTypes;
}