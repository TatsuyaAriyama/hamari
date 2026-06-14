import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'game/hamari_game.dart';

void main() {
  runApp(const HamariApp());
}

class HamariApp extends StatelessWidget {
  const HamariApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Hamari',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: GameWidget.controlled(gameFactory: HamariGame.new),
      ),
    );
  }
}
