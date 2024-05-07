# QNET GameMaker Library

_STATUS_: In Progress

---

QNet is a UDP GameMaker library that handles connections between clients and data serialization. It can be used with QNET - Node if you want to use Node for a backend. The data serialization is easy to setup so you do not need to worry about writing and reading from buffers yourself. It supports nested serializable types and arrays.

## At A Glance


#### **Example**

```javascript
function SerializableFunction1(_name = buffer_u8) constructor {
  name = _name;
  function OnRecieve() {
    ... do something with name
  }
}
function SerializableFunction1(_array_of_x_pos = [buffer_u8], _array_of_y_pos = [_position_y]) constructor {
  array_of_x_pos = _array_of_x_pos;
  array_of_y_pos = _array_of_y_pos;
  function OnReceive() {
    for (var i = 0; i < array_length(array_of_x_pos); i++) {
      update_position(array_of_x_pos[i], array_of_y_pos[i]);
    }
  }
}

var network_manager = new QNetManager([SerializableFunction1, SerializableFunction2]);
network_manager.start(3000);
```
