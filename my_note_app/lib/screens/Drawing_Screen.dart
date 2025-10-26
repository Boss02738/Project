// lib/screens/drawing_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:http/http.dart' as http;
import 'package:scribble/scribble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

/* ------------------ CONFIG ------------------ */

String get baseServerUrl =>
    Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000';

/* =================== TEXT BOX MODEL =================== */

class TextBoxData {
  final String id;
  final String text;
  final double x;
  final double y;
  final double fontSize;
  final int color;

  const TextBoxData({
    required this.id,
    required this.text,
    required this.x,
    required this.y,
    required this.fontSize,
    required this.color,
  });

  TextBoxData copyWith({
    String? text,
    double? x,
    double? y,
    double? fontSize,
    int? color,
  }) {
    return TextBoxData(
      id: id,
      text: text ?? this.text,
      x: x ?? this.x,
      y: y ?? this.y,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'x': x,
        'y': y,
        'fontSize': fontSize,
        'color': color,
      };

  factory TextBoxData.fromJson(Map<String, dynamic> m) => TextBoxData(
        id: m['id'] as String,
        text: (m['text'] as String?) ?? '',
        x: (m['x'] as num?)?.toDouble() ?? 0,
        y: (m['y'] as num?)?.toDouble() ?? 0,
        fontSize: (m['fontSize'] as num?)?.toDouble() ?? 18,
        color: (m['color'] as int?) ?? Colors.black.value,
      );
}

/* =================== PAGE =================== */

Sketch emptySketch() => Sketch.fromJson({'lines': []});

class NoteScribblePage extends StatefulWidget {
  final String boardId;
  final IO.Socket? socket;
  final String? documentId;
  final String? initialTitle;
  final List<Sketch>? initialPages;
  final List<List<TextBoxData>>? initialTextsPerPage;

  const NoteScribblePage({
    super.key,
    required this.boardId,
    this.socket,
    this.documentId,
    this.initialTitle,
    this.initialPages,
    this.initialTextsPerPage,
  });

  @override
  State<NoteScribblePage> createState() => _NoteScribblePageState();
}

class _NoteScribblePageState extends State<NoteScribblePage> {
  late final ScribbleNotifier _notifier;

  // drawing state
  Color _color = Colors.black;
  double _strokeWidth = 4.0;
  bool _isEraser = false;

  // saved custom colors
  static const _prefsKey = 'saved_colors';
  final List<Color> _savedColors = [];
  final Set<int> _presetColorValues = {
    Colors.black.value,
    Colors.red.value,
    Colors.yellow.value,
    Colors.green.value,
    Colors.blue.value,
  };

  int _lastLineCount = 0;
  Timer? _debounce;

  late List<Sketch> _pages;
  late List<List<TextBoxData>> _textsPages;
  int _pageIndex = 0;
  int _pendingSelfDeleteIndex = -1;

  String _title = 'Untitled';
  bool get offline => widget.socket == null;

  late final PageController _pageController;

  @override
  void initState() {
    super.initState();

    _pageController = PageController(initialPage: _pageIndex);

    _pages = (widget.initialPages != null && widget.initialPages!.isNotEmpty)
        ? widget.initialPages!.map((e) => Sketch.fromJson(e.toJson())).toList()
        : [emptySketch()];

    _textsPages =
        (widget.initialTextsPerPage != null && widget.initialTextsPerPage!.isNotEmpty)
            ? widget.initialTextsPerPage!
                .map((l) => l.map((t) => t).toList())
                .toList()
            : [<TextBoxData>[]];

    while (_textsPages.length < _pages.length) {
      _textsPages.add(<TextBoxData>[]);
    }

    _title = widget.initialTitle ?? 'Untitled';

    _notifier = ScribbleNotifier()
      ..setColor(_color)
      ..setStrokeWidth(_strokeWidth)
      ..setSketch(sketch: _pages[_pageIndex]);

    _notifier.addListener(() {
      final linesNow = _notifier.currentSketch.lines.length;
      if (linesNow != _lastLineCount) {
        _lastLineCount = linesNow;
        _scheduleSync();
      }
    });

    _loadSavedColors();

    if (!offline) {
      _wireSocket();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.socket!.emit('get_pages_meta', {'boardId': widget.boardId});
        _requestInitForCurrentPage();
      });
    }
  }

  /* ---------------- SAVED COLORS ---------------- */

  Future<void> _loadSavedColors() async {
    final sp = await SharedPreferences.getInstance();
    final ints = sp.getStringList(_prefsKey) ?? [];
    setState(() {
      _savedColors
        ..clear()
        ..addAll(ints.map((e) => Color(int.parse(e))));
    });
  }

  Future<void> _persistSavedColors() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(
      _prefsKey,
      _savedColors.map((c) => c.value.toString()).toList(),
    );
  }

  Future<void> _registerUsedColor(Color c, {bool reorderIfExists = true}) async {
    if (_presetColorValues.contains(c.value)) {
      setState(() {});
      return;
    }
    final i = _savedColors.indexWhere((x) => x.value == c.value);
    if (i >= 0) {
      if (reorderIfExists) {
        _savedColors.removeAt(i);
        _savedColors.insert(0, c);
      }
    } else {
      _savedColors.insert(0, c);
    }
    const cap = 12;
    if (_savedColors.length > cap) _savedColors.removeRange(cap, _savedColors.length);
    await _persistSavedColors();
    setState(() {});
  }

  /* ---------------- SOCKET ---------------- */

  void _wireSocket() {
    final socket = widget.socket!;
    socket.on('init_data', (data) {
      try {
        final int page = (data['page'] ?? 0) as int;
        final snap = data['snapshot'];
        if (snap != null && snap['data'] != null) {
          final Map<String, dynamic> jsonMap = snap['data'] is String
              ? Map<String, dynamic>.from(jsonDecode(snap['data']))
              : Map<String, dynamic>.from(snap['data'] as Map);

          final sketchJson =
              (jsonMap['lines'] != null) ? {'lines': jsonMap['lines']} : jsonMap;
          final sketch = Sketch.fromJson(sketchJson);
          final texts = (jsonMap['texts'] as List?)
                  ?.map((e) => TextBoxData.fromJson(Map<String, dynamic>.from(e as Map)))
                  .toList() ??
              <TextBoxData>[];

          _ensurePages(page + 1);
          _pages[page] = sketch;
          _textsPages[page] = texts;

          if (page == _pageIndex) {
            _notifier.setSketch(sketch: sketch);
            setState(() {});
          }
        } else if (page == _pageIndex) {
          _notifier.clear();
          _pages[_pageIndex] = emptySketch();
          _textsPages[_pageIndex] = <TextBoxData>[];
          setState(() {});
        }
      } catch (_) {}
    });

    socket.on('set_sketch', (data) {
      try {
        final int page = (data['page'] ?? 0) as int;
        final sketchJson = data['sketch'];
        final Map<String, dynamic> jsonMap = sketchJson is String
            ? Map<String, dynamic>.from(jsonDecode(sketchJson))
            : Map<String, dynamic>.from(sketchJson as Map);

        final linesOnly =
            (jsonMap['lines'] != null) ? {'lines': jsonMap['lines']} : jsonMap;
        final incoming = Sketch.fromJson(linesOnly);
        final texts = (jsonMap['texts'] as List?)
                ?.map((e) => TextBoxData.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            <TextBoxData>[];

        _ensurePages(page + 1);
        _pages[page] = incoming;
        _textsPages[page] = texts;

        if (page == _pageIndex) {
          _notifier.setSketch(sketch: _pages[_pageIndex]);
          setState(() {});
        }
      } catch (_) {}
    });

    socket.on('clear_board', (data) {
      try {
        final int page =
            (data is Map && data['page'] is int) ? data['page'] as int : _pageIndex;
        _ensurePages(page + 1);
        _pages[page] = emptySketch();
        _textsPages[page] = <TextBoxData>[];
        if (page == _pageIndex) {
          _notifier.clear();
          setState(() {});
        }
      } catch (_) {}
    });

    socket.on('pages_meta', (data) {
      try {
        final int count = (data['count'] ?? 1) as int;
        if (count <= 0) return;
        setState(() {
          if (_pages.length < count) {
            for (int i = 0; i < count - _pages.length; i++) {
              _pages.add(emptySketch());
              _textsPages.add(<TextBoxData>[]);
            }
          }
          if (_pageIndex >= _pages.length) {
            _pageIndex = _pages.length - 1;
            _notifier.setSketch(sketch: _pages[_pageIndex]);
          }
        });
      } catch (_) {}
    });

    socket.on('page_deleted', (data) {
      try {
        final int d =
            (data is Map && data['deletedPage'] is int) ? data['deletedPage'] as int : -1;
        if (d < 0) return;
        if (_pendingSelfDeleteIndex == d) {
          _pendingSelfDeleteIndex = -1;
          return;
        }
        if (d < _pages.length && _pages.length > 1) {
          setState(() {
            _pages.removeAt(d);
            _textsPages.removeAt(d);
            if (_pageIndex > d) _pageIndex -= 1;
            if (_pageIndex >= _pages.length) _pageIndex = _pages.length - 1;
          });
          _notifier.setSketch(sketch: _pages[_pageIndex]);
          _requestInitForCurrentPage();
        }
      } catch (_) {}
    });
  }

  void _ensurePages(int count) {
    while (_pages.length < count) {
      _pages.add(emptySketch());
      _textsPages.add(<TextBoxData>[]);
    }
  }

  void _requestInitForCurrentPage() {
    if (offline) return;
    widget.socket!.emit('init_page', {'boardId': widget.boardId, 'page': _pageIndex});
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!offline) _emitFullSketchWithTexts();
    });
  }

  void _emitFullSketchWithTexts() {
    if (offline) return;
    _pages[_pageIndex] = _notifier.currentSketch;

    final sketchJson = _notifier.currentSketch.toJson();
    final payload = {
      'lines': (sketchJson['lines'] ?? []),
      'texts': _textsPages[_pageIndex].map((t) => t.toJson()).toList(),
    };

    widget.socket!.emit('set_sketch', {
      'boardId': widget.boardId,
      'page': _pageIndex,
      'sketch': payload,
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.socket?.dispose();
    _notifier.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /* ---------------- COVER PNG ---------------- */

  Future<String?> _sketchToPngBase64(
    Sketch sketch, {
    int width = 512,
    int height = 288,
    List<TextBoxData>? texts,
  }) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas =
          Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

      final bg = Paint()..color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), bg);

      // content bounds
      double minX = double.infinity, minY = double.infinity;
      double maxX = -double.infinity, maxY = -double.infinity;

      for (final line in sketch.lines) {
        final dynamic dyn = line;
        if (dyn.points is List && (dyn.points as List).isNotEmpty) {
          for (final p in dyn.points as List) {
            final double x = (p.x as num).toDouble();
            final double y = (p.y as num).toDouble();
            minX = math.min(minX, x);
            minY = math.min(minY, y);
            maxX = math.max(maxX, x);
            maxY = math.max(maxY, y);
          }
        }
      }

      if (texts != null) {
        for (final t in texts) {
          minX = math.min(minX, t.x);
          minY = math.min(minY, t.y);
          maxX = math.max(maxX, t.x + t.fontSize * (t.text.length * 0.6));
          maxY = math.max(maxY, t.y + t.fontSize * 1.2);
        }
      }

      if (minX == double.infinity) {
        final picture = recorder.endRecording();
        final img = await picture.toImage(width, height);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        return base64Encode(bytes!.buffer.asUint8List());
      }

      final contentW = (maxX - minX).clamp(1.0, double.infinity);
      final contentH = (maxY - minY).clamp(1.0, double.infinity);
      final scale = 0.9 * math.min(width / contentW, height / contentH);
      final dx = (width - contentW * scale) / 2 - minX * scale;
      final dy = (height - contentH * scale) / 2 - minY * scale;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.scale(scale);

      for (final line in sketch.lines) {
        final dynamic dyn = line;
        Map<String, dynamic> m = {};
        try {
    final j = dyn.toJson();
    if (j is Map) m = Map<String, dynamic>.from(j);
        } catch (_) {}

        final bool isEraser = (m['tool'] == 'eraser') || (m['pen'] == 'eraser');
        final int colorInt = (m['color'] is int)
            ? m['color'] as int
            : (dyn.color is int ? dyn.color as int : Colors.black.value);

        final double widthPx = (m['width'] is num)
            ? (m['width'] as num).toDouble()
            : (dyn.width is num
                ? (dyn.width as num).toDouble()
                : (dyn.strokeWidth is num ? (dyn.strokeWidth as num).toDouble() : 4.0));

        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = widthPx
          ..color = isEraser ? Colors.white : Color(colorInt);

        final path = Path();
        if (dyn.points is List && (dyn.points as List).isNotEmpty) {
          final pts = dyn.points as List;
          path.moveTo((pts.first.x as num).toDouble(), (pts.first.y as num).toDouble());
          for (int i = 1; i < pts.length; i++) {
            final p = pts[i];
            path.lineTo((p.x as num).toDouble(), (p.y as num).toDouble());
          }
        }
        canvas.drawPath(path, paint);
      }

      if (texts != null) {
        for (final t in texts) {
          final builder = ui.ParagraphBuilder(
            ui.ParagraphStyle(fontSize: t.fontSize, textAlign: TextAlign.left),
          )..pushStyle(ui.TextStyle(color: Color(t.color)));
          builder.addText(t.text);
          final paragraph =
              builder.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
          canvas.drawParagraph(paragraph, Offset(t.x, t.y));
        }
      }

      canvas.restore();
      final picture = recorder.endRecording();
      final img = await picture.toImage(width, height);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      return base64Encode(bytes!.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  /* ---------------- SAVE DOC ---------------- */

  Future<void> _saveDocument() async {
    _pages[_pageIndex] = _notifier.currentSketch;

    final titleCtrl = TextEditingController(text: _title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Document'),
        content: TextField(
          controller: titleCtrl,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;

    final pages = <Map<String, dynamic>>[];
    for (int i = 0; i < _pages.length; i++) {
      pages.add({
        'index': i,
        'data': {
          'lines': _pages[i].toJson()['lines'] ?? [],
          'texts': _textsPages[i].map((t) => t.toJson()).toList(),
        }
      });
    }

    final coverBase64 = await _sketchToPngBase64(
      _pages.first,
      texts: _textsPages.isNotEmpty ? _textsPages.first : null,
    );

    final payload = {
      if (widget.documentId != null) 'id': widget.documentId,
      'title': titleCtrl.text.trim().isEmpty ? 'Untitled' : titleCtrl.text.trim(),
      'boardId': widget.boardId,
      'pages': pages,
      'coverPng': coverBase64,
      // attach owner if user logged in
      if ((await SharedPreferences.getInstance()).getInt('user_id') != null)
        'owner_id': (await SharedPreferences.getInstance()).getInt('user_id'),
    };

    try {
      final r = await http.post(
        Uri.parse('$baseServerUrl/documents'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      debugPrint('POST $baseServerUrl/documents => ${r.statusCode}');
      debugPrint('POST body: ${r.body}');
      if (!mounted) return;
      if (r.statusCode == 200) {
        setState(() => _title = payload['title'] as String);
        // ถ้า server คืน id ให้แสดงให้ผู้ใช้เห็น (กรณีสร้างใหม่)
        try {
          final Map<String, dynamic> json = jsonDecode(r.body) as Map<String, dynamic>;
          if (json.containsKey('id')) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('บันทึกเรียบร้อย (id: ${json['id']})')),
            );
          } else {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('บันทึกเรียบร้อย')));
          }
        } catch (_) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('บันทึกเรียบร้อย')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('บันทึกไม่สำเร็จ (${r.statusCode})')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('บันทึกไม่สำเร็จ')));
    }
  }

  /* ---------------- UI ---------------- */

  @override
  Widget build(BuildContext context) {
    final titleText = offline ? 'Document: $_title' : 'Room: ${widget.boardId}';

    return Scaffold(
      appBar: AppBar(
        title: Text(titleText, overflow: TextOverflow.ellipsis),
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        actions: [
          if (!offline)
            IconButton(
              tooltip: 'Copy Room ID',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: widget.boardId));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied: ${widget.boardId}')),
                  );
                }
              },
              icon: const Icon(Icons.content_copy),
            ),
          IconButton(
            tooltip: 'เพิ่มข้อความ',
            onPressed: _addTextBox,
            icon: const Icon(Icons.text_fields),
          ),
          IconButton(
            tooltip: 'Save as Document',
            onPressed: _saveDocument,
            icon: const Icon(Icons.save),
          ),
          if (!offline) ...[
            IconButton(
              tooltip: 'Sync snapshot',
              onPressed: _emitFullSketchWithTexts,
              icon: const Icon(Icons.sync),
            ),
            IconButton(
              tooltip: 'Clear (this page)',
              onPressed: () {
                _notifier.clear();
                _pages[_pageIndex] = emptySketch();
                _textsPages[_pageIndex] = <TextBoxData>[];
                widget.socket!.emit('clear_board', {
                  'boardId': widget.boardId,
                  'page': _pageIndex,
                });
                setState(() {});
              },
              icon: const Icon(Icons.delete_sweep),
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(84),
          child: _TopToolbar(
            isEraser: _isEraser,
            color: _color,
            strokeWidth: _strokeWidth,
            savedColors: _savedColors,
            onPen: () {
              setState(() => _isEraser = false);
              _notifier.setColor(_color);
            },
            onEraser: () {
              setState(() => _isEraser = true);
              _notifier.setEraser();
            },
            onPickPresetColor: (c) async {
              setState(() {
                _color = c;
                _isEraser = false;
              });
              _notifier.setColor(c);
              await _registerUsedColor(c);
            },
            onPickSavedColor: (c) async {
              setState(() {
                _color = c;
                _isEraser = false;
              });
              _notifier.setColor(c);
              await _registerUsedColor(c, reorderIfExists: false);
            },
            onOpenRainbowPicker: () async {
              final chosen = await _openRainbowPicker(context, _color);
              if (chosen != null) {
                setState(() {
                  _color = chosen;
                  _isEraser = false;
                });
                _notifier.setColor(chosen);
                await _registerUsedColor(chosen, reorderIfExists: true);
              }
            },
            onRemoveSavedColor: (c) async {
              setState(() => _savedColors.removeWhere((x) => x.value == c.value));
              await _persistSavedColors();
            },
            onChangeWidth: (v) {
              setState(() => _strokeWidth = v);
              _notifier.setStrokeWidth(v);
            },
          ),
        ),
      ),

      // Sheet
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: _pages.length,
          onPageChanged: (i) {
            _pages[_pageIndex] = _notifier.currentSketch;
            setState(() => _pageIndex = i);
            _notifier.setSketch(sketch: _pages[_pageIndex]);
            _requestInitForCurrentPage();
          },
          itemBuilder: (ctx, i) {
            final isCurrent = i == _pageIndex;
            final texts = _textsPages[i];

            final sheet = Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: isCurrent
                  ? Stack(
                      children: [
                        Scribble(
                          notifier: _notifier,
                          drawPen: !_isEraser,
                          drawEraser: _isEraser,
                        ),
                        ...texts.map((t) => _buildTextBoxWidget(t)),
                      ],
                    )
                  : const SizedBox.expand(),
            );

            final footer = Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Center(
                child: Text(
                  'Page ${i + 1}/${_pages.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            );

            return Column(
              children: [
                Expanded(child: sheet),
                footer,
              ],
            );
          },
        ),
      ),

      // Bottom controller
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(top: BorderSide(color: Colors.black12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous (up)',
                onPressed: (_pageIndex > 0)
                    ? () {
                        _pages[_pageIndex] = _notifier.currentSketch;
                        final newIndex = _pageIndex - 1;
                        _pageController.animateToPage(
                          newIndex,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      }
                    : null,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              const SizedBox(width: 8),
              Text('Page ${_pageIndex + 1}/${_pages.length}'),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Add new page (below)',
                onPressed: () {
                  _pages[_pageIndex] = _notifier.currentSketch;
                  setState(() {
                    _pages.add(emptySketch());
                    _textsPages.add(<TextBoxData>[]);
                  });
                  final newIndex = _pages.length - 1;
                  _notifier.setSketch(sketch: _pages[newIndex]);
                  _pageController.animateToPage(
                    newIndex,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                  setState(() => _pageIndex = newIndex);
                  if (!offline) {
                    widget.socket!.emit('add_page', {'boardId': widget.boardId, 'page': _pageIndex});
                  }
                },
                icon: const Icon(Icons.add_circle),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Delete this page',
                onPressed: (_pages.length > 1)
                    ? () {
                        final deletedIndex = _pageIndex;
                        _pendingSelfDeleteIndex = deletedIndex;
                        setState(() {
                          _pages.removeAt(deletedIndex);
                          _textsPages.removeAt(deletedIndex);
                          final next = deletedIndex.clamp(0, _pages.length - 1);
                          _pageIndex = next;
                          _notifier.setSketch(sketch: _pages[_pageIndex]);
                        });
                        _pageController.animateToPage(
                          _pageIndex,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        );
                        if (!offline) {
                          widget.socket!
                              .emit('delete_page', {'boardId': widget.boardId, 'page': deletedIndex});
                          _requestInitForCurrentPage();
                        }
                      }
                    : null,
                icon: const Icon(Icons.delete_forever),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Next (down)',
                onPressed: (_pageIndex < _pages.length - 1)
                    ? () {
                        _pages[_pageIndex] = _notifier.currentSketch;
                        final newIndex = _pageIndex + 1;
                        _pageController.animateToPage(
                          newIndex,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      }
                    : null,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ---------------- Text box controls ---------------- */

  Future<void> _addTextBox() async {
    final textCtrl = TextEditingController();
    int fontPx = 18;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Add Text'),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 350),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: textCtrl,
                    decoration: const InputDecoration(labelText: 'Text'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Font size'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _fontBox(
                          value: fontPx,
                          onChanged: (v) => setSt(() => fontPx = v.clamp(8, 96)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Color'),
                  const SizedBox(height: 8),
                  _colorSwatchesInline(
                    current: _color,
                    onPickPreset: (c) {
                      setSt(() {});
                      setState(() {
                        _color = c;
                        _isEraser = false;
                      });
                      _notifier.setColor(c);
                    },
                    onOpenPalette: () async {
                      final chosen = await _openRainbowPicker(context, _color);
                      if (chosen != null) {
                        setState(() {
                          _color = chosen;
                          _isEraser = false;
                        });
                        _notifier.setColor(chosen);
                        await _registerUsedColor(chosen);
                        setSt(() {});
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('เพิ่ม')),
          ],
        ),
      ),
    );
    if (ok != true || textCtrl.text.trim().isEmpty) return;

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final c = _color;
    final newBox = TextBoxData(
      id: id,
      text: textCtrl.text.trim(),
      x: 40,
      y: 40,
      fontSize: fontPx.toDouble(),
      color: c.value,
    );
    setState(() => _textsPages[_pageIndex] = [..._textsPages[_pageIndex], newBox]);
    _scheduleSync();
  }

  Widget _buildTextBoxWidget(TextBoxData t) {
    return Positioned(
      left: t.x,
      top: t.y,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            final nx = (t.x + d.delta.dx);
            final ny = (t.y + d.delta.dy);
            _textsPages[_pageIndex] = _textsPages[_pageIndex]
                .map((e) => e.id == t.id ? e.copyWith(x: nx, y: ny) : e)
                .toList();
          });
          _scheduleSync();
        },
        onTap: () => _editTextBox(t),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.0),
            border: Border.all(color: Colors.black12),
          ),
          child: Builder(builder: (ctx) {
            // Constrain text width so long text doesn't overflow the screen when positioned
            final screenW = MediaQuery.of(ctx).size.width;
            final maxW = (screenW - (t.x + 24)).clamp(80.0, screenW);
            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Text(
                  t.text,
                  style: TextStyle(fontSize: t.fontSize, color: Color(t.color)),
                  softWrap: true,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Future<void> _editTextBox(TextBoxData t) async {
    final textCtrl = TextEditingController(text: t.text);
    int fontPx = t.fontSize.round();
    Color current = Color(t.color);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Edit Text'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: textCtrl),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Font size'),
                  const SizedBox(width: 12),
                  _fontBox(
                    value: fontPx,
                    onChanged: (v) => setSt(() => fontPx = v.clamp(8, 96)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Color'),
                  const SizedBox(width: 12),
                  _colorSwatchesInline(
                    current: current,
                    onPickPreset: (c) {
                      setSt(() => current = c);
                    },
                    onOpenPalette: () async {
                      final chosen = await _openRainbowPicker(context, current);
                      if (chosen != null) setSt(() => current = chosen);
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('บันทึก')),
            TextButton(
              onPressed: () {
                setState(() {
                  _textsPages[_pageIndex] =
                      _textsPages[_pageIndex].where((e) => e.id != t.id).toList();
                });
                _scheduleSync();
                Navigator.pop(ctx, false);
              },
              child: const Text('ลบ', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      setState(() {
        _textsPages[_pageIndex] = _textsPages[_pageIndex].map((e) {
          if (e.id == t.id) {
            return e.copyWith(
              text: textCtrl.text.trim(),
              fontSize: fontPx.toDouble(),
              color: current.value,
            );
          }
          return e;
        }).toList();
      });
      _scheduleSync();
    }
  }

  /* ------------- palette helpers ------------- */

  Widget _fontBox({required int value, required ValueChanged<int> onChanged}) {
    final ctrl = TextEditingController(text: value.toString());
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(value - 1),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 64,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            onSubmitted: (v) {
              final n = int.tryParse(v) ?? value;
              onChanged(n);
            },
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              suffixText: 'px',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  Widget _colorSwatchesInline({
    required Color current,
    required ValueChanged<Color> onPickPreset,
    required Future<void> Function() onOpenPalette,
  }) {
    final presets = <Color>[Colors.black, Colors.red, Colors.yellow, Colors.green, Colors.blue];

    // Use Wrap so the swatches + palette button will wrap to new line instead of overflowing
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...presets.map((c) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _ringColorDot(
                color: c,
                selected: current.value == c.value,
                onTap: () => onPickPreset(c),
              ),
            )),
        FilledButton.tonalIcon(
          onPressed: onOpenPalette,
          icon: const Icon(Icons.palette),
          label: const Text('Palette'),
        ),
      ],
    );
  }

  Widget _ringColorDot({
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.black.withOpacity(0.25) : Colors.transparent,
            width: selected ? 2 : 0,
          ),
        ),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black12, width: 1),
          ),
        ),
      ),
    );
  }

  Future<Color?> _openRainbowPicker(BuildContext context, Color current) async {
    Color selected = current;
    HSVColor hsv = HSVColor.fromColor(current);
    double hue = hsv.hue;
    double value = hsv.value;

    return showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: StatefulBuilder(builder: (ctx, setSt) {
            selected = HSVColor.fromAHSV(1, hue, 1, value).toColor();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('เลือกสีจากถาดรุ้ง (ลากได้ 2 แกน)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _RainbowPanel2D(
                  height: 180,
                  initial: selected,
                  onChanged: (h, v, c) => setSt(() {
                    hue = h;
                    value = v;
                    selected = c;
                  }),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('สีที่เลือก:'),
                    const SizedBox(width: 8),
                    Container(
                      width: 44,
                      height: 28,
                      decoration: BoxDecoration(
                        color: selected,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                    const Spacer(),
                    Text('#${selected.value.toRadixString(16).padLeft(8, '0').toUpperCase()}'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, selected),
                      child: const Text('ใช้สีนี้'),
                    ),
                  ],
                ),
              ],
            );
          }),
        );
      },
    );
  }
}

/* ---------------- TOP TOOLBAR ---------------- */

class _TopToolbar extends StatelessWidget {
  const _TopToolbar({
    required this.isEraser,
    required this.color,
    required this.strokeWidth,
    required this.savedColors,
    required this.onPen,
    required this.onEraser,
    required this.onPickPresetColor,
    required this.onPickSavedColor,
    required this.onOpenRainbowPicker,
    required this.onRemoveSavedColor,
    required this.onChangeWidth,
  });

  final bool isEraser;
  final Color color;
  final double strokeWidth;
  final List<Color> savedColors;

  final VoidCallback onPen;
  final VoidCallback onEraser;
  final ValueChanged<Color> onPickPresetColor;
  final ValueChanged<Color> onPickSavedColor;
  final Future<void> Function() onOpenRainbowPicker;
  final ValueChanged<Color> onRemoveSavedColor;
  final ValueChanged<double> onChangeWidth;

  @override
  Widget build(BuildContext context) {
    final presets = <Color>[Colors.black, Colors.red, Colors.yellow, Colors.green, Colors.blue];

    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolButton(context, icon: Icons.edit, selected: !isEraser, tooltip: 'Pen', onTap: onPen),
            const SizedBox(width: 4),
            _toolButton(context,
                icon: Icons.cleaning_services, selected: isEraser, tooltip: 'Eraser', onTap: onEraser),
            const SizedBox(width: 8),
            Row(
              children: [
                const Icon(Icons.line_weight, size: 20),
                SizedBox(
                  width: 140,
                  child: Slider(min: 1, max: 20, value: strokeWidth, onChanged: onChangeWidth),
                ),
              ],
            ),
            const VerticalDivider(width: 16),
            Row(
              children: presets
                  .map((c) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6.0),
                        child: _ringColorDot(
                          color: c,
                          selected: c.value == color.value && !isEraser,
                          onTap: () => onPickPresetColor(c),
                        ),
                      ))
                  .toList(),
            ),
            if (savedColors.isNotEmpty) ...[
              const SizedBox(width: 8),
              Row(
                children: savedColors
                    .map((c) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _ringColorDot(
                                color: c,
                                selected: c.value == color.value && !isEraser,
                                onTap: () => onPickSavedColor(c),
                              ),
                              Positioned(
                                right: -2,
                                top: -2,
                                child: InkWell(
                                  onTap: () => onRemoveSavedColor(c),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.black26),
                                    ),
                                    child: const Icon(Icons.close, size: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: onOpenRainbowPicker,
              icon: const Icon(Icons.palette),
              label: const Text('Palette'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(BuildContext context,
      {required IconData icon, required bool selected, required VoidCallback onTap, String? tooltip}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? cs.primary : Colors.transparent, width: selected ? 2 : 0),
      ),
      child: IconButton.filledTonal(
        onPressed: onTap,
        icon: Icon(icon, color: selected ? cs.onSecondaryContainer : null),
        tooltip: tooltip,
        style: IconButton.styleFrom(backgroundColor: selected ? cs.secondaryContainer : null),
      ),
    );
  }

  Widget _ringColorDot({
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.black.withOpacity(0.25) : Colors.transparent,
            width: selected ? 2 : 0,
          ),
        ),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black12, width: 1),
          ),
        ),
      ),
    );
  }
}

/* ---------------- RAINBOW 2D PANEL ---------------- */

class _RainbowPanel2D extends StatefulWidget {
  const _RainbowPanel2D({
    required this.height,
    required this.initial,
    required this.onChanged,
  });

  final double height;
  final Color initial;
  final void Function(double hue, double value, Color color) onChanged;

  @override
  State<_RainbowPanel2D> createState() => _RainbowPanel2DState();
}

class _RainbowPanel2DState extends State<_RainbowPanel2D> {
  late double _hue; // 0..360
  late double _value; // 1..0

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initial);
    _hue = hsv.hue;
    _value = hsv.value;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cons) {
      final w = cons.maxWidth;
      final h = widget.height;

      void handleAt(Offset p) {
        final dx = p.dx.clamp(0, math.max(1.0, w));
        final dy = p.dy.clamp(0, math.max(1.0, h));
        final hue = (dx / w) * 360.0;
        final value = 1.0 - (dy / h);
        setState(() {
          _hue = hue;
          _value = value;
        });
        final color = HSVColor.fromAHSV(1, hue, 1, value).toColor();
        widget.onChanged(hue, value, color);
      }

      final indicatorX = (_hue / 360) * (w - 12);
      final indicatorY = (1 - _value) * (h - 12);

      return GestureDetector(
        onPanDown: (d) => handleAt(d.localPosition),
        onPanUpdate: (d) => handleAt(d.localPosition),
        child: Container(
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black12),
          ),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xFFFF0000),
                      Color(0xFFFFFF00),
                      Color(0xFF00FF00),
                      Color(0xFF00FFFF),
                      Color(0xFF0000FF),
                      Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.95)],
                  ),
                ),
              ),
              Positioned(
                left: indicatorX,
                top: indicatorY,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
