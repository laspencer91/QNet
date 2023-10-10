/// feather ignore all

/// @desc Emits a QSignal, activating all active listeners in the room.
/// @param {Any} _signal_identifier A Unique Signal Identifier. Listeners registered to the same ID will be triggered on emit.
/// @param {Struct,Undefined} _parameters (OPTIONAL) Parameters that will be sent to each listeners function. Use this to pass data to listeners.
function qsignal_emit(_signal_identifier, _parameters = undefined)
{
	if (!variable_global_exists("__qsignal_manager")) 
		global.__qsignal_manager = new __QSignalManager();
	
	global.__qsignal_manager.EmitSignal(_signal_identifier, _parameters);	
}

/// @desc Register the calling instance as a listener to a signal.
/// @param {Any} _signal_identifier A Unique Signal Identifier to listen for.
/// @param {Function} _callback A function that will play when this signal is emmitted.
function qsignal_listen(_signal_identifier, _callback)
{
	if (!variable_global_exists("__qsignal_manager")) 
		global.__qsignal_manager = new __QSignalManager();

	global.__qsignal_manager.AddListener(id, _signal_identifier, _callback);
}

/// @desc Cause the calling instance to stop listening to a signal.
/// @param {Any} _signal_identifier Unique Signal Identifier to stop listening to.
function qsignal_stop_listening(_signal_identifier)
{
	if (!variable_global_exists("__qsignal_manager")) 
		global.__qsignal_manager = new __QSignalManager();

	global.__qsignal_manager.RemoveListener(id, _signal_identifier);
}