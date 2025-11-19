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

  IO.Socket? get socket => _socket; // เผื่ออยากใช้ socket ตรง ๆ ที่หน้าอื่น

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

  // ถ้ายังมีฝั่ง server ใช้ 'notify' อยู่ก็เก็บไว้ได้
  void onNotify(void Function(dynamic data) handler) {
    // ให้ตรงกับ notificationController: io.to(...).emit("notification:new", item)
    _socket?.on('notification:new', handler);
  }

  /// ฟัง event ตอนโดนเชิญเข้าห้องโน้ต
  /// app.js / boardTopics.js ฝั่ง server จะ emit:
  ///   io.to(`user:${targetId}`).emit("board_invited", {
  ///      boardId, role: "editor", inviterId, ...
  ///   });
  void onBoardInvited(void Function(Map<String, dynamic> data) handler) {
    _socket?.off('board_invited'); // กันซ้ำ
    _socket?.on('board_invited', (data) {
      try {
        if (data is Map) {
          handler(Map<String, dynamic>.from(data as Map));
        } else {
          handler({'raw': data});
        }
      } catch (e) {
        print('[socket] board_invited parse error: $e');
      }
    });
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}
