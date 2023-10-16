/// Simple wrapper around a timesource.
function QSimpleTimesource(_period_seconds, _callback, _reps = -1) constructor
{
	_timesource = time_source_create(time_source_game, _period_seconds, time_source_units_seconds, _callback, [], _reps);
	
	/// Start running the function.
	function Start()
	{
		time_source_start(_timesource);
		return self;
	}
	
	// Reset the timesource.
	function Reset()
	{
		time_source_reset(_timesource);	
	}
	
	// Stop the timesource.
	function Stop()
	{
		time_source_stop(_timesource);
	}
	
	// Get the state of the timesource.
	function GetState()
	{
		time_source_get_state(_timesource);	
	}
	
	// Stop and destroy the timesource rendering this QSimpleTimesource unusuable.
	function Destroy()
	{
		time_source_stop(_timesource);
		time_source_destroy(_timesource);	
	}
}