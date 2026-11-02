import 'package:flutter/material.dart';

void main() {
  runApp(const PainterApp());
}

class PainterApp extends StatelessWidget {
  const PainterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Painter',
      home: Scaffold(
        body: Semantics(
          label: 'Canvas',
          child: ColoredBox(color: Colors.white),
        ),
      ),
    );
  }
}
