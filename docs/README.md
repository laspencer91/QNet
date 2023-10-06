# QSignals GameMaker Library

---

The QSignals library simplifies game event programming in GameMaker Studio 2.3 by eliminating excessive [coupling](https://w.wiki/7Yz6). This documentation will guide you through the usage of the library and provide examples to help you get started.

## Introduction

QSignals is a lightweight library designed to streamline event-driven programming in your GameMaker projects. It allows you to emit signals and create listeners for those specific signals. There are unlimited ways to put this library to use, so get creative! 

> See the [Examples](#examples) for some cool ideas.

> See the [Video](https://youtu.be/c0b2Gjw_Hw8) for a quick intro of the library.

## Installation

1. Add the asset to your library: [GameMaker Marketplace](https://marketplace.gamemaker.io/assets/11836/qsignals)
2. Import the library into your GameMaker project.
    - (In GameMaker) -> _Marketplace_ -> _My Library_ -> _QSignals_ -> _Import_ -> _Add All_ -> **Import**
3. Ensure that a folder named QSignals was added to your project. You are ready to go!

## At A Glance

> **Three Functions** to change your game development experience! ***The work is performed behind the scenes.***

#### **Single Parameter**

```javascript
qsignal_emit("player_death", player_score);

qsignal_listen("player_death", function(_score) {
    // Your code here
    show_debug_message("Player died! Score: " + string(score));
});

qsignal_stop_listening("player_death");
```

#### **Multiple Parameters**

```javascript
qsignal_emit("player_death", { score: player_score, cause: "spike" });

qsignal_listen("player_death", function(_payload) {
    // Your code here
    var _score = _payload.score;
    var _cause = _payload.cause;
    show_debug_message("Player died! Score: " + _score);
    show_debug_message("He died from " + _cause);
});

qsignal_stop_listening("player_death");
```