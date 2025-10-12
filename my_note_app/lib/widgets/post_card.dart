import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_note_app/api/api_service.dart';

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  const PostCard({super.key, required this.post});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool isExpanded = false;
  int? _userId;

  int _likeCount = 0;
  int _commentCount = 0;
  bool _likedByMe = false;

  @override
  void initState() {
    super.initState();
    _loadUser();

    // ดึงสถานะจาก payload ที่ backend ส่งมา (ถ้ามี)
    final m = widget.post;
    final liked = m['liked_by_me'];
    final lc = m['like_count'];
    final cc = m['comment_count'];

    if (liked is bool) _likedByMe = liked;
    if (lc is int) _likeCount = lc;
    if (cc is int) _commentCount = cc;

    // เผื่อ payload เก่ายังไม่มี count/liked_by_me -> โหลดซ้ำแบบปลอดภัย
    if (lc == null || cc == null) {
      _loadCounts();
    }
  }

  Future<void> _loadUser() async {
    final sp = await SharedPreferences.getInstance();
    setState(() => _userId = sp.getInt('user_id'));
  }

  Future<void> _loadCounts() async {
    final postId = widget.post['id'] as int?; // ต้องมี id ใน feed
    if (postId == null) return;
    try {
      final m = await ApiService.getCounts(postId);
      setState(() {
        _likeCount = (m['like_count'] as int?) ?? 0;
        _commentCount = (m['comment_count'] as int?) ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    final postId = widget.post['id'] as int?;
    if (postId == null || _userId == null) return;
    try {
      final liked = await ApiService.toggleLike(
        postId: postId,
        userId: _userId!,
      );
      setState(() {
        _likedByMe = liked;
        _likeCount += liked ? 1 : -1;
        if (_likeCount < 0) _likeCount = 0;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กดไลก์ไม่สำเร็จ')));
    }
  }

  Future<void> _openComments() async {
    final postId = widget.post['id'] as int?;
    if (postId == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CommentsSheet(
        postId: postId,
        onCommentAdded: () {
          setState(() => _commentCount++);
        },
      ),
    );
  }

  String _timeAgo(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    DateTime dt;
    try {
      dt = DateTime.parse(iso).toLocal();
    } catch (_) {
      return '';
    }
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds} วิ.';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาที';
    if (diff.inHours < 24) return '${diff.inHours} ชม.';
    if (diff.inDays < 7) return '${diff.inDays} วัน';
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}/$m/$d';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final avatar = (p['avatar_url'] as String?) ?? '';
    final img = (p['image_url'] as String?) ?? '';
    final file = (p['file_url'] as String?) ?? '';
    final name = p['username'] as String? ?? '';
    final text = p['text'] as String? ?? '';
    final subject = p['subject'] as String? ?? '';
    final year = p['year_label'] as String? ?? '';
    final created = p['created_at'] as String?;
    final showSeeMore = text.trim().length > 80;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------- Header ----------
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: CircleAvatar(
              radius: 22,
              backgroundImage: avatar.isNotEmpty
                  ? NetworkImage('${ApiService.host}$avatar')
                  : const AssetImage('assets/default_avatar.png')
                        as ImageProvider,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                if (year.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF4FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      year,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF335CFF),
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              subject.isNotEmpty ? subject : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.more_horiz),
          ),

          // ---------- Image ----------
          if (img.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  height: 220,
                  color: const Color(0xFFEFEFEF),
                  child: Image.network(
                    '${ApiService.host}$img',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),

          // ---------- File ----------
          if (file.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFFFBFBFB),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        file.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.download_rounded),
                  ],
                ),
              ),
            ),

          // ---------- Actions row ----------
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 6, top: 6),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _likedByMe ? Icons.favorite : Icons.favorite_border,
                  ),
                  onPressed: _toggleLike,
                ),
                Text('$_likeCount'),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.mode_comment_outlined),
                  onPressed: _openComments,
                ),
                Text('$_commentCount'),
              ],
            ),
          ),

          // ---------- Text + See more ----------
          if (text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$name ',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        TextSpan(
                          text: text,
                          style: const TextStyle(color: Colors.black87),
                        ),
                      ],
                    ),
                    maxLines: isExpanded ? null : 2,
                    overflow: isExpanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                  ),
                  if (showSeeMore)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => setState(() => isExpanded = !isExpanded),
                      child: Text(isExpanded ? 'ย่อ' : 'ดูเพิ่มเติม'),
                    ),
                ],
              ),
            ),

          // ---------- Time ----------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Text(
              _timeAgo(created),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  final int postId;
  final VoidCallback onCommentAdded;
  const _CommentsSheet({required this.postId, required this.onCommentAdded});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  List<dynamic> _items = [];
  bool _loading = true;
  int? _userId;

  @override
  void initState() {
    super.initState();
    _loadUserThenComments();
  }

  Future<void> _loadUserThenComments() async {
    final sp = await SharedPreferences.getInstance();
    _userId = sp.getInt('user_id');
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      _items = await ApiService.getComments(widget.postId);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final t = _controller.text.trim();
    if (t.isEmpty || _userId == null) return;
    try {
      await ApiService.addComment(
        postId: widget.postId,
        userId: _userId!,
        text: t,
      );
      _controller.clear();
      widget.onCommentAdded();
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ส่งคอมเมนต์ไม่สำเร็จ')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              const SizedBox(height: 8),
              const Text(
                'ความคิดเห็น',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
  final c = _items[i];
  final name = c['username'] ?? '';
  final avatar = c['avatar_url'] ?? '';
  final text = c['text'] ?? '';
  final createdAt = c['created_at'] ?? '';

  // แปลงเวลาให้เป็น readable format
  String timeLabel = '';
  if (createdAt.isNotEmpty) {
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) {
        timeLabel = '${diff.inSeconds} วิ.';
      } else if (diff.inMinutes < 60) {
        timeLabel = '${diff.inMinutes} นาที';
      } else if (diff.inHours < 24) {
        timeLabel = '${diff.inHours} ชม.';
      } else if (diff.inDays < 7) {
        timeLabel = '${diff.inDays} วัน';
      } else {
        timeLabel = '${dt.day}/${dt.month}/${dt.year}';
      }
    } catch (_) {}
  }

  return ListTile(
    leading: CircleAvatar(
      backgroundImage: avatar.toString().isNotEmpty
          ? NetworkImage('${ApiService.host}$avatar')
          : const AssetImage('assets/default_avatar.png') as ImageProvider,
    ),
    title: Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          timeLabel,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    ),
    subtitle: Text(text),
  );
},
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'เพิ่มความคิดเห็น...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.send), onPressed: _send),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
