/// feather ignore all

/// Readable text for a QNET_REASON value.
/// @param {Enum.QNET_REASON} _reason
/// @returns {String}
function qnet_reason_to_string(_reason)
{
	switch (_reason)
	{
		case QNET_REASON.LOCAL:           return "Closed locally";
		case QNET_REASON.REMOTE:          return "Closed by remote peer";
		case QNET_REASON.TIMEOUT:         return "Timed out";
		case QNET_REASON.SERVER_FULL:     return "Server is full";
		case QNET_REASON.SCHEMA_MISMATCH: return "Message list or QNet version does not match the host";
		case QNET_REASON.CONNECT_TIMEOUT: return "No response from host";
	}
	return "None";
}

/// Readable text for a QNET_CHANNEL value.
/// @param {Enum.QNET_CHANNEL} _channel
function qnet_channel_to_string(_channel)
{
	switch (_channel)
	{
		case QNET_CHANNEL.UNRELIABLE: return "unreliable";
		case QNET_CHANNEL.SEQUENCED:  return "sequenced";
		case QNET_CHANNEL.RELIABLE:   return "reliable";
	}
	return "invalid";
}

#region ---- Sequence numbers (u16, wrap around) ------------------------------------

/// True if sequence number _a is newer than _b, accounting for wrap-around at 65536.
function __qnet_seq_greater(_a, _b)
{
	return ((_a > _b) && (_a - _b <= 32768)) || ((_a < _b) && (_b - _a > 32768));
}

/// How far forward _newer is from _older, in 0..65535.
function __qnet_seq_diff(_newer, _older)
{
	return (_newer - _older + 65536) mod 65536;
}

/// The next sequence number after _seq.
function __qnet_seq_next(_seq)
{
	return (_seq + 1) mod 65536;
}

#endregion

#region ---- Misc ---------------------------------------------------------------------

/// Small xorshift32 generator. QNet uses this for salts and the network simulator so it
/// never consumes GameMaker's random state (lockstep games depend on that being untouched).
function __QNetRandom() constructor
{
	state = (get_timer() ^ (current_time << 11) ^ floor(date_current_datetime() * 86400000)) & 0xFFFFFFFF;
	if (state == 0) state = 0x9E3779B9;

	/// Stir an extra value (a port, a pointer) into the state.
	static Mix = function(_value)
	{
		state = (state ^ ((floor(_value) * 2654435761) & 0xFFFFFFFF)) & 0xFFFFFFFF;
		if (state == 0) state = 0x9E3779B9;
		NextU32();
	}

	/// @returns {Real} 0 .. 4294967295
	static NextU32 = function()
	{
		var _x = state;
		_x = (_x ^ (_x << 13)) & 0xFFFFFFFF;
		_x = _x ^ (_x >> 17);
		_x = (_x ^ (_x << 5)) & 0xFFFFFFFF;
		state = _x;
		return _x;
	}

	/// @returns {Real} 0 <= n < 1
	static NextFloat = function()
	{
		return NextU32() / 4294967296;
	}
}

/// First 32 bits of the md5 of a string, as a number.
function __qnet_hash_u32(_string)
{
	static _digits = "0123456789abcdef";
	var _hex = md5_string_utf8(_string);
	var _value = 0;
	for (var _i = 1; _i <= 8; _i++)
	{
		_value = _value * 16 + (string_pos(string_char_at(_hex, _i), _digits) - 1);
	}
	return _value;
}

/// The name of a script function or constructor, or undefined if _value is not one.
function __qnet_function_name(_value)
{
	if (is_method(_value)) _value = method_get_index(_value);
	try
	{
		if (script_exists(_value)) return script_get_name(_value);
	}
	catch (_exception) {}
	return undefined;
}

/// Names of a struct's data fields (methods excluded), sorted so every peer agrees on the order.
function __qnet_struct_field_names(_struct)
{
	var _names = variable_struct_get_names(_struct);
	var _fields = [];
	for (var _i = 0; _i < array_length(_names); _i++)
	{
		if (!is_method(_struct[$ _names[_i]])) array_push(_fields, _names[_i]);
	}
	array_sort(_fields, true);
	return _fields;
}

/// A message body: an exact-size buffer of encoded message bytes.
function __qnet_body_clone(_body)
{
	var _copy = buffer_create(_body.size, buffer_fixed, 1);
	buffer_copy(_body.buffer, 0, _body.size, _copy, 0);
	return { buffer: _copy, size: _body.size };
}

/// Logs a warning only the first time a given key is seen.
function __qnet_warn_once(_key, _message)
{
	static _seen = {};
	if (variable_struct_exists(_seen, _key)) return;
	_seen[$ _key] = true;
	q_warn(_message);
}

#endregion

/// _config[$ _name] if it is set, otherwise _default.
function __qnet_option(_config, _name, _default)
{
	var _value = _config[$ _name];
	return (_value == undefined) ? _default : _value;
}
