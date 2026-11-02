import 'package:flutter/material.dart';

import 'canvas/canvas_controller.dart';
import 'canvas/canvas_view.dart';

void main() {
  runApp(const PainterApp());
}

class PainterApp extends StatefulWidget {
  const PainterApp({super.key});

  @override
  State<PainterApp> createState() => _PainterAppState();
}

class _PainterAppState extends State<PainterApp> {
  final CanvasController _controller = CanvasController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Painter',
      home: Scaffold(body: CanvasView(controller: _controller)),
    );
  }
}
