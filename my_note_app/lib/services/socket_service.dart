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

    // เคลียร์ listener เดิมก่อนกันซ้ำ
    _socket!
      ..off('connect')
      ..on('connect', (_) {
        // debug ดูใน log ได้
        print('[socket] connected to $baseUrl');
      });

    if (!(_socket?.connected ?? false)) {
      _socket!.connect();
    }
  }

  /// (เดิมชื่อ joinUserRoom) แต่ฝั่ง server ของคุณใช้ event ชื่อ `register`
  /// app.js:
  ///   socket.on("register", (userId) => {
  ///     socket.join(`user:${id}`);
  ///     ...
  ///   });
  void registerUser(int userId) {
    _socket?.emit('register', userId);
  }

  // ถ้ายังมีฝั่ง server ใช้ 'notify' อยู่ก็เก็บไว้ได้
  void onNotify(void Function(dynamic data) handler) {
    _socket?.off('notify');
    _socket?.on('notify', handler);
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
