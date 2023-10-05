///@desc Creates a buffer and writes it by serializing the struct
///	qnet_packet_send_to_all(qnet_serialize(new PositionUpdate(x, y)));
///@param {Struct} _serializable_struct_instance An instance of a struct that has been previously registered by qnet_register_serializable()
///@returns {Id.Buffer,undefined} Buffer with serialized data written. Or undefined(-10) if it could not be written.
function qnet_serialize(_serializable_struct_instance) 
{	
	if (_serializable_struct_instance == undefined)
	{
		show_debug_message("[ERROR] No packet instance was provided to be serialized. Did you forget the keyword 'new'?");
		return undefined;
	}
	
	var _struct_id = asset_get_index(instanceof(_serializable_struct_instance));
	var _serializable_id = global.__struct_id_to_serializable_id_map[? _struct_id];
	
	if (_serializable_id == undefined)
	{
		show_debug_message($"Serializable Map - {ds_map_keys_to_array(global.__struct_id_to_serializable_id_map)}");
		show_debug_message($"[ERROR] Struct NAME, ID: {instanceof(_serializable_struct_instance)}, {_struct_id}");
		show_debug_message("[ERROR] No id could be found for struct: " + string(_serializable_struct_instance) + ". Are you sure it has been registered with QNET?");
		return undefined;
	}

	// Array of data types that were registered with packet_layout_register
	var _layout = global.__packet_layout_map[? _serializable_id];
	var _data_types = _layout.dataTypes;

	if (_layout == undefined)
	{
		show_debug_message($"[ERROR] There is no registered serialization layout for packet type: {_serializable_id}");
		return undefined;
	}

	// Create buffer and write packet identifier
	var _buffer = buffer_create(1, buffer_grow, 1);
	buffer_write(_buffer, buffer_u8, _serializable_id);	

	// If this packet type is registered as being a serializer, let it do the serialization.
	var _manual_serializer = global.__manual_serialized_packet_map[? _serializable_id];
	if (_manual_serializer != undefined)
	{
		// Use the manual serializer to write the buffer.
		var _should_send = _manual_serializer.Write(_buffer);
		if (!_should_send) { buffer_resize(_buffer, 0); }
	}
	else
	{
		qnet_write_struct_to_buffer(_buffer, _struct_id, _serializable_struct_instance);	// Recursive
	}

	buffer_resize(_buffer, buffer_tell(_buffer));

	return _buffer;
}

///@desc Writes a struct to a buffer. The struct must be registered with QNET in the qnet_register_custom_serializables() script.
///      Recursive  function, will end on a data type not being an array.
function qnet_write_struct_to_buffer(_buffer, _struct_id, _struct_instance)
{
	var _serializable_id = global.__struct_id_to_serializable_id_map[? _struct_id];
	var _struct_datatype_layout = global.__packet_layout_map[? _serializable_id].dataTypes;
	var _struct_field_names_array = struct_get_variable_names(_struct_instance);

	for (var _a = 0; _a < array_length(_struct_field_names_array); _a++) 
	{
		var _field_name	  = _struct_field_names_array[_a];
		var _data_type	  = _struct_datatype_layout[_a];
		var _field_value  = _struct_instance[$ _field_name];		
		
		if (_data_type == buffer_string && !is_string(_field_value))
			show_debug_message("When building a registered message, a string was expected but a 'real' number was passed.");	
		if (is_string(_field_value) && _data_type != buffer_string)
			show_debug_message("When building a registered message, a string was passed in but a 'real' number was expected.");
		
		if (is_array(_data_type))
		{
			var _array_type = _data_type[0];
			
			if (_array_type == CUSTOM_BUFFER_SERIALIZER)
			{
				var _serializer = _data_type[1];
				if (_serializer == undefined) { show_error("[PACKET WRITE] Custom buffer reader not setup correctly. Reader needs to be specified. EX: datafield = [ CUSTOM_BUFFER_SERIALIZER, reader_function_name ]", true); }
				_serializer.write(_buffer, _field_value);	// Pass the buffer and the data off to the custom serializer
			}
			else
			{
				var _array_length = array_length(_field_value);
				buffer_write(_buffer, buffer_u16, _array_length);
				
				if (is_registered_struct(_array_type))
				{
					for (var _ei = 0; _ei < _array_length; _ei++) 
					{
						qnet_write_struct_to_buffer(_buffer, _array_type, _field_value[_ei]);
					}
				}
				else 
				{
					// Write array contents
					for (var _ei = 0; _ei < _array_length; _ei++) 
					{
						buffer_write(_buffer, _array_type, _field_value[_ei]);
					}
				}
			}
		}
		else if (is_registered_struct(_data_type)) 
		{
			qnet_write_struct_to_buffer(_buffer, _data_type, _field_value);
		}
		else
		{
			buffer_write(_buffer, _data_type, _field_value);
		}
	}	
}


function is_registered_struct(_number) 
{
	if (_number > 100000 && script_exists(_number))
	{
		return true;
	}
	
	return false;
}

///@desc Read a packet using a registered layout. Will return "undefined" if no layout has been registered
///      for the given _serializable_struct_id.
///@param {real} _serializable_struct_id
///@param {Id.Buffer} _buffer
function __qnet_read_packet(_serializable_struct_id, _buffer) 
{
	var _layout = global.__packet_layout_map[? _serializable_struct_id];
	if (is_undefined(_layout))
	{
		return undefined;
	}
	var _packet_struct_id = _layout.structId;
	
	// Get to the right place after packet_type (which is the first byte)
	buffer_seek(_buffer, buffer_seek_start, 1);

	return __qnet_read_buffer_to_struct(_buffer, _packet_struct_id);
}

///TODO: This can be made recursive. To allow nested structs to be read. But we need to match it up with struct writing.
function __qnet_read_buffer_to_struct(_buffer, _struct_type) 
{
	var _serializable_id = global.__struct_id_to_serializable_id_map[? _struct_type];
	var _struct_field_datatypes = global.__packet_layout_map[? _serializable_id].dataTypes;
	
	// Read the buffer, one data type at a time, storing the read data into this array.
	var _data = array_create(array_length(_struct_field_datatypes));
	for (var _i = 0; _i < array_length(_struct_field_datatypes); _i++)
	{
		var _curr_field_datatype = _struct_field_datatypes[_i];
		
		if (is_array(_curr_field_datatype))
		{
			var _array_type = _curr_field_datatype[0];
			if (_array_type == CUSTOM_BUFFER_SERIALIZER)
			{
				var _buffer_reader = _curr_field_datatype[1];
				if (_buffer_reader == undefined) { show_error("[PACKET READ] Custom buffer reader not setup correctly. Reader needs to be specified. EX: datafield = [ CUSTOM_BUFFER_SERIALIZER, reader_function_name ]", true); }
				
				_data[_i] = _buffer_reader.read(_buffer);	// Read the buffer
			}
			else 
			{
				var _num_of_array_entries = buffer_read(_buffer, buffer_u16);
				var _sub_array		      = array_create(_numOfArrayEntries, undefined);
			
				if (is_registered_struct(_array_type))
				{
					// Read in an array of structs. Returns [FilledOutStructInstances]
					for (var _ae = 0; _ae < _num_of_array_entries; _ae++) 
					{
						_sub_array[_ae] = __qnet_read_buffer_to_struct(_buffer, _array_type);
					}	
				}
				else
				{
					// Read in an array of Gamemaker types.
					for (var _ae = 0; _ae < _num_of_array_entries; _ae++) 
					{
						_sub_array[_ae] = buffer_read(_buffer, _array_type);
					}	
				}
			
				_data[_i] = _sub_array;
			}
		}
		else if (is_registered_struct(_curr_field_datatype))
		{
			_data[_i] = __qnet_read_buffer_to_struct(_buffer, _curr_field_datatype);
		}
		else
		{
			show_debug_message($"Current Field Type: {_curr_field_datatype}");
			_data[_i] = buffer_read(_buffer, _curr_field_datatype); // Read single data normally
			show_debug_message($"Current Field Value: {_data[_i]}");
		}
	}
	// Construct the struct instance, piling all the previously read data into it.
	var _struct_inst = new _struct_type(); // Data type is a struct, we create an instance. And fill it out.
	var _field_names = struct_get_variable_names(_struct_inst);
			
	for (var _ei = 0; _ei < array_length(_data); _ei++) 
	{
		_struct_inst[$ _field_names[_ei]] = _data[_ei];
		show_debug_message($"Field Name: {_field_names[_ei]} = {_data[_ei]}")
	}

	return _struct_inst;
}