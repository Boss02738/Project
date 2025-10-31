// lib/widgets/post_card.dart  (หรือไฟล์ที่คุณวาง PostCard อยู่)

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

// ถ้ามี dialog เลือกเหตุผลรายงาน
import 'package:my_note_app/widgets/report_post_dialog.dart';

/// ======================= Fullscreen Gallery =======================
class GalleryViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  final String heroPrefix;

  const GalleryViewer({
    super.key,
    required this.urls,
    required this.initialIndex,
    required this.heroPrefix,
  });

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          PhotoViewGallery.builder(
            itemCount: widget.urls.length,
            pageController: _pageController,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            builder: (context, index) {
              final url = widget.urls[index];
              final tag = '${widget.heroPrefix}_$index';
              return PhotoViewGalleryPageOptions(
                heroAttributes: PhotoViewHeroAttributes(tag: tag),
                imageProvider: NetworkImage(url),
                minScale: PhotoViewComputedScale.contained * 1.0,
                maxScale: PhotoViewComputedScale.covered * 3.0,
              );
            },
            scrollPhysics: const BouncingScrollPhysics(),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            loadingBuilder: (context, event) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 16,
                  left: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Text(
                    '${_currentIndex + 1} / ${widget.urls.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================ Post Card ============================
class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onDeleted; // callback เมื่อ archive สำเร็จ
  const PostCard({super.key, required this.post, this.onDeleted});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool isExpanded = false;
  int? _userId;
  int _likeCount = 0;
  int _commentCount = 0;
  bool _likedByMe = false;
  bool _savedByMe = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
    final m = widget.post;
    final liked = m['liked_by_me'];
    final lc = m['like_count'];
    final cc = m['comment_count'];
    if (liked is bool) _likedByMe = liked;
    if (lc is int) _likeCount = lc;
    if (cc is int) _commentCount = cc;
    if (lc == null || cc == null) _loadCounts();
    _initSaved();
  }

  Future<void> _loadUser() async {
    final sp = await SharedPreferences.getInstance();
    setState(() => _userId = sp.getInt('user_id'));
  }

  Future<void> _loadCounts() async {
    final postId = widget.post['id'] as int?;
    if (postId == null) return;
    try {
      final m = await ApiService.getCounts(postId);
      if (!mounted) return;
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
      final liked = await ApiService.toggleLike(postId: postId, userId: _userId!);
      if (!mounted) return;
      setState(() {
        _likedByMe = liked;
        _likeCount += liked ? 1 : -1;
        if (_likeCount < 0) _likeCount = 0;
      });
    } catch (_) {}
  }

  Future<void> _initSaved() async {
    final postId = widget.post['id'] as int?;
    if (postId == null) return;
    final sp = await SharedPreferences.getInstance();
    final uid = sp.getInt('user_id');
    if (uid == null) return;
    try {
      final saved = await ApiService.getSavedStatus(postId: postId, userId: uid);
      if (!mounted) return;
      setState(() => _savedByMe = saved);
    } catch (_) {}
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

  Future<void> _toggleSave() async {
    final postId = widget.post['id'] as int?;
    if (postId == null) return;
    int? uid = _userId;
    if (uid == null) {
      final sp = await SharedPreferences.getInstance();
      uid = sp.getInt('user_id');
      if (uid == null) return;
      if (mounted) setState(() => _userId = uid);
    }
    try {
      final saved = await ApiService.toggleSave(postId: postId, userId: uid);
      if (!mounted) return;
      setState(() => _savedByMe = saved);
    } catch (_) {}
  }

  void _openGallery(List<String> urls, int startIndex, int postId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GalleryViewer(
          urls: urls,
          initialIndex: startIndex,
          heroPrefix: 'post_img_$postId',
        ),
      ),
    );
  }

  void _promptPurchase() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ปลดล็อกเนื้อหา'),
        content: const Text('ซื้อโพสต์นี้เพื่อดูรูปทั้งหมดและดาวน์โหลดไฟล์แนบ'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ปิด')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ไปหน้าซื้อโพสต์…')),
              );
            },
            child: const Text('ซื้อโพสต์'),
          ),
        ],
      ),
    );
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '${diff.inSeconds} วิ.';
    if (diff.inHours < 1) return '${diff.inMinutes} นาที';
    if (diff.inDays < 1) return '${diff.inHours} ชม.';
    if (diff.inDays < 7) return '${diff.inDays} วัน';
    return '${dt.year}/${dt.month}/${dt.day}';
  }

  Future<String?> _downloadFile(String url, String fileName) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        if (Platform.isAndroid) {
          try {
            final externalDir = Directory('/sdcard/Download');
            if (!await externalDir.exists()) await externalDir.create(recursive: true);
            final publicPath = '${externalDir.path}/$fileName';
            final publicFile = File(publicPath);
            await publicFile.writeAsBytes(response.bodyBytes);
            return publicFile.path;
          } catch (_) {}
        }
        final dir = await getApplicationDocumentsDirectory();
        final filePath = '${dir.path}/$fileName';
        final file = await File(filePath).writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (e) {
      debugPrint('Download error: $e');
    }
    return null;
  }

  Future<void> _confirmAndArchive() async {
    final postId = widget.post['id'] as int?;
    if (postId == null || _userId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ลบโพสต์ (เก็บไว้ส่วนตัว)'),
        content: const Text('ย้ายโพสต์นี้ไปยังรายการลบ (สามารถกู้คืนได้ใน Settings) ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('ยืนยัน')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final success = await ApiService().archivePost(postId, _userId!);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ย้ายไปที่ Deleted แล้ว')),
        );
        widget.onDeleted?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ล้มเหลว: server ไม่ยอมรับคำสั่ง')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ล้มเหลว: $e')),
      );
    }
  }

  /// ===== ยิงรีพอร์ตตรงผ่าน HTTP (ไม่พึ่ง ApiService.reportPost) =====
  Future<void> _sendReportDirect({
    required int postId,
    required int userId,
    required String reason,
    String? details,
  }) async {
    final uri = Uri.parse('${ApiService.host}/api/reports');
    final payload = <String, dynamic>{
      'post_id': postId,
      'reporter_id': userId,
      'reason': reason,
      if ((details ?? '').trim().isNotEmpty) 'details': (details ?? '').trim(),
    };

    final r = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));

    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('HTTP ${r.statusCode}: ${r.body}');
    }
  }

  // ===== Handler ส่งรีพอร์ต =====
  Future<void> _handleReportSubmit({
    required String reason,
    String? details,
  }) async {
    final postId = widget.post['id'] as int?;
    if (postId == null) return;

    int? uid = _userId;
    if (uid == null) {
      final sp = await SharedPreferences.getInstance();
      uid = sp.getInt('user_id');
      if (mounted) setState(() => _userId = uid);
    }
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนรายงานโพสต์')),
      );
      return;
    }

    await _sendReportDirect(
      postId: postId,
      userId: uid,
      reason: reason,
      details: details,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ส่งรายงานแล้ว ขอบคุณที่ช่วยดูแลชุมชน')),
    );
  }

  // เปิด dialog เลือกเหตุผลรายงาน
  Future<void> _openReportDialog() async {
    final postId = widget.post['id'] as int?;
    if (postId == null) return;

    await showDialog<bool>(
      context: context,
      builder: (_) => ReportPostDialog(
        postId: postId,
        userId: _userId ?? -1,
        onSubmit: _handleReportSubmit,
      ),
    );
  }

  // ===== Action Sheet (เมนูสวย ๆ แทน Popup) =====
  Future<void> _openActionsSheet(bool canDelete) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // drag handle
                Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Row(
                  children: const [
                    Icon(Icons.tune, size: 18, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('การทำรายการกับโพสต์',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),

                _ActionItem(
                  icon: Icons.flag_outlined,
                  label: 'รายงานโพสต์',
                  subtitle: 'แจ้งเนื้อหาไม่เหมาะสมให้ผู้ดูแลทราบ',
                  onTap: () {
                    Navigator.pop(ctx);
                    _openReportDialog();
                  },
                ),

                if (canDelete) ...[
                  const SizedBox(height: 4),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  _ActionItem(
                    icon: Icons.delete_outline,
                    label: 'Delete post',
                    subtitle: 'ย้ายไปยังรายการลบ (กู้คืนได้ใน Settings)',
                    danger: true,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _confirmAndArchive();
                    },
                  ),
                ],
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;

    // Normalize URL (/uploads -> http)
    List<String> _fixUrls(List<String> arr) =>
        arr.map((e) => e.startsWith('http') ? e : '${ApiService.host}$e').toList();

    final avatar = (p['avatar_url'] as String?) ?? '';
    final file = (p['file_url'] as String?) ?? '';
    final fileName = file.isNotEmpty ? file.split('/').last : null;
    final name = p['username'] as String? ?? '';
    final text = p['text'] as String? ?? '';
    final subject = p['subject'] as String? ?? '';
    final year = p['year_label'] as String? ?? '';
    final created = p['created_at'] as String?;

    // images (รวม legacy)
    final List<String> images = (p['images'] as List?)?.cast<String>() ?? [];
    final legacy = p['image_url'] as String?;
    final allImagesRaw = [...images, if ((legacy ?? '').isNotEmpty && images.isEmpty) legacy!];
    final allImages = _fixUrls(allImagesRaw);

    // owner id (รองรับ author_id/user_id)
    int? ownerId;
    final rawOwner = p['author_id'] ?? p['owner_id'] ?? p['created_by'] ?? p['user_id'];
    if (rawOwner is int) {
      ownerId = rawOwner;
    } else if (rawOwner != null) {
      final parsed = int.tryParse('$rawOwner');
      if (parsed != null) ownerId = parsed;
    }

    // ===== ACCESS LOGIC =====
    final myId = _userId;
    final isOwner = (ownerId != null && myId != null && ownerId == myId);

    final priceType = (p['price_type'] ?? 'free').toString().toLowerCase().trim();
    final isPaid = priceType != 'free';

    final purchased =
        (p['purchased'] == true) ||
        (p['is_purchased'] == true) ||
        (p['purchased_by_me'] == true) ||
        (p['granted_at'] != null);

    final hasAccess = isOwner || purchased;
    final canSeeAll = !isPaid || hasAccess;
    final canDownload = !isPaid || hasAccess;

    final imagesToShow = canSeeAll ? allImages : (allImages.isNotEmpty ? [allImages.first] : <String>[]);

    final showSeeMore = text.trim().length > 80;
    final canDelete = isOwner;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -------- Header --------
          ListTile(
            leading: CircleAvatar(
              radius: 22,
              backgroundImage: avatar.isNotEmpty
                  ? NetworkImage('${ApiService.host}$avatar')
                  : const AssetImage('assets/default_avatar.png') as ImageProvider,
            ),
            title: Row(
              children: [
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
                if (year.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF4FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(year, style: const TextStyle(fontSize: 11, color: Color(0xFF335CFF))),
                  ),
              ],
            ),
            subtitle: Text(subject, overflow: TextOverflow.ellipsis),

            // ✅ ปุ่มเปิด Action Sheet
            trailing: IconButton(
              icon: const Icon(Icons.more_horiz),
              onPressed: () => _openActionsSheet(canDelete),
            ),
          ),

          // -------- Images + Lock --------
          if (imagesToShow.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Stack(
                children: [
                  _SmartImageGrid(
                    postId: p['id'] as int,
                    images: imagesToShow,
                    onTap: (i) => _openGallery(imagesToShow, i, p['id'] as int),
                  ),
                  if (!canSeeAll && allImages.length > 1)
                    const Positioned(
                      right: 8,
                      top: 8,
                      child: _LockPill(label: 'ปลดล็อกดูรูปทั้งหมด'),
                    ),
                ],
              ),
            ),

          // -------- File download (secure) --------
          if (file.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  if (!canDownload) {
                    _promptPurchase();
                    return;
                  }
                  final sp = await SharedPreferences.getInstance();
                  final uid = _userId ?? sp.getInt('user_id');
                  if (uid == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนดาวน์โหลด')),
                    );
                    return;
                  }
                  final secureUrl = ApiService.buildSecureDownloadUrl(
                    postId: (p['id'] as int),
                    viewerUserId: uid,
                  );
                  final savePath = await _downloadFile(secureUrl, fileName ?? 'downloaded_file');
                  if (savePath != null) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('ไฟล์ถูกดาวน์โหลดไปที่ $savePath')),
                    );
                    try {
                      await OpenFile.open(savePath);
                    } catch (e) {
                      debugPrint('Open file error: $e');
                    }
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ดาวน์โหลดไฟล์ไม่สำเร็จ')),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFFFBFBFB),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        canDownload ? Icons.insert_drive_file : Icons.lock,
                        size: 20,
                        color: const Color(0xFF335CFF),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fileName ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF4FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              canDownload ? Icons.download_rounded : Icons.lock,
                              size: 18,
                              color: const Color(0xFF335CFF),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              canDownload ? 'ดาวน์โหลด' : 'ปลดล็อกเพื่อดาวน์โหลด',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF335CFF)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // -------- Actions --------
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 6, top: 6),
            child: Row(children: [
              IconButton(
                icon: Icon(_likedByMe ? Icons.favorite : Icons.favorite_border),
                onPressed: _toggleLike,
              ),
              Text('$_likeCount'),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.mode_comment_outlined),
                onPressed: _openComments,
              ),
              Text('$_commentCount'),
              const Spacer(),
              IconButton(
                icon: Icon(_savedByMe ? Icons.bookmark : Icons.bookmark_border_outlined),
                onPressed: _toggleSave,
              ),
            ]),
          ),

          // -------- Text --------
          if (text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: '$name ',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    TextSpan(text: text, style: const TextStyle(color: Colors.black87))
                  ]),
                  maxLines: isExpanded ? null : 2,
                  overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                ),
                if (showSeeMore)
                  TextButton(
                    onPressed: () => setState(() => isExpanded = !isExpanded),
                    child: Text(isExpanded ? 'ย่อ' : 'ดูเพิ่มเติม'),
                  )
              ]),
            ),

          // -------- Time --------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Text(_timeAgo(created), style: const TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}

/// ======================= Smart Grid Layout =======================
class _SmartImageGrid extends StatelessWidget {
  final int postId;
  final List<String> images;
  final void Function(int index)? onTap;
  const _SmartImageGrid({required this.postId, required this.images, this.onTap});

  @override
  Widget build(BuildContext context) {
    final total = images.length;
    final showCount = total > 6 ? 6 : total;
    final remaining = total > 6 ? total - 5 : 0;

    if (showCount == 5) {
      return Column(children: [
        _RowGap(
          gap: 6,
          children: List.generate(3, (i) => _ImageTile(
                url: images[i],
                tag: 'post_img_${postId}_$i',
                onTap: () => onTap?.call(i),
              )),
        ),
        const SizedBox(height: 6),
        _RowGap(
          gap: 6,
          children: List.generate(2, (i) {
            final idx = 3 + i;
            return _ImageTile(
              url: images[idx],
              tag: 'post_img_${postId}_$idx',
              onTap: () => onTap?.call(idx),
            );
          }),
        )
      ]);
    }

    int crossAxisCount;
    if (showCount == 1)
      crossAxisCount = 1;
    else if (showCount == 2)
      crossAxisCount = 2;
    else if (showCount == 4)
      crossAxisCount = 2;
    else
      crossAxisCount = 3;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: showCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemBuilder: (_, i) {
        final isLast = total > 6 && i == 5;
        final url = images[i];
        final tag = 'post_img_${postId}_$i';
        if (isLast) {
          return Stack(fit: StackFit.expand, children: [
            _Thumb(url: url),
            Container(
              color: Colors.black45,
              alignment: Alignment.center,
              child: Text(
                '+$remaining',
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
            )
          ]);
        }
        return GestureDetector(
          onTap: () => onTap?.call(i),
          child: Hero(tag: tag, child: _Thumb(url: url)),
        );
      },
    );
  }
}

class _RowGap extends StatelessWidget {
  final double gap;
  final List<Widget> children;
  const _RowGap({required this.gap, required this.children});
  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            Expanded(child: AspectRatio(aspectRatio: 1, child: children[i])),
            if (i != children.length - 1) SizedBox(width: gap),
          ]
        ],
      );
}

class _ImageTile extends StatelessWidget {
  final String url;
  final String tag;
  final VoidCallback? onTap;
  const _ImageTile({required this.url, required this.tag, this.onTap});
  @override
  Widget build(BuildContext context) =>
      GestureDetector(onTap: onTap, child: Hero(tag: tag, child: _Thumb(url: url)));
}

class _Thumb extends StatelessWidget {
  final String url;
  const _Thumb({required this.url});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 32),
        ),
      );
}

/// ------------------------- Lock Pill -------------------------
class _LockPill extends StatelessWidget {
  final String label;
  const _LockPill({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

/// ====================== BottomSheet: Comments ======================
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
      await ApiService.addComment(postId: widget.postId, userId: _userId!, text: t);
      _controller.clear();
      widget.onCommentAdded();
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ส่งคอมเมนต์ไม่สำเร็จ')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              const SizedBox(height: 8),
              const Text('ความคิดเห็น', style: TextStyle(fontWeight: FontWeight.bold)),
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

                          String timeLabel = '';
                          if (createdAt.toString().isNotEmpty) {
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
                                Text(timeLabel, style: const TextStyle(color: Colors.grey, fontSize: 12)),
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

/// ========= ชิ้นส่วน UI ของแผ่นล่าง =========
class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool danger;
  final VoidCallback onTap;

  const _ActionItem({
    Key? key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.danger = false,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red : const Color(0xFF1F2937); // slate-800
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment:
                subtitle == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: danger ? Colors.red.withOpacity(.08) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: color,
                        )),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF6B7280), // slate-500
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}
