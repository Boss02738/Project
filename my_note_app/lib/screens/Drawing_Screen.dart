import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart'; // สำหรับ RenderRepaintBoundary

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scribble/scribble.dart';

class NoteScribblePage extends StatefulWidget {
  const NoteScribblePage({super.key});

  @override
  State<NoteScribblePage> createState() => _NoteScribblePageState();
}

class _NoteScribblePageState extends State<NoteScribblePage> {
  late final ScribbleNotifier _notifier;
  final GlobalKey _repaintKey = GlobalKey();

  // พาเลตสีที่ให้เลือก
  final List<Color> _colors = const [
    Colors.black,
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.brown,
    Colors.grey,
  ];

  double _strokeWidth = 3.0;

  // เก็บ state ฝั่งเราเองเพื่อเลี่ยง breaking changes ของแพ็กเกจ
  late Color _currentColor;
  bool _isEraser = false;

  @override
  void initState() {
    super.initState();
    _currentColor = _colors.first;
    _notifier = ScribbleNotifier()
      ..setColor(_currentColor)
      ..setStrokeWidth(_strokeWidth);
  }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  Future<void> _exportToImage() async {
    try {
      // แปลงพื้นที่วาดให้เป็น PNG ผ่าน RepaintBoundary
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่พบพื้นที่วาด')),
          );
        }
        return;
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception("ไม่สามารถแปลงภาพเป็น PNG ได้");

      final Uint8List bytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/note_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกรูปแล้ว: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export ไม่สำเร็จ: $e')),
        );
      }
    }
  }

  Widget _buildToolButton({
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? Colors.black.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon),
        ),
      ),
    );
  }

  Widget _buildColorDot(Color c) {
    final isActive = !_isEraser && (_currentColor.value == c.value);
    return InkWell(
      onTap: () {
        _notifier.setColor(c); // สลับออกจากยางลบอัตโนมัติในบางเวอร์ชัน แต่กันเหนียวเราอัปเดต state เองด้วย
        setState(() {
          _currentColor = c;
          _isEraser = false;
        });
      },
      customBorder: const CircleBorder(),
      child: Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? Colors.black : Colors.black12,
            width: isActive ? 2 : 1,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEraser = _isEraser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('เขียนโน้ตด้วยดินสอ'),
        centerTitle: true,
        actions: [
          // Export PNG
          IconButton(
            tooltip: 'บันทึกเป็น PNG',
            onPressed: _exportToImage,
            icon: const Icon(Icons.download),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // แถบเครื่องมือด้านบน
          Material(
            color: Colors.white,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // ปากกา
                  _buildToolButton(
                    selected: !isEraser,
                    icon: Icons.edit,
                    tooltip: 'ปากกา',
                    onTap: () {
                      // กลับสู่โหมดปากกาโดยใช้สีล่าสุด
                      _notifier.setColor(_currentColor);
                      setState(() {
                        _isEraser = false;
                      });
                    },
                  ),

                  // ยางลบ
                  _buildToolButton(
                    selected: isEraser,
                    icon: Icons.cleaning_services_outlined,
                    tooltip: 'ยางลบ',
                    onTap: () {
                      _notifier.setEraser(); // เวอร์ชันใหม่ไม่มีพารามิเตอร์
                      setState(() {
                        _isEraser = true;
                      });
                    },
                  ),

                  const VerticalDivider(width: 16, thickness: 1),

                  // Undo / Redo — ใช้ AnimatedBuilder ให้ปุ่มอัปเดตตาม notifier
                  AnimatedBuilder(
                    animation: _notifier,
                    builder: (_, __) => IconButton(
                      tooltip: 'ย้อนกลับ (Undo)',
                      onPressed: _notifier.canUndo ? _notifier.undo : null,
                      icon: const Icon(Icons.undo),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _notifier,
                    builder: (_, __) => IconButton(
                      tooltip: 'ทำซ้ำ (Redo)',
                      onPressed: _notifier.canRedo ? _notifier.redo : null,
                      icon: const Icon(Icons.redo),
                    ),
                  ),

                  const Spacer(),

                  // สี
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: _colors.map(_buildColorDot).toList()),
                  ),

                  const SizedBox(width: 12),

                  // ความหนาเส้น
                  SizedBox(
                    width: 160,
                    child: Row(
                      children: [
                        const Icon(Icons.brush, size: 18),
                        Expanded(
                          child: Slider(
                            min: 1,
                            max: 15,
                            value: _strokeWidth,
                            label: _strokeWidth.toStringAsFixed(0),
                            onChanged: (v) {
                              setState(() => _strokeWidth = v);
                              _notifier.setStrokeWidth(v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ล้างกระดาน
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _notifier.clear,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('ล้าง'),
                  ),
                ],
              ),
            ),
          ),

          // พื้นที่วาด
          Expanded(
            child: Container(
              color: const Color(0xFFF7F7F7),
              alignment: Alignment.center,
              child: AspectRatio(
                aspectRatio: 3 / 4, // กระดาษแนว A-ish
                child: RepaintBoundary(
                  key: _repaintKey,
                  child: Container(
                    color: Colors.white,
                    child: Stack(
                      children: [
                        // (ถ้าต้องการ เส้นบรรทัด ให้ใส่ CustomPaint ตรงนี้)
                        Positioned.fill(
                          child: Scribble(
                            notifier: _notifier,
                            // drawPen / drawEraser สามารถเปิดเพื่อแสดงหัวปากกา/ยางลบบนเคอร์เซอร์ได้ในบางแพลตฟอร์ม
                            // drawPen: true,
                            // drawEraser: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
