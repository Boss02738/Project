import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_note_app/api/api_service.dart';
import 'package:my_note_app/screens/home_screen.dart';
import 'package:my_note_app/screens/NewPost.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _debouncer = _Debouncer(const Duration(milliseconds: 350));
  bool _loading = false;

  // toggle filter: ค้นหาทั้งคู่/เฉพาะ user/เฉพาะ subject
  SearchFilter _filter = SearchFilter.all;

  // recent search (เก็บล่าสุด 10 รายการ)
  List<String> _recent = [];

  // results
  List<dynamic> _userResults = [];
  List<String> _subjectResults = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final sp = await SharedPreferences.getInstance();
    setState(() => _recent = sp.getStringList('recent_search') ?? []);
  }

  Future<void> _saveRecent(String q) async {
    if (q.trim().isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    final list = [..._recent];
    list.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    list.insert(0, q);
    if (list.length > 10) list.removeLast();
    await sp.setStringList('recent_search', list);
    setState(() => _recent = list);
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() {
        _userResults = [];
        _subjectResults = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      // เรียกตาม filter
      if (_filter == SearchFilter.users || _filter == SearchFilter.all) {
        _userResults = await ApiService.searchUsers(q);
      } else {
        _userResults = [];
      }

      if (_filter == SearchFilter.subjects || _filter == SearchFilter.all) {
        _subjectResults = await ApiService.searchSubjects(q);
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

  void _onSubmit(String q) {
    _saveRecent(q);
    _search(q);
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
              hintText: 'Search',
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
        PopupMenuButton<SearchFilter>(
          icon: const Icon(Icons.tune_rounded),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (v) {
            setState(() => _filter = v);
            _search(_controller.text);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: SearchFilter.all, child: Text('All')),
            const PopupMenuItem(
              value: SearchFilter.users,
              child: Text('Users'),
            ),
            const PopupMenuItem(
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
        const Text(
          'Recent Search',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._recent.map(
          (q) => ListTile(
            leading: const Icon(Icons.history, size: 20),
            title: Text(q),
            trailing: const Icon(Icons.north_east, size: 18),
            onTap: () {
              _controller.text = q;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _controller.text.length),
              );
              _search(q);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    if (_loading) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }

    final hasUser = _userResults.isNotEmpty;
    final hasSubject = _subjectResults.isNotEmpty;

    if (!hasUser && !hasSubject) {
      // ถ้าไม่มี query ให้แสดง recent
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
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: avatar.isNotEmpty
                      ? NetworkImage('${ApiService.host}$avatar')
                      : const AssetImage('assets/default_avatar.png')
                            as ImageProvider,
                ),
                title: Text(username),
                trailing: const Icon(Icons.north_east, size: 18),
                onTap: () {
                  // TODO: ไปหน้าโปรไฟล์ผู้ใช้คนนั้น เมื่อพร้อม
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
                onTap: () {
                  // TODO: ไปหน้า feed กรองเฉพาะ subject นี้
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        selectedItemColor: const Color.fromARGB(255, 31, 102, 160),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) async {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const homescreen()),
            );
          } else if (index == 2) {
            final prefs = await SharedPreferences.getInstance();
            final userId = prefs.getInt('user_id');
            final username = prefs.getString('username');

            if (userId == null || username == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('กรุณาเข้าสู่ระบบใหม่')),
              );
              return;
            }

            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    NewPostScreen(userId: userId, username: username),
              ),
            );
          } else if (index == 3) {
            // TODO: ไปหน้าโปรไฟล์
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Add'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle_outlined),
            label: 'Profile',
          ),
        ],
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
