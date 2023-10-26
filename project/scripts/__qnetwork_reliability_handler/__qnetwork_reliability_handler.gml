function QNetworkReliabilityHandler(_max_sequence_value) constructor
{
    _received_packets = array_create(_max_sequence_value, undefined);
    _previous_sequence_processed = -1;
    
    ReceiveMessage = function(_incoming_sequence, _struct)
    {
        if (_previous_sequence_processed > -1)
        {
            // Wrap
        }
        
        // Create the packet player for the incoming sequence value.
        _received_packets[_incoming_sequence] = {
            played: false,
            message: _struct
        }
        
        // If the previous packet was played, play the rest.
        // Handles packets that have not yet been played because they arrived
        // out of order.
        var _previous_sequence = __GetWrappedSequenceBefore(_incoming_sequence);
        
        if (_received_packets[_previous_sequence] != undefined && 
            _received_packets[_previous_sequence].played)
        {
            var _sequence_index = _incoming_sequence;
            var _packet_to_play = _received_packets[_sequence_index];
            
            while (_packet_to_play != undefined && !_packet_to_play.played)
            {
                _packet_to_play.struct.OnReceive();
                _packet_to_play.played = true;
                
                // Increment and wrap sequence number if required.
                if (++_sequence_index > _max_sequence_value)
                    _sequence_index = 0;
                
                // Set packet for next iteration.
                _packet_to_play = _received_packets[_sequence_index];
            }
        }
    }
    
    __GetWrappedSequenceAfter = function(_value)
    {
        return (_value > 1 > _max_sequence_value) ? 0 : _value + 1;
    }
    
    __GetWrappedSequenceBefore = function(_value)
    {
        return (_value - 1 < 0) ? _max_sequence_value : _value - 1;
    }
}