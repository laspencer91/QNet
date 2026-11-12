/******************************************************************
*     ____ _    ____ ____ ____ _ _  _ ____
*     |  | |    |  | | __ | __ | |\ | | __
*     |_\| |___ |__| |__] |__] | | \| |__]
*
*******************************************************************/

// Library-wide log level. DEFAULT shows connection events; DEBUG adds per-connection detail;
// DEEP_DEBUG logs every packet and is very noisy.
#macro __QLOG_LEVEL QLOG_LEVEL.DEFAULT

// The [APP NAME] that appears in console logs and error messages.
#macro __QLOG_APP_NAME "QNET"

enum QLOG_LEVEL {
	DEFAULT,
	DEBUG,
	DEEP_DEBUG,
}

/// Opens an error window with a formatted message and stops the game. Used for programmer
/// errors (bad arguments, unregistered messages), never for anything a remote peer can cause.
function q_error(_error, _hints, _example)
{
	var _hints_string = is_array(_hints) ? $"- {string_join_ext("\n- ", _hints)}" : $"- {_hints}";
	show_error($"---------- {__QLOG_APP_NAME} ---------- \n{_error}\n \n---------- HINT ---------- \n{_hints_string} \n \n---------- EXAMPLE ----------\n{_example} \n\n", true);
}

/// Logs an error to the console without stopping the game.
function q_error_quiet(_message)
{
	show_debug_message($"[{__QLOG_APP_NAME}] [ERROR] {_message}");
}

/// Logs a warning to the console.
function q_warn(_message)
{
	show_debug_message($"[{__QLOG_APP_NAME}] [WARNING] {_message}");
}

/// Logs a message to the console if the log level allows it.
/// @param {string} _message
/// @param {Enum.QLOG_LEVEL} _level
function q_log(_message, _level = QLOG_LEVEL.DEFAULT)
{
	if (__QLOG_LEVEL >= _level)
		show_debug_message($"[{__QLOG_APP_NAME}] {_message}");
}
