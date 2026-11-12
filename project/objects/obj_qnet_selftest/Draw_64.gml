/// @description Results

var _passed = 0;
for (var _i = 0; _i < array_length(results); _i++)
{
	if (results[_i].ok) _passed++;
}

draw_set_colour(c_white);
if (stage < 0) draw_text(10, 10, $"QNet self-test finished: {_passed}/{array_length(results)} passed   (ESC: back to demo)");
else draw_text(10, 10, $"QNet self-test running, stage {stage}...   (ESC: back to demo)");

var _y = 40;
for (var _i = 0; _i < array_length(results); _i++)
{
	var _result = results[_i];
	draw_set_colour(_result.ok ? c_lime : c_red);
	draw_text(10, _y, $"{_result.ok ? "PASS" : "FAIL"}  {_result.name}   {_result.detail}");
	_y += 20;
}
draw_set_colour(c_white);
