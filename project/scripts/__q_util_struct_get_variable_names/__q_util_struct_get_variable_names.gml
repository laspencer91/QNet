///@desc Ommits method names. Gets property field names only.
///@param {Struct} _struct
function struct_get_variable_names(_struct) 
{
	var _field_names = variable_struct_get_names(_struct);

	var _filtered_array = [];
	for (var _i = 0; _i < array_length(_field_names); _i++) 
	{
		var _type = typeof(variable_struct_get(_struct, _field_names[_i]));
		if (_type != "method") 
		{
			array_push(_filtered_array, _field_names[_i]);
		}
	}
	return _filtered_array;
}