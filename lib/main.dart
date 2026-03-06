import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Infinite Runner',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const InfiniteRunnerPage(),
    );
  }
}

class InfiniteRunnerPage extends StatefulWidget {
  const InfiniteRunnerPage({super.key});

  @override
  State<InfiniteRunnerPage> createState() => _InfiniteRunnerPageState();
}

class _InfiniteRunnerPageState extends State<InfiniteRunnerPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();

  Duration _lastElapsed = Duration.zero;

  double _screenWidth = 0;
  double _screenHeight = 0;

  // Mundo / jogador
  final double _groundHeight = 110;
  final double _playerSize = 42;
  final double _playerX = 80;
  final double _gravity = 1800;
  final double _jumpVelocity = -720;

  double _playerY = 0;
  double _playerVelocityY = 0;

  // Jogo
  bool _isPlaying = false;
  bool _gameOver = false;
  double _score = 0;
  int _highScore = 0;

  // Obstáculos
  final List<Obstacle> _obstacles = [];
  double _spawnTimer = 0;
  double _nextSpawnTime = 1.2;
  double _worldSpeed = 280;

  // Visual do chão
  double _groundStripeOffset = 0;

  double get _groundY => _screenHeight - _groundHeight - _playerSize;

  bool get _isOnGround => (_playerY - _groundY).abs() < 1.0;

  @override
  void initState() {
    super.initState();

    _ticker = createTicker((elapsed) {
      final delta = elapsed - _lastElapsed;
      _lastElapsed = elapsed;

      final dt = (delta.inMicroseconds / 1000000.0).clamp(0.0, 0.05);

      if (_screenWidth <= 0 || _screenHeight <= 0) {
        if (mounted) setState(() {});
        return;
      }

      if (_isPlaying && !_gameOver) {
        _updateGame(dt);
      }

      if (mounted) {
        setState(() {});
      }
    });

    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _updateGame(double dt) {
    // Física do jogador
    _playerVelocityY += _gravity * dt;
    _playerY += _playerVelocityY * dt;

    if (_playerY > _groundY) {
      _playerY = _groundY;
      _playerVelocityY = 0;
    }

    // Pontuação e velocidade
    _score += dt * 10;
    _worldSpeed = 280 + (_score * 2.2);

    // Movimento visual do chão
    _groundStripeOffset =
        (_groundStripeOffset + (_worldSpeed * dt)) % 42.0;

    // Spawn de obstáculos
    _spawnTimer += dt;
    if (_spawnTimer >= _nextSpawnTime) {
      _spawnObstacle();
      _spawnTimer = 0;
      _nextSpawnTime = 1.0 + _random.nextDouble() * 0.8;
    }

    // Move obstáculos
    for (final obstacle in _obstacles) {
      obstacle.x -= _worldSpeed * dt;
    }

    _obstacles.removeWhere((o) => o.x + o.width < -20);

    // Colisão
    _checkCollision();
  }

  void _spawnObstacle() {
    final width = 28 + _random.nextDouble() * 32;
    final height = 36 + _random.nextDouble() * 60;

    _obstacles.add(
      Obstacle(
        x: _screenWidth + 20,
        width: width,
        height: height,
      ),
    );
  }

  void _checkCollision() {
    final playerRect = Rect.fromLTWH(
      _playerX,
      _playerY,
      _playerSize,
      _playerSize,
    );

    for (final obstacle in _obstacles) {
      final obstacleRect = Rect.fromLTWH(
        obstacle.x,
        _screenHeight - _groundHeight - obstacle.height,
        obstacle.width,
        obstacle.height,
      );

      if (playerRect.overlaps(obstacleRect)) {
        _gameOver = true;
        _isPlaying = false;

        final finalScore = _score.floor();
        if (finalScore > _highScore) {
          _highScore = finalScore;
        }
        break;
      }
    }
  }

  void _jump() {
    if (_isOnGround) {
      _playerVelocityY = _jumpVelocity;
    }
  }

  void _startGame() {
    _isPlaying = true;
    _gameOver = false;
    _playerY = _groundY;
    _playerVelocityY = 0;
    _jump();
  }

  void _restartGame() {
    _obstacles.clear();
    _score = 0;
    _spawnTimer = 0;
    _nextSpawnTime = 1.0 + _random.nextDouble() * 0.6;
    _worldSpeed = 280;
    _groundStripeOffset = 0;
    _gameOver = false;
    _isPlaying = true;
    _playerY = _groundY;
    _playerVelocityY = 0;
    _jump();
  }

  void _handleAction() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }

    if (_screenWidth <= 0 || _screenHeight <= 0) return;

    if (_gameOver) {
      _restartGame();
      return;
    }

    if (!_isPlaying) {
      _startGame();
      return;
    }

    _jump();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.keyW) {
      _handleAction();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _screenWidth = constraints.maxWidth;
              _screenHeight = constraints.maxHeight;

              if (!_isPlaying && !_gameOver) {
                _playerY = _groundY;
              } else if (_playerY > _groundY) {
                _playerY = _groundY;
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleAction,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: RunnerPainter(
                          playerX: _playerX,
                          playerY: _playerY,
                          playerSize: _playerSize,
                          groundHeight: _groundHeight,
                          groundStripeOffset: _groundStripeOffset,
                          obstacles: _obstacles,
                          gameOver: _gameOver,
                        ),
                      ),
                    ),

                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _InfoCard(
                            title: 'Pontos',
                            value: _score.floor().toString(),
                          ),
                          _InfoCard(
                            title: 'Recorde',
                            value: _highScore.toString(),
                          ),
                        ],
                      ),
                    ),

                    if (!_isPlaying && !_gameOver)
                      const Center(
                        child: _OverlayMessage(
                          title: 'Infinite Runner',
                          subtitle:
                          'Toque na tela ou pressione Espaço / ↑ / W para começar',
                        ),
                      ),

                    if (_gameOver)
                      Center(
                        child: _OverlayMessage(
                          title: 'Game Over',
                          subtitle:
                          'Pontuação: ${_score.floor()}\nToque para reiniciar',
                        ),
                      ),

                    const Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Text(
                        'Controles: toque, Espaço, seta para cima ou W',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class Obstacle {
  Obstacle({
    required this.x,
    required this.width,
    required this.height,
  });

  double x;
  final double width;
  final double height;
}

class RunnerPainter extends CustomPainter {
  RunnerPainter({
    required this.playerX,
    required this.playerY,
    required this.playerSize,
    required this.groundHeight,
    required this.groundStripeOffset,
    required this.obstacles,
    required this.gameOver,
  });

  final double playerX;
  final double playerY;
  final double playerSize;
  final double groundHeight;
  final double groundStripeOffset;
  final List<Obstacle> obstacles;
  final bool gameOver;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawGround(canvas, size);
    _drawObstacles(canvas, size);
    _drawPlayer(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final backgroundRect = Offset.zero & size;

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0B1021),
          Color(0xFF182848),
          Color(0xFF243B55),
        ],
      ).createShader(backgroundRect);

    canvas.drawRect(backgroundRect, bgPaint);

    // Estrelas / pontos
    final starPaint = Paint()..color = Colors.white24;
    for (int i = 0; i < 26; i++) {
      final dx = (i * 97.0) % size.width;
      final dy = 20 + ((i * 53.0) % (size.height * 0.35));
      final radius = i % 3 == 0 ? 2.0 : 1.2;
      canvas.drawCircle(Offset(dx, dy), radius, starPaint);
    }

    // Blocos ao fundo simulando cidade / cenário
    final farPaint = Paint()..color = const Color(0xFF101B32).withOpacity(0.55);
    final midPaint = Paint()..color = const Color(0xFF16233F).withOpacity(0.8);

    final horizonY = size.height - groundHeight - 60;

    for (int i = 0; i < 10; i++) {
      final x = i * (size.width / 9) - 20;
      final w = 30 + (i % 3) * 18.0;
      final h = 40 + (i % 4) * 22.0;
      canvas.drawRect(
        Rect.fromLTWH(x, horizonY - h, w, h),
        farPaint,
      );
    }

    for (int i = 0; i < 8; i++) {
      final x = i * (size.width / 7) + 10;
      final w = 36 + (i % 2) * 20.0;
      final h = 55 + (i % 3) * 28.0;
      canvas.drawRect(
        Rect.fromLTWH(x, horizonY - h + 20, w, h),
        midPaint,
      );
    }
  }

  void _drawGround(Canvas canvas, Size size) {
    final groundTop = size.height - groundHeight;

    final groundPaint = Paint()..color = const Color(0xFF2D2A32);
    final linePaint = Paint()..color = const Color(0xFF615D68);
    final stripePaint = Paint()..color = const Color(0xFF494552);

    canvas.drawRect(
      Rect.fromLTWH(0, groundTop, size.width, groundHeight),
      groundPaint,
    );

    canvas.drawRect(
      Rect.fromLTWH(0, groundTop, size.width, 4),
      linePaint,
    );

    const stripeWidth = 26.0;
    const stripeGap = 16.0;
    double x = -groundStripeOffset;

    while (x < size.width + stripeWidth) {
      canvas.drawRect(
        Rect.fromLTWH(x, groundTop + 44, stripeWidth, 10),
        stripePaint,
      );
      x += stripeWidth + stripeGap;
    }
  }

  void _drawObstacles(Canvas canvas, Size size) {
    final groundTop = size.height - groundHeight;

    final obstaclePaint = Paint()..color = const Color(0xFFE85D75);
    final accentPaint = Paint()..color = const Color(0xFFB23A48);

    for (final obstacle in obstacles) {
      final rect = Rect.fromLTWH(
        obstacle.x,
        groundTop - obstacle.height,
        obstacle.width,
        obstacle.height,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        obstaclePaint,
      );

      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + 4,
          rect.top + 6,
          rect.width - 8,
          6,
        ),
        accentPaint,
      );
    }
  }

  void _drawPlayer(Canvas canvas, Size size) {
    final groundTop = size.height - groundHeight;

    final shadowPaint = Paint()..color = Colors.black26;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(playerX + playerSize / 2, groundTop + 6),
        width: playerSize * 0.8,
        height: 10,
      ),
      shadowPaint,
    );

    final playerRect = Rect.fromLTWH(
      playerX,
      playerY,
      playerSize,
      playerSize,
    );

    final bodyPaint = Paint()
      ..color = gameOver
          ? const Color(0xFFFF6B6B)
          : const Color(0xFF4ECDC4);

    canvas.drawRRect(
      RRect.fromRectAndRadius(playerRect, const Radius.circular(8)),
      bodyPaint,
    );

    final eyeWhitePaint = Paint()..color = Colors.white;
    final pupilPaint = Paint()..color = Colors.black87;
    final detailPaint = Paint()..color = Colors.black12;

    canvas.drawCircle(
      Offset(
        playerX + playerSize * 0.68,
        playerY + playerSize * 0.33,
      ),
      4,
      eyeWhitePaint,
    );

    canvas.drawCircle(
      Offset(
        playerX + playerSize * 0.70,
        playerY + playerSize * 0.33,
      ),
      2,
      pupilPaint,
    );

    canvas.drawRect(
      Rect.fromLTWH(
        playerX + 8,
        playerY + playerSize - 8,
        playerSize - 16,
        4,
      ),
      detailPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayMessage extends StatelessWidget {
  const _OverlayMessage({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 28),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}