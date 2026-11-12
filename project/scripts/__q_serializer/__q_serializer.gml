/*******************************************************************************************************************
*   ______          _______. _______ .______       __       ___       __       __   ________   _______ .______
*  /  __  \        /       ||   ____||   _  \     |  |     /   \     |  |     |  | |       /  |   ____||   _  \
* |  |  |  |      |   (----`|  |__   |  |_)  |    |  |    /  ^  \    |  |     |  | `---/  /   |  |__   |  |_)  |
* |  |  |  |       \   \    |   __|  |      /     |  |   /  /_\  \   |  |     |  |    /  /    |   __|  |      /
* |  `--'  '--..----)   |   |  |____ |  |\  \----.|  |  /  _____  \  |  `----.|  |   /  /----.|  |____ |  |\  \----.
*  \_____\_____\_______/    |_______|| _| `._____||__| /__/     \__\ |_______||__|  /________||_______|| _| `._____|
*
*  Turns registered structs into bytes and back.
*
*  A message type is a constructor whose arguments default to the type of each field:
*
*      function PlayerMove(_x = buffer_s16, _y = buffer_s16) constructor
*      {
*          x = _x;
*          y = _y;
*      }
*
*  Field types can be:
*      buffer_u8 ... buffer_u64, buffer_f16/f32/f64, buffer_bool, buffer_string
*      [type]            an array of that type (length is written as a u16, so up to 65535 items)
*      OtherMessage      a nested registered struct
*      [[type]], [Other] arrays nest freely
*
*  Fields are written in alphabetical order of their names, so every peer (GameMaker or Node)
*  agrees on the layout no matter what order the runtime reports struct variables in.
*
*  For full control, add MANUAL_SERIALIZATION and write Write(buffer) / Read(buffer) yourself.
*********************************************************************************************************************/

/// feather ignore all

// Put this as the first line of a message constructor to serialize it yourself with Write(buffer) and Read(buffer).
#macro MANUAL_SERIALIZATION static __use_manual_serialization = true

#macro __QSERIALIZER_MANUAL_EXAMPLE @"function ExampleMessage(_value = 0) constructor
{
	MANUAL_SERIALIZATION

	value = _value;

	static Write = function(_buffer)
	{
		buffer_write(_buffer, buffer_u16, value);
	}

	static Read = function(_buffer)
	{
		value = buffer_read(_buffer, buffer_u16);
	}
}"

/// Serializes and deserializes registered message structs.
/// Every peer must register the same messages in the same order: a message's position in the
/// array is its id on the wire.
/// @param {Array<Function>} _message_types Constructors, e.g. [PlayerMove, ChatMessage]. Nested struct types must be included too.
function QSerializer(_message_types) constructor
{
	// Message type records, indexed by wire id.
	__types_by_id = [];
	// Message type records, keyed by constructor name.
	__types_by_name = {};

	/// Hash of every registered type and field. Peers with different hashes cannot understand each other.
	schema_hash = 0;

	#region ---- Public --------------------------------------------------------------------

	/// Writes a message (its type id, then its fields) at the buffer's current position.
	/// @param {Id.Buffer} _buffer
	/// @param {Struct} _message An instance of a registered message type.
	static Write = function(_buffer, _message)
	{
		if (!is_struct(_message))
		{
			q_error($"Tried to send {_message}, which is not a struct.",
			        ["Did you forget the keyword 'new'?", "Messages are instances of a registered constructor."],
			        "connection.Send(new PlayerMove(x, y));");
		}
		var _type = __types_by_name[$ instanceof(_message)];
		if (_type == undefined)
		{
			q_error($"{instanceof(_message)} is not a registered message type.",
			        "Add it to the messages array when creating the QNetwork or QSerializer.",
			        "new QNetwork({ messages: [" + instanceof(_message) + ", ...] });");
		}
		buffer_write(_buffer, buffer_u8, _type.id);
		__WriteBody(_buffer, _type, _message);
	}

	/// Reads one message at the buffer's current position.
	/// Throws if the data is malformed; returns undefined if the type id is unknown.
	/// @param {Id.Buffer} _buffer
	/// @returns {Struct,Undefined}
	static Read = function(_buffer)
	{
		var _id = buffer_read(_buffer, buffer_u8);
		if (_id >= array_length(__types_by_id)) return undefined;
		return __ReadBody(_buffer, __types_by_id[_id]);
	}

	/// Serializes a message into a new buffer, sized exactly. You must buffer_delete() it.
	/// @param {Struct} _message
	/// @returns {Id.Buffer}
	static Serialize = function(_message)
	{
		var _buffer = buffer_create(64, buffer_grow, 1);
		Write(_buffer, _message);
		buffer_resize(_buffer, buffer_tell(_buffer));
		return _buffer;
	}

	/// Deserializes a whole buffer produced by Serialize(). Returns undefined if it cannot be read.
	/// @param {Id.Buffer} _buffer
	/// @returns {Struct,Undefined}
	static Deserialize = function(_buffer)
	{
		buffer_seek(_buffer, buffer_seek_start, 0);
		try
		{
			return Read(_buffer);
		}
		catch (_exception)
		{
			q_error_quiet($"Could not deserialize buffer: {_exception.message}");
			return undefined;
		}
	}

	/// True if _message_type (a constructor) is registered.
	static IsRegistered = function(_message_type)
	{
		var _name = __qnet_function_name(_message_type);
		return _name != undefined && variable_struct_exists(__types_by_name, _name);
	}

	#endregion

	#region ---- Writing ------------------------------------------------------------------

	static __WriteBody = function(_buffer, _type, _message)
	{
		if (_type.manual)
		{
			_message.Write(_buffer);
			return;
		}
		var _fields = _type.fields;
		var _codecs = _type.codecs;
		for (var _i = 0; _i < array_length(_fields); _i++)
		{
			__WriteValue(_buffer, _codecs[_i], _message[$ _fields[_i]], _type, _fields[_i]);
		}
	}

	static __WriteValue = function(_buffer, _codec, _value, _type, _field)
	{
		switch (_codec.kind)
		{
			case 0: // primitive
				if (_codec.buffer_type == buffer_string)
				{
					if (!is_string(_value)) __FieldError(_type, _field, "a string", _value);
				}
				else if (!is_numeric(_value))
				{
					__FieldError(_type, _field, "a number", _value);
				}
				buffer_write(_buffer, _codec.buffer_type, _value);
				break;

			case 1: // array
				if (!is_array(_value)) __FieldError(_type, _field, "an array", _value);
				var _length = array_length(_value);
				if (_length > 65535) __FieldError(_type, _field, "an array of at most 65535 items", $"{_length} items");
				buffer_write(_buffer, buffer_u16, _length);
				for (var _i = 0; _i < _length; _i++)
				{
					__WriteValue(_buffer, _codec.element, _value[_i], _type, _field);
				}
				break;

			case 2: // nested struct
				if (!is_struct(_value)) __FieldError(_type, _field, $"a {_codec.message_type.name} struct", _value);
				__WriteBody(_buffer, _codec.message_type, _value);
				break;
		}
	}

	static __FieldError = function(_type, _field, _expected, _value)
	{
		q_error($"{_type.name}.{_field} should be {_expected}, but it is {typeof(_value)}: {_value}",
		        ["Check the arguments passed to the constructor.", "A field left at its default holds its buffer type, not data."],
		        $"new {_type.name}(...)");
	}

	#endregion

	#region ---- Reading ------------------------------------------------------------------

	static __ReadBody = function(_buffer, _type)
	{
		var _ctor = _type.ctor;
		var _message = new _ctor();
		if (_type.manual)
		{
			_message.Read(_buffer);
			return _message;
		}
		var _fields = _type.fields;
		var _codecs = _type.codecs;
		for (var _i = 0; _i < array_length(_fields); _i++)
		{
			_message[$ _fields[_i]] = __ReadValue(_buffer, _codecs[_i]);
		}
		return _message;
	}

	static __ReadValue = function(_buffer, _codec)
	{
		switch (_codec.kind)
		{
			case 0:
				return buffer_read(_buffer, _codec.buffer_type);

			case 1:
				var _length = buffer_read(_buffer, buffer_u16);
				// Every element takes at least one byte except empty structs, so a length larger
				// than what is left in the buffer can only be garbage.
				if (_length > buffer_get_size(_buffer) - buffer_tell(_buffer) && !_codec.element.may_be_empty)
				{
					throw("QSerializer: array length exceeds remaining data");
				}
				var _array = array_create(_length);
				for (var _i = 0; _i < _length; _i++)
				{
					_array[_i] = __ReadValue(_buffer, _codec.element);
				}
				return _array;

			case 2:
				return __ReadBody(_buffer, _codec.message_type);
		}
		return undefined;
	}

	#endregion

	#region ---- Registration -------------------------------------------------------------

	static __PRIMITIVE_TYPES = [buffer_u8, buffer_s8, buffer_u16, buffer_s16, buffer_u32, buffer_s32, buffer_u64,
	                            buffer_f16, buffer_f32, buffer_f64, buffer_bool, buffer_string];

	static __Register = function(_ctor)
	{
		var _name = __qnet_function_name(_ctor);
		if (_name == undefined)
		{
			q_error($"Cannot register {_ctor} as a message type.",
			        ["Pass the constructor itself, not an instance or a call.", "Message types are declared with: function Name(...) constructor { }"],
			        "new QNetwork({ messages: [PlayerMove, ChatMessage] });");
		}
		if (variable_struct_exists(__types_by_name, _name))
		{
			q_error($"{_name} is registered twice.", "Each message type can appear in the list only once.", "messages: [PlayerMove, ChatMessage]");
		}

		var _sample = new _ctor();
		var _type = {
			id:     array_length(__types_by_id),
			name:   _name,
			ctor:   _ctor,
			manual: false,
			fields: [],
			declared: [],
			codecs: [],
			has_on_receive: false,
		};

		// Statics are not visible to variable_struct_get_names, so look these up directly.
		try { _type.manual = (_sample.__use_manual_serialization == true); } catch (_e1) { _type.manual = false; }
		try { _type.has_on_receive = is_callable(_sample.OnReceive); } catch (_e2) { _type.has_on_receive = false; }

		if (_type.manual)
		{
			var _has_read = false, _has_write = false;
			try { _has_read = is_callable(_sample.Read); } catch (_e3) {}
			try { _has_write = is_callable(_sample.Write); } catch (_e4) {}
			if (!_has_read || !_has_write)
			{
				q_error($"{_name} uses MANUAL_SERIALIZATION but is missing Read() or Write().",
				        "Manual messages implement both Write(buffer) and Read(buffer).",
				        __QSERIALIZER_MANUAL_EXAMPLE);
			}
		}
		else
		{
			_type.fields = __qnet_struct_field_names(_sample);
			for (var _i = 0; _i < array_length(_type.fields); _i++)
			{
				array_push(_type.declared, _sample[$ _type.fields[_i]]);
			}
		}

		array_push(__types_by_id, _type);
		__types_by_name[$ _name] = _type;
	}

	// Second pass, after every type is registered, so nested types can appear in any order.
	static __Compile = function(_type)
	{
		for (var _i = 0; _i < array_length(_type.declared); _i++)
		{
			array_push(_type.codecs, __CompileType(_type.declared[_i], _type, _type.fields[_i]));
		}
	}

	static __CompileType = function(_declared, _type, _field)
	{
		if (is_array(_declared))
		{
			if (array_length(_declared) != 1)
			{
				q_error($"{_type.name}.{_field} declares an array with {array_length(_declared)} entries.",
				        "Array fields declare a single element type.",
				        "function Path(_points = [buffer_s16]) constructor { points = _points; }");
			}
			return { kind: 1, element: __CompileType(_declared[0], _type, _field), may_be_empty: false };
		}

		if (is_numeric(_declared))
		{
			for (var _i = 0; _i < array_length(__PRIMITIVE_TYPES); _i++)
			{
				if (_declared == __PRIMITIVE_TYPES[_i]) return { kind: 0, buffer_type: _declared, may_be_empty: false };
			}
		}

		var _name = __qnet_function_name(_declared);
		if (_name != undefined && variable_struct_exists(__types_by_name, _name))
		{
			var _nested = __types_by_name[$ _name];
			return { kind: 2, message_type: _nested, may_be_empty: (!_nested.manual && array_length(_nested.declared) == 0) };
		}

		q_error($"{_type.name}.{_field} has an unsupported type: {_declared}",
		        ["Use a buffer type (buffer_u8, buffer_string, ...), an array like [buffer_u8], or a registered struct.",
		         "buffer_text is not supported because it cannot be read back. Use buffer_string.",
		         "Nested structs must also be in the messages list."],
		        "function Spawn(_name = buffer_string, _pos = Vec2, _tags = [buffer_u8]) constructor { ... }");
	}

	static __CodecString = function(_codec)
	{
		switch (_codec.kind)
		{
			case 0: return string(_codec.buffer_type);
			case 1: return "[" + __CodecString(_codec.element) + "]";
			case 2: return _codec.message_type.name;
		}
		return "?";
	}

	static __SchemaString = function()
	{
		var _schema = $"qnet{QNET_PROTOCOL_VERSION}";
		for (var _i = 0; _i < array_length(__types_by_id); _i++)
		{
			var _type = __types_by_id[_i];
			_schema += $"|{_type.name}:";
			if (_type.manual)
			{
				_schema += "manual";
				continue;
			}
			for (var _f = 0; _f < array_length(_type.fields); _f++)
			{
				_schema += $"{_type.fields[_f]}={__CodecString(_type.codecs[_f])},";
			}
		}
		return _schema;
	}

	#endregion

	#region ---- Construction -------------------------------------------------------------

	if (!is_array(_message_types))
	{
		q_error("QSerializer needs an array of message constructors.", "Pass the constructors themselves.", "new QSerializer([PlayerMove, ChatMessage])");
	}
	if (array_length(_message_types) > 256)
	{
		q_error("QSerializer supports at most 256 message types.", "Combine related messages, or use a type field inside one message.", "");
	}
	for (var _i = 0; _i < array_length(_message_types); _i++)
	{
		__Register(_message_types[_i]);
	}
	for (var _i = 0; _i < array_length(__types_by_id); _i++)
	{
		__Compile(__types_by_id[_i]);
	}
	schema_hash = __qnet_hash_u32(__SchemaString());

	q_log($"QSerializer registered {array_length(__types_by_id)} message types (schema {schema_hash})", QLOG_LEVEL.DEBUG);

	#endregion
}
