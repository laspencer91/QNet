/// Opens an error window with a Qnet formatted string, and crashes the game.
function qnet_error(_error, _hint, _example) 
{
	show_error($"---------- QNET ---------- \n{_error}\n \n---------- HINT ---------- \n{_hint} \n \n---------- EXAMPLE ----------\n{_example}) \n\n", false);
}

/// Logs a Qnet error to the console, but does not open an Error Window or crash the game. 
function qnet_error_quiet(_message) 
{
	show_debug_message($"[QNET] [ERROR] {_message}");
}

/// Logs a Qnet warning message to the console.
function qnet_warn(_message) 
{
	show_debug_message($"[QNET] [WARNING] {_message}");
}

#region LOGGING EXAMPLE MESSAGES
#macro __QNET_STRING_SERIALIZATION_EXAMPLE @"function ExampleStruct(_xx) constructor 
{ 
	MANUAL_SERIALIZATION
	
	xx = _xx; 
	
	OnReceive = function() 
	{
		show_debug_message(xx);
	}
	
	Write = function(_buffer) 
	{
		buffer_write(_buffer, buffer_u16, xx);
	}
	
	Read = function(_buffer) 
	{
		xx = buffer_write(_buffer, buffer_u16);
	}
}"
#endregion