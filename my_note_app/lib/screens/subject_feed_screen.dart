import 'package:flutter/material.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/widgets/post_card.dart';

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
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: feed.length,
              itemBuilder: (_, i) {
                final p = feed[i];
                return PostCard(post: p);
              },
            ),
          );
        },
      ),
    );
  }
}
