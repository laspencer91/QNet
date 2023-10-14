/******************************************************************
*     ____ _    ____ ____ ____ _ _  _ ____ 
*     |  | |    |  | | __ | __ | |\ | | __ 
*     |_\| |___ |__| |__] |__] | | \| |__] 
*
*******************************************************************/

// This is a library wide setting. Update this to change what messages get displayed.
#macro __QLOG_LEVEL QLOG_LEVEL.DEBUG

// Changing this will update the [APP NAME] that appears in console logs and error messages
#macro __QLOG_APP_NAME "QNET"

enum QLOG_LEVEL {
	DEFAULT,
	DEBUG,
	DEEP_DEBUG,
}


/// Opens an error window with a Qnet formatted string, and crashes the game.
function q_error(_error, _hints, _example) 
{
	var _hints_string = is_array(_hints) ? $"- {string_join_ext("\n- ", _hints)}" : _hints;
	show_error($"---------- ${__QLOG_APP_NAME} ---------- \n{_error}\n \n---------- HINT ---------- \n{_hints_string} \n \n---------- EXAMPLE ----------\n{_example} \n\n", false);
}

/// Logs a Qnet error to the console, but does not open an Error Window or crash the game. 
function q_error_quiet(_message) 
{
	show_debug_message($"[{__QLOG_APP_NAME}] [ERROR] {_message}");
}

/// Logs a Qnet warning message to the console.
function q_warn(_message) 
{
	show_debug_message($"[{__QLOG_APP_NAME}] [WARNING] {_message}");
}

/// Logs a Qnet log message to the console.
/// @param {string} _message
/// @param {Enum.QLOG_LEVEL} _level
function q_log(_message, _level = QLOG_LEVEL.DEFAULT) 
{
	if (__QLOG_LEVEL >= _level)
		show_debug_message($"[{__QLOG_APP_NAME}] [LOG] {_message}");
}