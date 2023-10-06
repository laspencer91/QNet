/**
@desc Registers serializable data with the QNET system. This allows QNET to identify a packet across the network.
@example
	// QNET can now send and recieve qnet_packet_kill
	qnet_register_serializable(qnet_packet_kill);
*/
///@param {Function} _struct_id An id of a serializable struct.
/// By default, QNET has a limit of 255 registered structs. Configurable by #macro SERIALIZABLE_ID_BUFFER_TYPE
function qnet_register_serializable(_struct_id) 
{
	if (global.qnet_is_initialized) 
	{
		show_debug_message("QNET Has already been initialized. Cannot register anymore serializable packets. " +
				  "The only time these are registered is upon initialization. Do not call qnet_register_serializable manually");
		return;
	}
	
	static __serializable_id = 0;
	
	if (ds_map_exists(global.__struct_serialization_config_map, __serializable_id)) 
	{
		show_debug_message($"The serializable struct cannot be re-registered, it has already been done for type {__serializable_id}");	
		return -1;
	}
	
	var _struct = new _struct_id();
	var _struct_property_names = struct_get_variable_names(_struct);
	
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
	
	var _uses_manual_serialization = _struct[$ "__use_manual_serialization"] == true;
	global.__struct_serialization_config_map[? __serializable_id] = new QnetSerializationConfig(_struct_id, _array_of_types, _uses_manual_serialization);
	global.__struct_id_to_serializable_id_map[? _struct_id] = __serializable_id;

	show_debug_message($"[{_uses_manual_serialization ? "MANUAL" : "DEFAULT"} SERIALIZABLE STRUCT REGISTERED] {script_get_name(_struct_id)} with Serializable ID: {__serializable_id}");

	return __serializable_id++;
}

function QnetSerializationConfig(_struct_id, _data_types, _uses_manual_serialization) constructor 
{
	struct_id  = _struct_id;
	data_types = _data_types;
	uses_manual_serialization = _uses_manual_serialization;
}