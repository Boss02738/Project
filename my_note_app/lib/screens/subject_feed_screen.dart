import 'package:flutter/material.dart';
import 'package:my_note_app/api/api_service.dart';

class SubjectFeedScreen extends StatefulWidget {
  final String subjectName;
  const SubjectFeedScreen({super.key, required this.subjectName});

  @override
  State<SubjectFeedScreen> createState() => _SubjectFeedScreenState();
}

class _SubjectFeedScreenState extends State<SubjectFeedScreen> {
  late Future<List<dynamic>> _futureFeed;

  @override
  void initState() {
    super.initState();
    _futureFeed = ApiService.getFeedBySubject(widget.subjectName);
  }

  Future<void> _reload() async {
    setState(() => _futureFeed = ApiService.getFeedBySubject(widget.subjectName));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subjectName, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _futureFeed,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('โหลดโพสต์ไม่สำเร็จ'));
          }
          final feed = snap.data ?? [];
          if (feed.isEmpty) {
            return const Center(child: Text('ยังไม่มีโพสต์ในรายวิชานี้'));
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: feed.length,
              itemBuilder: (_, i) {
                final p = feed[i];
                final avatar = (p['avatar_url'] as String?) ?? '';
                final img    = (p['image_url']  as String?) ?? '';
                final file   = (p['file_url']   as String?) ?? '';
                final name   = p['username'] as String? ?? '';
                final text   = p['text'] as String? ?? '';
                final subject= p['subject'] as String? ?? '';
                final year   = p['year_label'] as String? ?? '';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundImage: avatar.isNotEmpty
                          ? NetworkImage('${ApiService.host}$avatar')
                          : const AssetImage('assets/default_avatar.png')
                              as ImageProvider,
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(subject.isNotEmpty ? subject : 'No subject'),
                      trailing: const Icon(Icons.more_horiz),
                    ),
                    if (img.isNotEmpty)
                      AspectRatio(
                        aspectRatio: 16/9,
                        child: Image.network(
                          '${ApiService.host}$img',
                          fit: BoxFit.cover,
                        ),
                      ),
                    if (file.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.insert_drive_file, size: 18),
                            const SizedBox(width: 8),
                            Flexible(child: Text(file.split('/').last, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    if (text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(text),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(year, style: const TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
