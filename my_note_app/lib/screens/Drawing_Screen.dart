// lib/screens/drawing_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:flutter/painting.dart' show paintImage;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:scribble/scribble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

// ====== [ADDED] Save & Open files ======
import 'package:file_saver/file_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:open_file/open_file.dart';
// ======================================

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

/* =================== IMAGE LAYER MODEL =================== */

class ImageLayerData {
  final String id;
  final String bytesB64; // raw image base64 (png/jpg)
  final double x;        // center x (px)
  final double y;        // center y (px)
  final double scale;    // 0.2..6
  final double rotation; // radians

  const ImageLayerData({
    required this.id,
    required this.bytesB64,
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
  });

  ImageLayerData copyWith({
    String? bytesB64,
    double? x,
    double? y,
    double? scale,
    double? rotation,
  }) {
    return ImageLayerData(
      id: id,
      bytesB64: bytesB64 ?? this.bytesB64,
      x: x ?? this.x,
      y: y ?? this.y,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bytesB64': bytesB64,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
      };

  factory ImageLayerData.fromJson(Map<String, dynamic> m) => ImageLayerData(
        id: m['id'] as String,
        bytesB64: m['bytesB64'] as String,
        x: (m['x'] as num?)?.toDouble() ?? 140,
        y: (m['y'] as num?)?.toDouble() ?? 160,
        scale: (m['scale'] as num?)?.toDouble() ?? 1.0,
        rotation: (m['rotation'] as num?)?.toDouble() ?? 0.0,
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
  final List<List<ImageLayerData>>? initialImagesPerPage;

  const NoteScribblePage({
    super.key,
    required this.boardId,
    this.socket,
    this.documentId,
    this.initialTitle,
    this.initialPages,
    this.initialTextsPerPage,
    this.initialImagesPerPage,
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
  late List<List<ImageLayerData>> _imagePages;
  int _pageIndex = 0;
  int _pendingSelfDeleteIndex = -1;

  String _title = 'Untitled';
  bool get offline => widget.socket == null;

  late final PageController _pageController;

  final ImagePicker _picker = ImagePicker();
  int _selectedImageIndex = -1;
  bool _isManipulatingImage = false;

  // โหมด: วาด (false) / แก้ไขรูป (true)
  bool _editImagesMode = false;

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

    _imagePages =
        (widget.initialImagesPerPage != null && widget.initialImagesPerPage!.isNotEmpty)
            ? widget.initialImagesPerPage!.map((l) => l.map((e) => e).toList()).toList()
            : List.generate(_pages.length, (_) => <ImageLayerData>[]);

    while (_textsPages.length < _pages.length) _textsPages.add(<TextBoxData>[]);
    while (_imagePages.length < _pages.length) _imagePages.add(<ImageLayerData>[]);

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
          final images = (jsonMap['images'] as List?)
                  ?.map((e) => ImageLayerData.fromJson(Map<String, dynamic>.from(e as Map)))
                  .toList() ??
              <ImageLayerData>[];

          _ensurePages(page + 1);
          _pages[page] = sketch;
          _textsPages[page] = texts;
          _imagePages[page] = images;

          if (page == _pageIndex) {
            _notifier.setSketch(sketch: sketch);
            _selectedImageIndex = -1;
            setState(() {});
          }
        } else if (page == _pageIndex) {
          _notifier.clear();
          _pages[_pageIndex] = emptySketch();
          _textsPages[_pageIndex] = <TextBoxData>[];
          _imagePages[_pageIndex] = <ImageLayerData>[];
          _selectedImageIndex = -1;
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
        final images = (jsonMap['images'] as List?)
                ?.map((e) => ImageLayerData.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            <ImageLayerData>[];

        _ensurePages(page + 1);
        _pages[page] = incoming;
        _textsPages[page] = texts;
        _imagePages[page] = images;

        if (page == _pageIndex) {
          _notifier.setSketch(sketch: _pages[_pageIndex]);
          _selectedImageIndex = -1;
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
        _imagePages[page] = <ImageLayerData>[];
        if (page == _pageIndex) {
          _selectedImageIndex = -1;
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
              _imagePages.add(<ImageLayerData>[]);
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
            _imagePages.removeAt(d);
            _selectedImageIndex = -1;
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
      _imagePages.add(<ImageLayerData>[]);
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
      'images': _imagePages[_pageIndex].map((img) => img.toJson()).toList(),
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
    List<ImageLayerData>? images,
  }) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas =
          Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

      final bg = Paint()..color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), bg);

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

      if (images != null && images.isNotEmpty) {
        for (final img in images) {
          final w = 200.0 * img.scale;
          final h = 200.0 * img.scale;
          minX = math.min(minX, img.x - w / 2);
          minY = math.min(minY, img.y - h / 2);
          maxX = math.max(maxX, img.x + w / 2);
          maxY = math.max(maxY, img.y + h / 2);
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

      if (images != null && images.isNotEmpty) {
        for (final layer in images) {
          try {
            final bytes = base64Decode(layer.bytesB64);
            final codec = await ui.instantiateImageCodec(bytes);
            final frame = await codec.getNextFrame();
            final uiImage = frame.image;

            final imgW = uiImage.width.toDouble();
            final imgH = uiImage.height.toDouble();

            canvas.save();
            canvas.translate(layer.x, layer.y);
            canvas.rotate(layer.rotation);
            canvas.scale(layer.scale, layer.scale);
            final rect = Rect.fromCenter(
              center: Offset.zero,
              width: imgW,
              height: imgH,
            );
            paintImage(canvas: canvas, rect: rect, image: uiImage, fit: BoxFit.contain);
            canvas.restore();
          } catch (_) {}
        }
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

  /* ---------------- SAVE DOC (server) ---------------- */

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
          'images': _imagePages[i].map((img) => img.toJson()).toList(),
        }
      });
    }

    final coverBase64 = await _sketchToPngBase64(
      _pages.first,
      texts: _textsPages.isNotEmpty ? _textsPages.first : null,
      images: _imagePages.isNotEmpty ? _imagePages.first : null,
    );

    if (coverBase64 == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Warning: failed to generate cover image; saving without cover')),
        );
      }
    }

    final payload = {
      if (widget.documentId != null) 'id': widget.documentId,
      'title': titleCtrl.text.trim().isEmpty ? 'Untitled' : titleCtrl.text.trim(),
      'boardId': widget.boardId,
      'board_id': widget.boardId,
      'pages': pages,
      'coverPng': coverBase64,
      'cover_png': coverBase64,
      if ((await SharedPreferences.getInstance()).getInt('user_id') != null)
        'owner_id': (await SharedPreferences.getInstance()).getInt('user_id'),
    };

    try {
      final r = await http.post(
        Uri.parse('$baseServerUrl/documents'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (!mounted) return;
      if (r.statusCode == 200) {
        setState(() => _title = payload['title'] as String);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('บันทึกเรียบร้อย')));
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

  /* ---------------- Local save/export helpers [ADDED] ---------------- */

  Future<void> _ensureStoragePermission() async {
    try {
      await Permission.storage.request();
    } catch (_) {}
  }

  Future<void> _announceAndOpen(String label, String? savedPath) async {
    if (!mounted) return;
    final text = (savedPath != null && savedPath.isNotEmpty)
        ? 'บันทึกแล้ว: $label\n$savedPath'
        : 'บันทึกแล้ว: $label';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    if (savedPath != null && savedPath.isNotEmpty) {
      await OpenFile.open(savedPath);
    }
  }

  Future<void> _saveCurrentPageAsPNG() async {
    await _ensureStoragePermission();
    final b64 = await _sketchToPngBase64(
      _notifier.currentSketch,
      width: 1400,
      height: 2000,
      texts: _textsPages[_pageIndex],
      images: _imagePages[_pageIndex],
    );
    if (b64 == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('แปลงภาพไม่สำเร็จ')),
        );
      }
      return;
    }
    final bytes = base64Decode(b64);
    final fileName = 'note_page_${_pageIndex + 1}.png';

    final savedPath = await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      ext: 'png',
      mimeType: MimeType.png,
    );

    await _announceAndOpen(fileName, savedPath);
  }

  Future<void> _exportAllPagesAsPDF() async {
    await _ensureStoragePermission();

    final List<Uint8List> pagePngs = [];
    for (int i = 0; i < _pages.length; i++) {
      final b64 = await _sketchToPngBase64(
        _pages[i],
        width: 1400,
        height: 2000,
        texts: _textsPages[i],
        images: _imagePages[i],
      );
      if (b64 != null) pagePngs.add(base64Decode(b64));
    }
    if (pagePngs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่มีหน้าสำหรับส่งออก')),
        );
      }
      return;
    }

    final doc = pw.Document();
    for (final png in pagePngs) {
      final img = pw.MemoryImage(png);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Center(
            child: pw.FittedBox(
              fit: pw.BoxFit.contain,
              child: pw.Image(img),
            ),
          ),
        ),
      );
    }
    final pdfBytes = await doc.save();
    final fileName = 'notes_${DateTime.now().millisecondsSinceEpoch}.pdf';

    final savedPath = await FileSaver.instance.saveFile(
      name: fileName,
      bytes: pdfBytes,
      ext: 'pdf',
      mimeType: MimeType.pdf,
    );

    await _announceAndOpen(fileName, savedPath);
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
          // สลับโหมด วาด / แก้ไขรูป
          IconButton(
            tooltip: _editImagesMode ? 'ไปโหมดวาด' : 'ไปโหมดแก้ไขรูป',
            onPressed: () {
              setState(() {
                _editImagesMode = !_editImagesMode;
                _selectedImageIndex = -1;
              });
            },
            icon: Icon(_editImagesMode ? Icons.brush : Icons.photo),
          ),
          IconButton(
            tooltip: 'เพิ่มรูป',
            onPressed: _addImageLayer,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          IconButton(
            tooltip: 'เพิ่มข้อความ',
            onPressed: _addTextBox,
            icon: const Icon(Icons.text_fields),
          ),
          IconButton(
            tooltip: 'Save as Document (server)',
            onPressed: _saveDocument,
            icon: const Icon(Icons.save),
          ),
          // ====== [ADDED] Export/Save local ======
          PopupMenuButton<String>(
            tooltip: 'Export',
            icon: const Icon(Icons.download),
            onSelected: (v) {
              if (v == 'png') _saveCurrentPageAsPNG();
              if (v == 'pdf') _exportAllPagesAsPDF();
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem<String>(value: 'png', child: Text('Save this page as PNG')),
              PopupMenuItem<String>(value: 'pdf', child: Text('Export ALL pages as PDF')),
            ],
          ),
          // =======================================
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
                _imagePages[_pageIndex] = <ImageLayerData>[];
                _selectedImageIndex = -1;
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
          physics: _isManipulatingImage
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          itemCount: _pages.length,
          onPageChanged: (i) {
            _pages[_pageIndex] = _notifier.currentSketch;
            setState(() {
              _pageIndex = i;
              _selectedImageIndex = -1;
            });
            _notifier.setSketch(sketch: _pages[_pageIndex]);
            _requestInitForCurrentPage();
          },
          itemBuilder: (ctx, i) {
            final isCurrent = i == _pageIndex;
            final texts = _textsPages[i];
            final images = _imagePages[i];

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
                        // 1) รูปภาพชั้นล่าง: รับทัชเฉพาะโหมดแก้ไขรูป
                        IgnorePointer(
                          ignoring: !_editImagesMode,
                          child: Stack(
                            children: List.generate(images.length, (idx) {
                              final layer = images[idx];
                              return _ImageLayerWidget(
                                key: ValueKey('img-$i-$idx-${layer.id}'),
                                layer: layer,
                                selected: _selectedImageIndex == idx,
                                onSelected: () {
                                  setState(() => _selectedImageIndex = idx);
                                },
                                onChanged: (updated) {
                                  setState(() {
                                    _imagePages[i][idx] = updated;
                                  });
                                  _scheduleSync();
                                },
                                onManipulationStart: () =>
                                    setState(() => _isManipulatingImage = true),
                                onManipulationEnd: () =>
                                    setState(() => _isManipulatingImage = false),
                              );
                            }),
                          ),
                        ),

                        // 2) Scribble ด้านบน: รับทัชเฉพาะโหมดวาด → วาดทับรูปได้
                        IgnorePointer(
                          ignoring: _editImagesMode,
                          child: Scribble(
                            notifier: _notifier,
                            drawPen: !_isEraser,
                            drawEraser: _isEraser,
                          ),
                        ),

                        // 3) ข้อความอยู่บนสุด
                        ...texts.map((t) => _buildTextBoxWidget(t)),

                        // 4) แถบควบคุมรูป (เฉพาะโหมดแก้ไขรูป)
                        if (_editImagesMode) _selectedImageFloatingToolbar(),
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
                    _imagePages.add(<ImageLayerData>[]);
                    _selectedImageIndex = -1;
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
                    widget.socket!
                        .emit('add_page', {'boardId': widget.boardId, 'page': _pageIndex});
                  }
                },
                icon: const Icon(Icons.add_circle),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Delete this page',
                onPressed: (_pages.length > 1)
                    ? () async {
                        // ====== [ADDED] Confirm before delete ======
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('ลบหน้ากระดาษนี้?'),
                            content: Text('ยืนยันจะลบหน้า ${_pageIndex + 1} ใช่ไหม'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('ยกเลิก'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('ลบ'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        // ==========================================

                        final deletedIndex = _pageIndex;
                        _pendingSelfDeleteIndex = deletedIndex;
                        setState(() {
                          _pages.removeAt(deletedIndex);
                          _textsPages.removeAt(deletedIndex);
                          _imagePages.removeAt(deletedIndex);
                          _selectedImageIndex = -1;
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
                          widget.socket!.emit(
                            'delete_page',
                            {'boardId': widget.boardId, 'page': deletedIndex},
                          );
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

  /* ---------------- Floating toolbar for image ---------------- */

  Widget _selectedImageFloatingToolbar() {
    final hasSel = _selectedImageIndex >= 0 &&
        _selectedImageIndex < _imagePages[_pageIndex].length;

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Card(
          elevation: 3,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'ซูม −',
                onPressed: hasSel ? () => _zoomSelectedImage(1 / 1.15) : null,
                icon: const Icon(Icons.zoom_out),
              ),
              IconButton(
                tooltip: 'ซูม +',
                onPressed: hasSel ? () => _zoomSelectedImage(1.15) : null,
                icon: const Icon(Icons.zoom_in),
              ),
              IconButton(
                tooltip: 'ลบรูป',
                onPressed: hasSel ? _deleteSelectedImage : null,
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _zoomSelectedImage(double factor) {
    final idx = _selectedImageIndex;
    if (idx < 0 || idx >= _imagePages[_pageIndex].length) return;
    final cur = _imagePages[_pageIndex][idx];
    final next = cur.copyWith(
      scale: (cur.scale * factor).clamp(0.2, 6.0),
    );
    setState(() {
      _imagePages[_pageIndex][idx] = next;
    });
    _scheduleSync();
  }

  /* ---------------- Image layers ---------------- */

  Future<void> _addImageLayer() async {
    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final img = ImageLayerData(
        id: id,
        bytesB64: base64Encode(bytes),
        x: 140,
        y: 160,
        scale: 1.0,
        rotation: 0.0,
      );
      setState(() {
        _imagePages[_pageIndex] = [..._imagePages[_pageIndex], img];
        _selectedImageIndex = _imagePages[_pageIndex].length - 1;
      });
      _scheduleSync();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('เพิ่มรูปไม่สำเร็จ: $e')));
    }
  }

  void _deleteSelectedImage() {
    final idx = _selectedImageIndex;
    if (idx < 0 || idx >= _imagePages[_pageIndex].length) return;
    setState(() {
      final list = [..._imagePages[_pageIndex]];
      list.removeAt(idx);
      _imagePages[_pageIndex] = list;
      _selectedImageIndex = -1;
    });
    _scheduleSync();
  }

  void _bringImageToFront() {
    final idx = _selectedImageIndex;
    if (idx < 0 || idx >= _imagePages[_pageIndex].length) return;
    setState(() {
      final list = [..._imagePages[_pageIndex]];
      final l = list.removeAt(idx);
      list.add(l);
      _imagePages[_pageIndex] = list;
      _selectedImageIndex = list.length - 1;
    });
    _scheduleSync();
  }

  void _sendImageToBack() {
    final idx = _selectedImageIndex;
    if (idx < 0 || idx >= _imagePages[_pageIndex].length) return;
    setState(() {
      final list = [..._imagePages[_pageIndex]];
      final l = list.removeAt(idx);
      list.insert(0, l);
      _imagePages[_pageIndex] = list;
      _selectedImageIndex = 0;
    });
    _scheduleSync();
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
  late double _hue;   // 0..360
  late double _value; // 0..1

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

/* ---------------- Image layer widget ---------------- */

class _ImageLayerWidget extends StatefulWidget {
  final ImageLayerData layer;
  final bool selected;
  final VoidCallback onSelected;
  final ValueChanged<ImageLayerData> onChanged;
  final VoidCallback? onManipulationStart;
  final VoidCallback? onManipulationEnd;

  const _ImageLayerWidget({
    super.key,
    required this.layer,
    required this.selected,
    required this.onSelected,
    required this.onChanged,
    this.onManipulationStart,
    this.onManipulationEnd,
  });

  @override
  State<_ImageLayerWidget> createState() => _ImageLayerWidgetState();
}

class _ImageLayerWidgetState extends State<_ImageLayerWidget> {
  late ImageLayerData _state;
  Offset _focalStart = Offset.zero;
  double _startScale = 1.0;
  double _startRotation = 0.0;

  Uint8List _bytes = Uint8List(0);

  @override
  void initState() {
    super.initState();
    _state = widget.layer;
    _bytes = base64Decode(widget.layer.bytesB64);
  }

  @override
  void didUpdateWidget(covariant _ImageLayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layer != widget.layer) {
      _state = widget.layer;
      if (oldWidget.layer.bytesB64 != widget.layer.bytesB64) {
        _bytes = base64Decode(widget.layer.bytesB64);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => widget.onSelected(),
        onScaleStart: (details) {
          widget.onSelected();
          widget.onManipulationStart?.call();
          _focalStart = details.focalPoint;
          _startScale = _state.scale;
          _startRotation = _state.rotation;
        },
        onScaleEnd: (_) => widget.onManipulationEnd?.call(),
        onScaleUpdate: (details) {
          final translation = details.focalPoint - _focalStart;
          final updated = _state.copyWith(
            x: _state.x + translation.dx,
            y: _state.y + translation.dy,
            scale: (_startScale * details.scale).clamp(0.2, 6.0),
            rotation: _startRotation + details.rotation,
          );
          _focalStart = details.focalPoint;
          _state = updated;
          widget.onChanged(updated);
        },
        child: CustomSingleChildLayout(
          delegate: _CenteredAt(Offset(_state.x, _state.y)),
          child: Transform.rotate(
            angle: _state.rotation,
            child: Transform.scale(
              scale: _state.scale,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.memory(_bytes, fit: BoxFit.contain),
                  if (widget.selected)
                    IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                            strokeAlign: BorderSide.strokeAlignOutside,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CenteredAt extends SingleChildLayoutDelegate {
  final Offset center;
  _CenteredAt(this.center);

  @override
  bool shouldRelayout(covariant _CenteredAt oldDelegate) => oldDelegate.center != center;

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return Offset(center.dx - childSize.width / 2, center.dy - childSize.height / 2);
  }
}
