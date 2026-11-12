/// @description Every network sees every event and ignores the ones for other sockets.
for (var _i = 0; _i < array_length(nets); _i++) nets[_i].AsyncNetworking();
