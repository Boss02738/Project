import 'package:flutter/material.dart';

class ReportPostDialog extends StatefulWidget {
  final int postId;
  final int userId;
  final Future<void> Function({required String reason, String? details}) onSubmit;

  const ReportPostDialog({
    super.key,
    required this.postId,
    required this.userId,
    required this.onSubmit,
  });

  @override
  State<ReportPostDialog> createState() => _ReportPostDialogState();
}

class _ReportPostDialogState extends State<ReportPostDialog> {
  String? _reason;
  final _details = TextEditingController();
  bool _loading = false;

  final reasons = const [
    'สแปม (Spam)',
    'เนื้อหาไม่เหมาะสมทางเพศ',
    'ความรุนแรง / เกลียดชัง',
    'ฉ้อโกง / หลอกลวง',
    'ละเมิดลิขสิทธิ์',
    'คุกคาม / บูลลี่',
    'อื่น ๆ',
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('รายงานโพสต์นี้'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in reasons)
              RadioListTile<String>(
                value: r,
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v),
                title: Text(r),
                dense: true,
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _details,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'รายละเอียดเพิ่มเติม (ถ้ามี)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: (_reason == null || _loading)
              ? null
              : () async {
                  setState(() => _loading = true);
                  try {
                    await widget.onSubmit(reason: _reason!, details: _details.text);
                    if (context.mounted) Navigator.pop(context, true);
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                },
          child: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('ส่งรายงาน'),
        ),
      ],
    );
  }
}
