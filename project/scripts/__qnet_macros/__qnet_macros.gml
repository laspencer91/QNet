// Used for GMNet serialization
#macro CUSTOM_BUFFER_SERIALIZER 15

// Each serialized buffer includes an identifier as its first piece of data.
// Configuring this can open space for more identifiers. DEFAULT = buffer_u8 (255 MAXIMUM serializable_ids)
#macro SERIALIZABLE_ID_BUFFER_TYPE buffer_u8


// Manual Serializer Macro
#macro ____NOOP_FUNC_READ     function Read() { show_message($"[ERROR] Read(_buffer) unimplemented for manually serializer {instanceof(self)}")}
#macro ____NOOP_FUNC_WRITE    function Write() { show_message($"[ERROR] Write(_buffer) unimplemented for manually serializer {instanceof(self)}")}
#macro ____NOOP_FUNC_RECEIVE  function OnReceive() { show_message($"[ERROR] Receive(_id) unimplemented for manually serializer {instanceof(self)}")}
#macro MANUAL_SERIALIZATION static __use_manual_serialization = true