// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information
function QNetworkReliableOrderedHandler(){

	__inflight_ack_packets = ds_map_create();

	function HandleIncomingReliableSequenced(_incoming_ack, _incoming_ack_bits) {
		for (var _i = 0; _i < 16; _i++)
		{
			var _acked = _incoming_ack_bits << _i;
			if (_acked)
			{
				// Recognize Ack
				__inflight_ack_packets[? _acked] = undefined;
			}
			else if (_i % 2 == 0)
			{
				// Handle Resend?
				var _ack_number = _incoming_ack - _i;
				var _packet = __inflight_ack_packets[? _ack_number];
				var _buffer = __serializer.Serialize(_packet, { 
					delivery_type: QNET_DELIVERY_TYPE.RELIABLE_SEQENCED, 
					sequence: _ack_number
				});
				network_send_udp(__socket, ip, port, _buffer, buffer_get_size(_buffer));	
			}
		}	
	}
}