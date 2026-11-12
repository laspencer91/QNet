/*******************************************************************************
*  QNET CONFIG
*
*  Library-wide settings and the public enums. Per-network settings (max clients,
*  timeouts, heartbeat) are passed to new QNetwork({ ... }) instead.
*******************************************************************************/

// ---- Wire protocol --------------------------------------------------------------
// Builds with a different protocol id or version cannot talk to each other. The version
// is also folded into the schema hash that is checked during the handshake.
#macro QNET_PROTOCOL_ID           0x514E   // "QN"
#macro QNET_PROTOCOL_VERSION      2

// ---- Tuning ---------------------------------------------------------------------
// QNet packs queued messages into packets up to this size. 1200 bytes stays under the
// MTU of nearly every real network path. A single message larger than this is still
// sent, alone in its own packet, but it is more likely to be lost.
#macro QNET_MAX_PACKET_SIZE       1200

// Reliable messages that can be in flight (sent, not yet acknowledged) per connection. A power of two.
// Anything sent beyond this waits in a backlog until earlier messages are acknowledged.
#macro QNET_RELIABLE_WINDOW       256

// Lower bound on how long QNet waits for an acknowledgement before resending a reliable
// message. The real interval is max(this, rtt * 1.5).
#macro QNET_MIN_RESEND_MS         100

// How often handshake packets are retried while joining.
#macro QNET_HANDSHAKE_RETRY_MS    200

// When a peer has sent us packets and we have nothing to send back, a bare
// acknowledgement goes out after this long.
#macro QNET_ACK_DELAY_MS          33

// Maximum half-open join attempts a host tracks at once.
#macro QNET_MAX_PENDING           64

// Size of the per-connection packet history used for acknowledgements. A power of two, > 32.
#macro QNET_SEQUENCE_RING         256

// ---- Public enums ---------------------------------------------------------------

/// How a message is delivered.
enum QNET_CHANNEL
{
	// Fire and forget. May be lost or arrive out of order. Never duplicated.
	UNRELIABLE,
	// May be lost, but never arrives older than one already received. Use for state that is
	// superseded every update, like positions.
	SEQUENCED,
	// Always arrives, exactly once, in the order it was sent. Use for events: chat, spawns, hits.
	RELIABLE,
}

/// What a QNetwork is currently doing.
enum QNET_ROLE
{
	OFFLINE,
	HOST,
	CLIENT,
}

/// Lifecycle of a QNetConnection.
enum QNET_STATE
{
	DISCONNECTED,
	// Client only: sending connection requests.
	CONNECTING,
	// Client only: the host answered with a challenge, proving our address is real.
	CHALLENGED,
	CONNECTED,
}

/// Why a connection ended or a Join() failed. Use qnet_reason_to_string() for display.
enum QNET_REASON
{
	NONE,
	// You called Disconnect() or Shutdown().
	LOCAL,
	// The other side closed the connection (a client left, or the host kicked you or shut down).
	REMOTE,
	// Nothing was heard from the peer for `timeout` seconds.
	TIMEOUT,
	// Join() only: the host has no free slots.
	SERVER_FULL,
	// Join() only: the host registered a different list of messages, or runs a different QNet version.
	SCHEMA_MISMATCH,
	// Join() only: no answer from the host within `connect_timeout` seconds.
	CONNECT_TIMEOUT,
}

// ---- Internal -------------------------------------------------------------------
enum __QNET_PACKET
{
	CONNECT_REQUEST = 1,
	CHALLENGE,
	CHALLENGE_RESPONSE,
	ACCEPTED,
	DENIED,
	PAYLOAD,
	DISCONNECT,
}
