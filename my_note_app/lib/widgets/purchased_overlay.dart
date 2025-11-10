import 'package:flutter/material.dart';

class PurchasedOverlay extends StatelessWidget {
  final Widget child;
  final String label;
  final EdgeInsets padding;
  const PurchasedOverlay({
    super.key,
    required this.child,
    this.label = 'ซื้อแล้ว',
    this.padding = const EdgeInsets.all(10),
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          left: padding.left,
          top: padding.top,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check_circle, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text('ซื้อแล้ว',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
