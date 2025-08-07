import 'package:flutter/material.dart';
import 'package:scribble/scribble.dart';

class NoteDrawingPage extends StatefulWidget {
  @override
  _NoteDrawingPageState createState() => _NoteDrawingPageState();
}

class _NoteDrawingPageState extends State<NoteDrawingPage> {
  late ScribbleNotifier notifier;

  @override
  void initState() {
    super.initState();
    notifier = ScribbleNotifier();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("เขียนโน้ตด้วยดินสอ"),
        actions: [
          IconButton(
            icon: Icon(Icons.undo),
            onPressed: notifier.canUndo ? notifier.undo : null,
          ),
          IconButton(
            icon: Icon(Icons.redo),
            onPressed: notifier.canRedo ? notifier.redo : null,
          ),
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: notifier.clear,
          ),
        ],
      ),
      body: Scribble(
        notifier: notifier,
        drawPen: true,
      ),
    );
  }
}
