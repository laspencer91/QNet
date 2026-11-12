# QNet

_STATUS_: 2.0. Wire-compatible with [QNet-Node](https://github.com/laspencer91/QNet-Node) 2.0 (branch `v2`), so a Node server can host GameMaker clients.

QNet is a UDP networking library for GameMaker. You declare messages as plain constructors, choose how each one is delivered, and QNet handles connections, serialization, acknowledgements, resending and ordering.

## Introduction

```gml
// A message is a constructor whose arguments default to each field's type.
function PlayerMove(_x = buffer_s16, _y = buffer_s16) constructor
{
    x = _x;
    y = _y;
}

function ChatMessage(_text = buffer_string) constructor
{
    text = _text;
}
```

```gml
/// Create
network = new QNetwork({ messages: [PlayerMove, ChatMessage] });

network.OnConnected = function(_connection)
{
    _connection.Send(new ChatMessage("welcome!"));
}

network.On(ChatMessage, function(_message, _from)
{
    show_debug_message($"#{_from.id} says {_message.text}");
});

network.Host(3000);                     // or network.Join("127.0.0.1", 3000);

/// Async - Networking
network.AsyncNetworking();

/// Clean Up
network.Destroy();
```

That is the whole setup. QNet updates itself every frame, so there is no Step event to remember.

## Installation

Import the `QNet` folder from the `.yymps`, or copy these scripts into your project:

| Script | Purpose |
| --- | --- |
| `__qnet_network` | `QNetwork`, the class you use |
| `__qnet_connection` | `QNetConnection`, one per remote peer; reliability lives here |
| `__qnet_config` | Enums and tuning macros |
| `__qnet_util` | Internal helpers |
| `__q_serializer` | `QSerializer`, usable on its own for save files etc. |
| `__q_logging` | Console logging |

Requires GameMaker 2023.8 or newer. Desktop targets (UDP is not available on HTML5).

## At A Glance

### Messages

Field types are declared as constructor argument defaults:

| Declared as | Sends |
| --- | --- |
| `buffer_u8` ... `buffer_u64`, `buffer_s8` ... `buffer_s32`, `buffer_f16/f32/f64`, `buffer_bool`, `buffer_string` | that value |
| `[buffer_u8]` | an array of that type (up to 65535 items) |
| `Vec2` | a nested registered struct |
| `[Vec2]`, `[[buffer_u8]]` | arrays of structs, arrays of arrays |

Nested struct types must be in the `messages` list too. Fields are sent in alphabetical order of their names, so the order the runtime reports struct variables in never matters.

Every peer must register the **same list in the same order**. QNet hashes the list during the handshake, so a mismatched build is turned away with `QNET_REASON.SCHEMA_MISMATCH` instead of decoding garbage.

For full control, serialize a message yourself:

```gml
function Snapshot(_tick = 0) constructor
{
    MANUAL_SERIALIZATION
    tick = _tick;

    static Write = function(_buffer) { buffer_write(_buffer, buffer_u32, tick); }
    static Read  = function(_buffer) { tick = buffer_read(_buffer, buffer_u32); }
}
```

### Channels

Every send picks a channel. The default is `RELIABLE`.

| Channel | Arrives | Use for |
| --- | --- | --- |
| `QNET_CHANNEL.RELIABLE` | Always, exactly once, in send order | Events: chat, spawns, hits, game state changes |
| `QNET_CHANNEL.SEQUENCED` | Maybe; never older than one already received | State that is replaced every update: positions, aim |
| `QNET_CHANNEL.UNRELIABLE` | Maybe, in any order | Cosmetic one-offs where late is as bad as never |

```gml
connection.Send(new ChatMessage("hi"));                                  // reliable
network.SendToAll(new PlayerMove(x, y), QNET_CHANNEL.SEQUENCED);
network.SendToAll(new PlayerMove(x, y), QNET_CHANNEL.SEQUENCED, _from);  // everyone except _from (relaying)
```

Messages queued during a frame are packed together into as few packets as possible.

### Handling messages

Two styles. Use whichever reads better; `On()` wins if both exist.

```gml
// 1. A handler, bound to the instance that registered it.
network.On(ChatMessage, function(_message, _from) { array_push(chat_log, _message.text); });

// 2. An OnReceive method on the message itself.
function ChatMessage(_text = buffer_string) constructor
{
    text = _text;
    OnReceive = function(_from) { show_debug_message(text); }
}
```

### Hosting and joining

```gml
if (!network.Host(3000)) show_message("Port 3000 is in use");

network.Join("192.168.1.20", 3000);  // result arrives via OnConnected or OnConnectFailed
network.Shutdown();                  // leave / stop hosting; Host() or Join() again any time
```

- The host is always id `0`. Clients are `1 .. max_clients`. `network.local_id` is your own id.
- On a host, `network.GetConnection(id)` finds a client. On a client, `GetConnection(0)` is the host.
- `connection.Disconnect()` kicks a client (host) or leaves (client).

### Callbacks

| Callback | When |
| --- | --- |
| `OnConnected(_connection)` | A client joined (host), or the host accepted us (client) |
| `OnDisconnected(_connection, _reason)` | A connected peer is gone |
| `OnConnectFailed(_reason)` | Client only: a `Join()` did not succeed |

Guarantees: every `Join()` that returns true ends in exactly one `OnConnected` or `OnConnectFailed`, and every `OnConnected` is followed by exactly one `OnDisconnected`, including when you call `Shutdown()`. `qnet_reason_to_string(_reason)` gives readable text.

### Options

```gml
network = new QNetwork({
    messages:        [PlayerMove, ChatMessage],  // required
    max_clients:     8,     // host only
    timeout:         5,     // seconds of silence before a connection drops
    connect_timeout: 5,     // seconds Join() keeps trying
    heartbeat:       0.5,   // seconds between keep-alives when idle
});
```

Library-wide tuning (packet size, reliable window, resend floor) lives in `__qnet_config`.

### Testing on one machine

```gml
network.Simulate(120, 40, 0.15);  // 120ms +/- 40ms latency, 15% loss on what this peer sends
network.Simulate();               // off
```

Each connection exposes `rtt` (ms), `packet_loss` (0..1) and `stats` (packets, bytes, resends). `string(network)` prints a summary.

The project includes a demo room (run it with the MultiClient extension: the first window hosts, the rest join) and a self-test room (`T` in the demo) that runs two networks through 20% simulated loss and checks reliability, ordering, sequencing, full servers, schema mismatches, timeouts and disconnects.

## How it works

See [PROTOCOL.md](PROTOCOL.md) for the wire format.

**Packets.** Each packet carries a sequence number, plus the newest sequence number received from the other side and a 32-bit mask of the 32 before it. Every packet in either direction therefore acknowledges recent packets the other way, and each side learns which of its packets arrived (and the round-trip time) without sending anything extra.

**Reliable messages.** Each reliable message gets an id and stays in a send window until a packet that carried it is acknowledged. If no acknowledgement comes within `max(100ms, rtt * 1.5)`, it is packed into a later packet again. The receiver keeps messages that arrive early and releases them strictly in id order, once each. A lost packet only delays the reliable messages behind it; it never stalls unreliable traffic.

**Connections.** Joining is a four-step handshake: request, challenge, response, accept. The host does not allocate a slot until the client has echoed a random challenge, so spoofed addresses cannot fill the server. Afterwards every packet carries a session key derived from both sides' random salts.

QNet never touches GameMaker's random state, so lockstep games stay deterministic.
