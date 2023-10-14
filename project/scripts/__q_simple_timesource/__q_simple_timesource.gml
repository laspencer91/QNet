/// Simple wrapper around a timesource. The timesource starts on creation.
function QSimpleTimesource(_period_seconds, _callback, _reps = -1) constructor
{
	_timesource = time_source_create(time_source_game, _period_seconds, time_source_units_seconds, _callback, [], _reps);
	
	function Start()
	{
		time_source_start(_timesource);
		return self;
	}
	
	function Reset()
	{
		time_source_reset(_timesource);	
	}
	
	function Stop()
	{
		time_source_stop(_timesource);
	}
	
	function GetState()
	{
		time_source_get_state(_timesource);	
	}
	
	function Destroy()
	{
		time_source_stop(_timesource);
		time_source_destroy(_timesource);	
	}
}