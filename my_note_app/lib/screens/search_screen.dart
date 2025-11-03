import 'dart:async';
import 'package:flutter/material.dart';
import 'package:my_note_app/screens/documents_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/screens/home_screen.dart';
import 'package:my_note_app/screens/NewPost.dart';
import 'package:my_note_app/screens/subject_feed_screen.dart';
import 'package:my_note_app/screens/profile_screen.dart'; // ✅ เพิ่มตรงนี้
import 'package:my_note_app/widgets/app_bottom_nav_bar.dart'; 

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _debouncer = _Debouncer(const Duration(milliseconds: 350));
  bool _loading = false;

  SearchFilter _filter = SearchFilter.all;
  int? _userId;
  String get _recentKey => 'recent_search_${_userId ?? "guest"}';

  List<String> _recent = [];
  List<dynamic> _userResults = [];
  List<String> _subjectResults = [];

  final List<String> _years = const [
    'ปี 1',
    'ปี 2',
    'ปี 3',
    'ปี 4',
    'วิชาเฉพาะเลือก',
  ];
  String _selectedYear = 'ปี 1';

  @override
  void initState() {
    super.initState();
    _initUserThenLoadRecent();
  }

  Future<void> _initUserThenLoadRecent() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _userId = sp.getInt('user_id');
    });
    await _loadRecent();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final sp = await SharedPreferences.getInstance();
    setState(() => _recent = sp.getStringList(_recentKey) ?? []);
  }

  Future<void> _saveRecent(String q) async {
    final text = q.trim();
    if (text.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    final list = [..._recent];

    list.removeWhere((e) => e.toLowerCase() == text.toLowerCase());
    list.insert(0, text);
    if (list.length > 10) list.removeRange(10, list.length);

    await sp.setStringList(_recentKey, list);
    if (mounted) setState(() => _recent = list);
  }

  Future<void> _clearRecent() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_recentKey);
    if (mounted) setState(() => _recent = []);
  }

  Future<void> _removeRecentItem(String q) async {
    final sp = await SharedPreferences.getInstance();
    final list = [..._recent]
      ..removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    await sp.setStringList(_recentKey, list);
    if (mounted) setState(() => _recent = list);
  }

  Future<void> _search(String q) async {
    final term = q.trim();
    if (term.isEmpty) {
      setState(() {
        _userResults = [];
        _subjectResults = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      if (_filter == SearchFilter.users || _filter == SearchFilter.all) {
        _userResults = await ApiService.searchUsers(term);
      } else {
        _userResults = [];
      }

      if (_filter == SearchFilter.subjects || _filter == SearchFilter.all) {
        _subjectResults = await ApiService.searchSubjects(term);
      } else {
        _subjectResults = [];
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ค้นหาไม่สำเร็จ')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String q) {
    _debouncer.run(() => _search(q));
  }

  void _onSubmit(String q) async {
    await _saveRecent(q);
    _search(q);
  }

  Future<void> _openSubjectPicker() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _SubjectPickerSheet(
          years: _years,
          initialYear: _selectedYear,
          onYearChanged: (y) => _selectedYear = y,
          onSubjectTap: (subject) async {
            await _saveRecent(subject);
            if (!mounted) return;
            Navigator.pop(ctx);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SubjectFeedScreen(subjectName: subject),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            onChanged: _onQueryChanged,
            onSubmitted: _onSubmit,
            decoration: InputDecoration(
              hintText: 'ค้นหาผู้ใช้หรือรายวิชา',
              prefixIcon: const Icon(Icons.search),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'เลือกวิชาตามปี',
          onPressed: _openSubjectPicker,
          icon: const Icon(Icons.tune_rounded),
        ),
        PopupMenuButton<SearchFilter>(
          tooltip: 'โหมดค้นหา',
          icon: const Icon(Icons.filter_list_alt),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (v) {
            setState(() => _filter = v);
            _search(_controller.text);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: SearchFilter.all, child: Text('All')),
            PopupMenuItem(value: SearchFilter.users, child: Text('Users')),
            PopupMenuItem(
              value: SearchFilter.subjects,
              child: Text('Subjects'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecent() {
    if (_recent.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            const Text(
              'Recent Search',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _clearRecent,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('ลบประวัติทั้งหมด'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ..._recent.map((q) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                const Icon(Icons.history, size: 20, color: Colors.black54),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      _controller.text = q;
                      _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: _controller.text.length),
                      );
                      await _saveRecent(q);
                      _search(q);
                    },
                    child: Text(
                      q,
                      style: const TextStyle(fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                  splashRadius: 20,
                  padding: EdgeInsets.zero,
                  onPressed: () => _removeRecentItem(q),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildResults() {
    if (_loading)
      return const Expanded(child: Center(child: CircularProgressIndicator()));

    final hasUser = _userResults.isNotEmpty;
    final hasSubject = _subjectResults.isNotEmpty;

    if (!hasUser && !hasSubject) {
      if (_controller.text.trim().isEmpty) {
        return Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8),
            child: _buildRecent(),
          ),
        );
      }
      return const Expanded(child: Center(child: Text('ไม่พบผลลัพธ์')));
    }

    return Expanded(
      child: ListView(
        children: [
          if (hasUser) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text(
                'Users',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ..._userResults.map((u) {
              final username = u['username'] as String? ?? '';
              final avatar = u['avatar_url'] as String? ?? '';
              // ✅ ดึง id_user แบบปลอดภัย
              final int? targetUserId = (u['id_user'] as num?)?.toInt();

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: avatar.isNotEmpty
                      ? NetworkImage('${ApiService.host}$avatar')
                      : const AssetImage('assets/default_avatar.png')
                            as ImageProvider,
                ),
                title: Text(username),
                trailing: const Icon(Icons.north_east, size: 18),
                onTap: () async {
                  if (targetUserId == null) return; // กัน null

                  await _saveRecent(username);
                  if (!mounted) return;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ProfileScreen(userId: targetUserId), // ✅ ส่ง id ไป
                    ),
                  );
                },
              );
            }),
          ],
          if (hasSubject) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 16, 4, 4),
              child: Text(
                'Subjects',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ..._subjectResults.map(
              (s) => ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(s),
                trailing: const Icon(Icons.north_east, size: 18),
                onTap: () async {
                  await _saveRecent(s);
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SubjectFeedScreen(subjectName: s),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

return Scaffold(
  body: SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(children: [_buildSearchBar(), _buildResults()]),
    ),
  ),

  // ⬇⬇⬇ แทนส่วนนี้แทนของเก่า ⬇⬇⬇
  bottomNavigationBar: AppBottomNavBar(
    currentIndex: 1, // เพราะหน้า Search คือ index 1
    onTapAsync: (index) async {
      if (index == 0) {
        // ไปหน้า Home
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const homescreen()),
        );
      } else if (index == 2) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DocumentsScreen()),
        );
      } else if (index == 3) {
        // ปุ่ม Add
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getInt('user_id');
        final username = prefs.getString('username');

        if (userId == null || username == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('กรุณาเข้าสู่ระบบใหม่')),
          );
          return;
        }

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NewPostScreen(userId: userId, username: username),
          ),
        );
      } else if (index == 4) {
        // ไปหน้าโปรไฟล์
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getInt('user_id');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileScreen(userId: userId ?? 0),
          ),
        );
      }
    },
  ),
);

  }
}

enum SearchFilter { all, users, subjects }

class _Debouncer {
  final Duration delay;
  Timer? _t;
  _Debouncer(this.delay);
  void run(void Function() fn) {
    _t?.cancel();
    _t = Timer(delay, fn);
  }
}

// ---------------- Subject Picker Sheet ----------------
class _SubjectPickerSheet extends StatefulWidget {
  final List<String> years;
  final String initialYear;
  final ValueChanged<String> onYearChanged;
  final ValueChanged<String> onSubjectTap;

  const _SubjectPickerSheet({
    required this.years,
    required this.initialYear,
    required this.onYearChanged,
    required this.onSubjectTap,
  });

  @override
  State<_SubjectPickerSheet> createState() => _SubjectPickerSheetState();
}

class _SubjectPickerSheetState extends State<_SubjectPickerSheet> {
  late String _year;
  late Future<List<String>> _futureSubjects;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear;
    _futureSubjects = ApiService.getSubjects(yearLabel: _year);
  }

  Future<void> _reload() async {
    setState(() {
      _futureSubjects = ApiService.getSubjects(yearLabel: _year);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded, size: 20),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _year,
                  items: widget.years
                      .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                      .toList(),
                  onChanged: (y) {
                    if (y == null) return;
                    setState(() => _year = y);
                    widget.onYearChanged(y);
                    _reload();
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<String>>(
              future: _futureSubjects,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('โหลดรายวิชาไม่สำเร็จ'),
                  );
                }
                final subs = snap.data ?? [];
                if (subs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('ยังไม่มีโพสต์ในปีนี้'),
                  );
                }
                return Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: subs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.circle, size: 8),
                      title: Text(subs[i]),
                      onTap: () => widget.onSubjectTap(subs[i]),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
