// import 'package:socket_io_client/socket_io_client.dart' as IO;

// class SocketService {
//   static final SocketService _i = SocketService._internal();
//   factory SocketService() => _i;
//   SocketService._internal();

//   IO.Socket? _socket;

//   void connect(String baseUrl) {
//     _socket ??= IO.io(baseUrl, IO.OptionBuilder()
//         .setTransports(['websocket'])
//         .disableAutoConnect()
//         .build());
//     if (!(_socket?.connected ?? false)) _socket!.connect();
//   }

//   void joinUserRoom(int userId) {
//     _socket?.emit('join_user', {'userId': userId});
//   }

//   void onNotify(void Function(dynamic data) handler) {
//     _socket?.on('notify', handler);
//   }

//   void dispose() {
//     _socket?.dispose();
//     _socket = null;
//   }
// }

// lib/services/socket_service.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _i = SocketService._internal();
  factory SocketService() => _i;
  SocketService._internal();

  IO.Socket? _socket;

  void connect(String baseUrl) {
    _socket ??= IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );
    if (!(_socket?.connected ?? false)) _socket!.connect();
  }

  void joinUserRoom(int userId) {
    // ให้ตรงกับ server: socket.on("register", ...)
    _socket?.emit('register', userId);
  }

  void onNotify(void Function(dynamic data) handler) {
    // ให้ตรงกับ notificationController: io.to(...).emit("notification:new", item)
    _socket?.on('notification:new', handler);
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}
