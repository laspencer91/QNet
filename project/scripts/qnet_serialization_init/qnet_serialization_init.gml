/// Must be called before any qnet serialization can take place. All Serializable Struct types must be initialized here.
/// @param {Array} _serializable_structs An array of Struct Ids to be recognized by qnet_serialization. Example - qnet_serialization_init([PlayerPosition, Ping]);
function qnet_serialization_init(_serializable_structs)
{
	global.__struct_id_to_serializable_id_map = ds_map_create();
	global.__struct_serialization_config_map = ds_map_create();
	global.qnet_is_initialized = false;
	
	for (var _i = 0; _i < array_length(_serializable_structs); _i++)
	{
		qnet_register_serializable(_serializable_structs[_i]);
	}
	
	
	global.qnet_is_initialized = true;	
}