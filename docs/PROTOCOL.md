# QNet wire protocol, version 2

This is the contract between QNet for GameMaker and any other implementation (QNet-Node). All integers are little-endian, as GameMaker's buffers write them.

## Packet header

Every packet starts with:

| Field | Type | Notes |
| --- | --- | --- |
| protocol_id | u16 | `0x514E` ("QN"). Anything else is ignored. |
| type | u8 | One of the packet types below. |

Packets from unknown addresses, with a wrong session or with a size too small for their type, are dropped silently.

## Packet types

| Value | Name | Direction | Body after the header |
| --- | --- | --- | --- |
| 1 | CONNECT_REQUEST | client to host | u32 schema_hash, u32 client_salt |
| 2 | CHALLENGE | host to client | u32 client_salt, u32 server_salt |
| 3 | CHALLENGE_RESPONSE | client to host | u32 session |
| 4 | ACCEPTED | host to client | u32 session, u16 assigned_id |
| 5 | DENIED | host to client | u32 client_salt, u8 reason (4 = SERVER_FULL, 5 = SCHEMA_MISMATCH) |
| 6 | PAYLOAD | both | see below |
| 7 | DISCONNECT | both | u32 session |

`session = client_salt XOR server_salt`. Salts are random u32 values.

### Handshake

1. The client sends CONNECT_REQUEST every 200ms.
2. The host checks the schema hash (DENIED 5 on mismatch) and for a free slot (DENIED 4 if full). It records `{client_salt, server_salt}` for that address as pending, without allocating a slot, and replies with CHALLENGE. Repeated requests with the same client_salt get the same challenge.
3. The client, on a CHALLENGE that echoes its own salt, computes the session and sends CHALLENGE_RESPONSE every 200ms. It uses the address the challenge came from from now on.
4. The host, on a CHALLENGE_RESPONSE whose session matches the pending entry, allocates the lowest free id (1..max_clients), creates the connection and sends ACCEPTED. If the address is already connected with that session (ACCEPTED was lost), it sends ACCEPTED again.
5. The client, on ACCEPTED with its session, is connected, and its local id is assigned_id.

The client gives up after `connect_timeout`. The host forgets pending entries after `connect_timeout`.

DISCONNECT is sent three times, best effort. Either side also drops a connection after `timeout` with no valid packet.

## PAYLOAD

| Field | Type | Notes |
| --- | --- | --- |
| session | u32 | Must match the connection. |
| seq | u16 | Packet sequence number, +1 per packet sent, wraps at 65536. |
| ack | u16 | Newest seq received from the other side. 65535 with ack_bits 0 if nothing has been received yet. |
| ack_bits | u32 | Bit n (0-based) set means seq `ack - 1 - n` was received. |
| messages | ... | Repeated until the end of the packet. |

Each message:

| Field | Type | Notes |
| --- | --- | --- |
| channel | u8 | 0 UNRELIABLE, 1 SEQUENCED, 2 RELIABLE |
| channel_seq | u16 | Only for SEQUENCED (counter) and RELIABLE (message id). Absent for UNRELIABLE. |
| length | u16 | Bytes in the body. |
| body | bytes | u8 message type id, then the fields. |

Sequence comparison: `a` is newer than `b` if `(a > b and a - b <= 32768) or (a < b and b - a > 32768)`.

### Receiving rules

- A packet whose seq was already received, or that is 256 or more behind the newest one, is dropped.
- For each seq acknowledged by `ack` and `ack_bits`, every reliable message id carried in that packet is acknowledged.
- SEQUENCED: deliver only if channel_seq is newer than the newest delivered so far.
- RELIABLE: accept ids within 256 ahead of the next expected id, buffer them, and deliver in id order, once each. Ids behind the next expected id are duplicates and are dropped (the packet is still acknowledged).

### Sending rules

- At most 256 reliable messages are unacknowledged at once; later ones wait in order.
- An unacknowledged reliable message is resent after `max(100ms, rtt * 1.5)`.
- Messages are packed into packets of up to 1200 bytes. A single larger message goes in a packet of its own.
- With nothing to send, a packet with no messages goes out 33ms after receiving something (to acknowledge it), and at least every `heartbeat`.

## Message bodies

`body = u8 type_id, fields...`. The type id is the message's index in the registered list.

Fields are written in **ascending order of field name** (plain character-code comparison):

| Declared type | Encoding |
| --- | --- |
| buffer_u8, s8, u16, s16, u32, s32, u64, f16, f32, f64, bool | GameMaker buffer encoding, little-endian. bool is 1 byte. |
| buffer_string | UTF-8 bytes, then a 0 byte. |
| [T] | u16 count, then count values of T. |
| Struct type | Its fields, recursively, with no type id. |
| MANUAL_SERIALIZATION | Whatever the message's Write() produces. |

## Schema hash

The schema hash is the first 8 hex digits of the MD5 of a string, read as a u32:

```
"qnet2" + for each registered type, in order:
    "|" + Name + ":" + ( "manual" | for each field in name order: field + "=" + typeString + "," )
```

`typeString` is one of `u8 s8 u16 s16 u32 s32 u64 f16 f32 f64 bool string`, `[` + inner + `]` for arrays, or the struct's name.

Example: `qnet2|PlayerState:player_id=u8,px=s16,py=s16,|Snapshot:manual`
