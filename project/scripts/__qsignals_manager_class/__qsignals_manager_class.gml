/// feather ignore all

/// @desc Signal Manager class is meant to be private. It is used by QSignals functions.
function __QSignalManager() constructor
{
	static _current_room = room;
	
	static signal_map = ds_map_create();	
	
	static AddListener = function(_instance_id, _signal_identifier, _callback)
	{
		__CleanOnRoomChange()
		
		if (!ds_map_exists(signal_map, _signal_identifier))
		{
			__QSignalManager.signal_map[? _signal_identifier] = ds_list_create();
		}

		// If the calling instance already has a callback for this signal, overwrite it.
		var _listener_list = signal_map[? _signal_identifier];
		for (var _i = 0; _i < ds_list_size(_listener_list); _i++)
		{
			var _listener = _listener_list[| _i]; 
			if (_listener.instance == _instance_id)
			{
				_listener.callback = _callback;
				return;
			}
		}
		
		// If the instance wasn't found in the list, add it.
		ds_list_add(signal_map[?  _signal_identifier], { instance: _instance_id, callback: _callback });
	}
	
	static RemoveListener = function (_instance_id, _signal_identifier)
	{
		__CleanOnRoomChange()
		
		if (!ds_map_exists(signal_map, _signal_identifier))
		{
			return;
		}

		// If delete the listener from the list if found.
		var _listener_list = signal_map[? _signal_identifier];
		for (var _i = 0; _i < ds_list_size(_listener_list); _i++)
		{
			var _listener = _listener_list[| _i]; 
			if (_listener.instance == _instance_id)
			{
				ds_list_delete(_listener_list, _i);
				return;
			}
		}
		
	}
	
	static EmitSignal = function(_signal_identifier, _params)
	{
		__CleanOnRoomChange()
		
		var _listener_list = signal_map[? _signal_identifier];

		if (_listener_list != undefined)
		{
			for (var _i = 0; _i < ds_list_size(_listener_list); _i++)
			{
				var _item = _listener_list[| _i];
				
				if (!instance_exists(_item.instance))
				{
					ds_list_delete(_listener_list, _i--);
					continue;
				}
				
				if (!is_callable(_item.callback))
				{
					show_debug_message($"[QSignal Error] A signal is registered with an uncallable function. Signal - {_signal_identifier}");
					ds_list_delete(_listener_list, _i--);
					continue;
				}
				
				_item.callback(_params);
			}
		}
	}
	
	/// Detects room change and clears signal connections for destroyed instances. Persistent Instance signals persist.
	static __CleanOnRoomChange = function()
	{
		if (room == _current_room)
		{
			return;
		}
		
		_current_room = room;
		
		// Loop through each signal, get the list of listerners, loop through each listener. Remove the listener if it does not exist.
		var _key = ds_map_find_first(__QSignalManager.signal_map);
		
		while (_key != undefined)
		{
			var _signal_listener_list = __QSignalManager.signal_map[? _key];
			for (var _i = 0; _i < ds_list_size(_signal_listener_list); _i++)
			{
				var _signal_listener = _signal_listener_list[| _i];
				if (!instance_exists(_signal_listener.instance))
				{
					ds_list_delete(_signal_listener_list, _i--);
				}
			}
			
			_key = ds_map_find_next(__QSignalManager.signal_map, _key);
		}
	}
}