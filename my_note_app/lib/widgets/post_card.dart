import 'package:flutter/material.dart';
import 'package:my_note_app/api/api_service.dart';

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  const PostCard({super.key, required this.post});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool isExpanded = false;

  String _timeAgo(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    DateTime dt;
    try { dt = DateTime.parse(iso).toLocal(); } catch (_) { return ''; }
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
    final avatar  = (p['avatar_url'] as String?) ?? '';
    final img     = (p['image_url']  as String?) ?? '';
    final file    = (p['file_url']   as String?) ?? '';
    final name    = p['username'] as String? ?? '';
    final text    = p['text'] as String? ?? '';
    final subject = p['subject'] as String? ?? '';
    final year    = p['year_label'] as String? ?? '';
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
                  : const AssetImage('assets/default_avatar.png') as ImageProvider,
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF4FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      year,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF335CFF)),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

          // ---------- Text + See more ----------
          if (text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
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
                    overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
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
