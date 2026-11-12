/// @description HUD

draw_set_colour(c_white);
draw_text(10, 10, string(network));
draw_text(10, 160, $"Reliable counters received: {counter_received}   order errors: {counter_errors}");

var _y = 200;
for (var _i = 0; _i < array_length(log); _i++)
{
	draw_text(10, _y, log[_i]);
	_y += 18;
}

draw_text(10, room_height - 30, "ARROWS move   SPACE 100 reliable msgs   C chat   L toggle lag/loss   D disconnect   R host/rejoin   T self-test");
