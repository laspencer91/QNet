/// @desc Deserializes data in a buffer to a registered struct instance.
/// @param {Id.Buffer} _buffer A buffer with data to be deserialized. For example, a received network packet./
/// @returns {Struct, undefined}
function qnet_deserialize(_buffer)
{
	buffer_seek(_buffer, buffer_seek_start, 0);

	// Read serializable_id (packet identifier). This will allow us to lookup the type of data to expect.	
	var _serializable_id = buffer_read(_buffer, SERIALIZABLE_ID_BUFFER_TYPE);
	// Retrieve configuration for the identified struct.
	var _serialization_config = global.__struct_serialization_config_map[? _serializable_id];
	if (_serialization_config == undefined)
	{
		qnet_error_quiet($"Attempted to process an unrecognized serializable_id ({_serializable_id}). If you are receiving data from external sources (networking), they could have passed incorrect data.");
		return undefined;
	}

	if (_serialization_config.uses_manual_serialization)
	{
		var _struct_instance = new _serialization_config.struct_id();
		
		try 
		{
			_struct_instance.Read(_buffer);
		} 
		catch(_exception) 
		{
			if (string_pos("<unknown_object>.Read", _exception.message))
			{
				qnet_error($"[UNIMPLEMENTED] {instanceof(_struct_instance)}.Read() may be unimplemented.",
							"- You have marked a registered a struct with MANUAL_SERIALIZATION. \n- This struct requires a Read() function to be implemented.",
							__QNET_STRING_SERIALIZATION_EXAMPLE);
			}
			else
			{
				show_error(_exception.longMessage, false);	
			}
		}
		
		return _struct_instance;
	}
	else
	{	
		// Standard deserizalation
		var _struct_id = _serialization_config.struct_id;
	
		// Get to the right place after serializable_id (which is the first byte)
		buffer_seek(_buffer, buffer_seek_start, 1);

		return __qnet_read_buffer_to_struct(_buffer, _struct_id);
	}	
}

///@desc Creates a buffer and writes it by serializing the struct
///@param {Struct} _serializable_struct_instance An instance of a struct that has been previously registered by qnet_register_serializable()
///@returns {Id.Buffer,undefined} Buffer with serialized data written. Or undefined(-10) if it could not be written.
function qnet_serialize(_struct_instance) 
{	
	if (!is_struct(_struct_instance))
	{
		qnet_error($"Error attempting to execute qnet_serialize({_struct_instance}). \nNo packet instance was provided to be serialized.", 
				   "- Did you forget the keyword 'new'? \n- Make sure you are attempting to send an instance of a struct.", 
				   "qnet_serialize(new SomeStruct(10, 30.2))");
	}
	
	var _struct_id = asset_get_index(instanceof(_struct_instance));
	var _serializable_id = global.__struct_id_to_serializable_id_map[? _struct_id];

	if (_serializable_id == undefined)
	{
		qnet_error($"NO ID FOUND FOR STRUCT: {instanceof(_struct_instance)}", 
					"Is it registered with QNET via qnet_serialization_init([])?",
		            "qnet_serialization_init([Struct1, Struct2, YourStructName])");
	}

	// Array of data types that were registered with packet_layout_register
	var _serialization_config = global.__struct_serialization_config_map[? _serializable_id];
	var _data_types = _serialization_config.data_types;

	if (_serialization_config == undefined)
	{
		qnet_error($"There is no registered serialization config for packet type: {_serializable_id}",
		            "This is a bug and should be reported. \nEmail: laspencer@live.com \nI will response as quickly as possible.",
					"global.__struct_serialization_config_map[? _serializable_id] should contain the configuration for your serializable struct.");
	}

	// Create buffer and write packet identifier
	var _buffer = buffer_create(1, buffer_grow, 1);
	buffer_write(_buffer, SERIALIZABLE_ID_BUFFER_TYPE, _serializable_id);	

	// If this packet type is registered as being a serializer, let it do the serialization.
	if (_serialization_config.uses_manual_serialization)
	{
		// Use the manual serializer to write the buffer.
		try 
		{
			_struct_instance.Write(_buffer);
		} 
		catch(_exception) 
		{
			if (string_pos("<unknown_object>.Write", _exception.message))
			{
				qnet_error($"[UNIMPLEMENTED] {instanceof(_struct_instance)}.Write() may be unimplemented.",
				            "- You have marked a registered a struct with MANUAL_SERIALIZATION. \n- This struct requires a Write() function to be implemented.",
							__QNET_STRING_SERIALIZATION_EXAMPLE);
			}
			else
			{
				show_error(_exception.longMessage, false);	
			}
		}
	}
	else
	{
		__qnet_write_struct_to_buffer(_buffer, _struct_id, _struct_instance);	// Recursive
	}

	buffer_resize(_buffer, buffer_tell(_buffer));

	return _buffer;
}

///@desc Writes a struct to a buffer. The struct must be registered with QNET in the qnet_register_custom_serializables() script.
///      Recursive  function, will end on a data type not being an array.
function __qnet_write_struct_to_buffer(_buffer, _struct_id, _struct_instance)
{
	var _serializable_id = global.__struct_id_to_serializable_id_map[? _struct_id];
	var _serialization_config = global.__struct_serialization_config_map[? _serializable_id];
	
	if (_serialization_config == undefined)
	{
		qnet_error($"While attempting to write struct to a buffer, there is no registered serialization config for struct: {instanceof(_struct_instance)}.",
		            "This struct should be included with qnet_serialization_init().",
					"qnet_serialization_init([ExampleStruct]);");
	}
	
	var _serialization_config_data_types = _serialization_config.data_types;
	
	var _struct_field_names_array = struct_get_variable_names(_struct_instance);

	for (var _a = 0; _a < array_length(_struct_field_names_array); _a++) 
	{
		var _field_name	  = _struct_field_names_array[_a];
		var _data_type	  = _serialization_config_data_types[_a];
		var _field_value  = _struct_instance[$ _field_name];		
		
		if (_data_type == buffer_string && !is_string(_field_value))
			show_debug_message("When building a registered message, a string was expected but a 'real' number was passed.");	
		if (is_string(_field_value) && _data_type != buffer_string)
			show_debug_message("When building a registered message, a string was passed in but a 'real' number was expected.");
		
		if (is_array(_data_type))
		{
			// Handles an array type
			var _array_data_type = _data_type[0];
			
			if (_array_data_type == CUSTOM_BUFFER_SERIALIZER)
			{
				// Data type will be handled by a custom serializer.
				var _serializer = _data_type[1];
				if (_serializer == undefined) 
				{ 
					qnet_error("[PACKET WRITE] Custom buffer reader not setup correctly.",
					           "Reader needs to be specified.", 
							   "function ExampleStruct(datafield = [ CUSTOM_BUFFER_SERIALIZER, reader_function_name ]) constructor {"); 
				}
				_serializer.write(_buffer, _field_value);	// Pass the buffer and the data off to the custom serializer
			}
			else
			{
				// Data type is an Array of a Type
				// We begin by writing the length of the array.
				var _array_length = array_length(_field_value);
				buffer_write(_buffer, buffer_u16, _array_length);
				
				if (__is_registered_struct(_array_data_type))
				{
					// The data type is an array of a Structs. Call this function recursively.
					for (var _ei = 0; _ei < _array_length; _ei++) 
					{
						__qnet_write_struct_to_buffer(_buffer, _array_data_type, _field_value[_ei]);
					}
				}
				else 
				{
					// The data type is an array of "primitives" (buffer_u8, buffer_u16, etc...)
					// Write the data into the buffer.
					for (var _ei = 0; _ei < _array_length; _ei++) 
					{
						buffer_write(_buffer, _array_data_type, _field_value[_ei]);
					}
				}
			}
		}
		else if (__is_registered_struct(_data_type)) 
		{
			// Handles writing of a single struct
			__qnet_write_struct_to_buffer(_buffer, _data_type, _field_value);
		}
		else
		{
			// Handles the writing of a single primitive (buffer_u8, buffer_u16, etc...) type.
			buffer_write(_buffer, _data_type, _field_value);
		}
	}	
}

///TODO: This can be made recursive. To allow nested structs to be read. But we need to match it up with struct writing.
function __qnet_read_buffer_to_struct(_buffer, _struct_type) 
{
	var _serializable_id = global.__struct_id_to_serializable_id_map[? _struct_type];
	var _serialization_config_data_types = global.__struct_serialization_config_map[? _serializable_id].data_types;
	
	// Read the buffer, one data type at a time, storing the read data into this array.
	var _data = array_create(array_length(_serialization_config_data_types));
	for (var _i = 0; _i < array_length(_serialization_config_data_types); _i++)
	{
		var _curr_field_datatype = _serialization_config_data_types[_i];
		
		if (is_array(_curr_field_datatype))
		{
			var _array_type = _curr_field_datatype[0];
			if (_array_type == CUSTOM_BUFFER_SERIALIZER)
			{
				var _buffer_reader = _curr_field_datatype[1];
				if (_buffer_reader == undefined) 
				{ 
					qnet_error("[PACKET READ] Custom buffer reader not setup correctly.", 
					           "Reader needs to be specified.",
							   "function ExampleStruct(_field = [ CUSTOM_BUFFER_SERIALIZER, reader_function_name ]) constructor {");
				}
				
				_data[_i] = _buffer_reader.read(_buffer);
			}
			else 
			{
				var _num_of_array_entries = buffer_read(_buffer, buffer_u16);
				var _sub_array		      = array_create(_num_of_array_entries, undefined);
			
				if (__is_registered_struct(_array_type))
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
		else if (__is_registered_struct(_curr_field_datatype))
		{
			_data[_i] = __qnet_read_buffer_to_struct(_buffer, _curr_field_datatype);
		}
		else
		{
			_data[_i] = buffer_read(_buffer, _curr_field_datatype); // Read single data normally
		}
	}
	// Construct the struct instance, piling all the previously read data into it.
	var _struct_inst = new _struct_type(); // Data type is a struct, we create an instance. And fill it out.
	var _field_names = struct_get_variable_names(_struct_inst);
			
	for (var _ei = 0; _ei < array_length(_data); _ei++) 
	{
		_struct_inst[$ _field_names[_ei]] = _data[_ei];
	}

	return _struct_inst;
}

/// Returns whether a given function id exists.
/// @param {Asset.GMScript} _number 
function __is_registered_struct(_number) 
{
	if (_number > 100000 && script_exists(_number))
	{
		return true;
	}
	
	return false;
}