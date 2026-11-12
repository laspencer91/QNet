/// @description Players

var _names = variable_struct_get_names(players);
for (var _i = 0; _i < array_length(_names); _i++)
{
	var _player = players[$ _names[_i]];
	draw_set_colour(c_orange);
	draw_rectangle(_player.px - 12, _player.py - 12, _player.px + 12, _player.py + 12, false);
	draw_set_colour(c_white);
	draw_text(_player.px - 8, _player.py - 32, "#" + _names[_i]);
}

draw_set_colour(c_lime);
draw_rectangle(my_x - 12, my_y - 12, my_x + 12, my_y + 12, false);
draw_set_colour(c_white);
draw_text(my_x - 16, my_y - 32, "you");
