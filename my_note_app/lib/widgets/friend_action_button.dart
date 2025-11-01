// lib/widgets/friend_action_button.dart
import 'package:flutter/material.dart';
import 'package:my_note_app/api/api_service.dart'; // ให้ตรง path ของคุณ

class FriendActionButton extends StatefulWidget {
  final int meId;       // user ปัจจุบัน
  final int otherId;    // โปรไฟล์ที่กำลังดู

  const FriendActionButton({
    super.key,
    required this.meId,
    required this.otherId,
  });

  @override
  State<FriendActionButton> createState() => _FriendActionButtonState();
}

class _FriendActionButtonState extends State<FriendActionButton> {
  String _status = 'none'; // none | pending_out | pending_in | friends
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.meId == widget.otherId) {
      setState(() => _status = 'self');
      return;
    }
    try {
      final s = await ApiService.getFriendStatus(
        userId: widget.meId,
        otherUserId: widget.otherId,
      ); // <-- ใช้ named params
      setState(() => _status = s);
    } catch (_) {
      // จะโชว์ error ก็ได้
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ApiService.sendFriendRequest(
        fromUserId: widget.meId,
        toUserId: widget.otherId,
      ); // <-- ใช้ named params
      setState(() => _status = 'pending_out');
      _toast('ส่งคำขอเป็นเพื่อนแล้ว');
    } catch (e) {
      _toast('ส่งคำขอไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ApiService.cancelFriendRequest(
        userId: widget.meId,
        otherUserId: widget.otherId,
      );
      setState(() => _status = 'none');
      _toast('ยกเลิกคำขอแล้ว');
    } catch (e) {
      _toast('ยกเลิกไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ApiService.respondFriendRequest(
        userId: widget.meId,
        otherUserId: widget.otherId,
        action: 'accept',
      );
      setState(() => _status = 'friends');
      _toast('ยอมรับเป็นเพื่อนแล้ว');
    } catch (e) {
      _toast('ยอมรับไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ApiService.respondFriendRequest(
        userId: widget.meId,
        otherUserId: widget.otherId,
        action: 'reject',
      );
      setState(() => _status = 'none');
      _toast('ปฏิเสธคำขอแล้ว');
    } catch (e) {
      _toast('ปฏิเสธไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unfriend() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ApiService.unfriend(
        userId: widget.meId,
        otherUserId: widget.otherId,
      );
      setState(() => _status = 'none');
      _toast('เลิกเป็นเพื่อนแล้ว');
    } catch (e) {
      _toast('เลิกเป็นเพื่อนไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status == 'self') return const SizedBox.shrink();

    switch (_status) {
      case 'friends':
        return OutlinedButton.icon(
          onPressed: _busy ? null : _unfriend,
          icon: const Icon(Icons.check),
          label: Text(_busy ? 'กำลังดำเนินการ...' : 'เพื่อนกันแล้ว • เลิกเป็นเพื่อน'),
        );
      case 'pending_out':
        return OutlinedButton.icon(
          onPressed: _busy ? null : _cancel,
          icon: const Icon(Icons.hourglass_top),
          label: Text(_busy ? 'กำลังดำเนินการ...' : 'ส่งคำขอแล้ว • ยกเลิก'),
        );
      case 'pending_in':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: _busy ? null : _accept,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(_busy ? '...' : 'ยอมรับ'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy ? null : _reject,
              child: Text(_busy ? '...' : 'ปฏิเสธ'),
            ),
          ],
        );
      default: // none
        return ElevatedButton.icon(
          onPressed: _busy ? null : _send,
          icon: const Icon(Icons.person_add),
          label: Text(_busy ? 'กำลังส่ง...' : 'เพิ่มเพื่อน'),
        );
    }
  }
}
