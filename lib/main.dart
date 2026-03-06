import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infinite Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF08111F),
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
  static const String _highScoreKey = 'infinite_runner_high_score';

  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();

  SharedPreferences? _prefs;
  Duration _lastElapsed = Duration.zero;

  double _screenWidth = 0;
  double _screenHeight = 0;

  final double _groundHeight = 112;
  final double _playerSize = 42;
  final double _playerX = 84;

  final double _gravity = 1850;
  final double _jumpVelocity = -760;

  double _playerY = 0;
  double _playerVelocityY = 0;
  int _jumpsUsed = 0;
  final int _maxJumps = 2;

  bool _isPlaying = false;
  bool _gameOver = false;
  bool _isPaused = false;

  double _score = 0;
  int _coinsCollected = 0;
  int _highScore = 0;
  int _difficultyLevel = 1;

  double _worldSpeed = 250;
  double _groundStripeOffset = 0;

  double _animationTime = 0;
  double _farParallaxOffset = 0;
  double _midParallaxOffset = 0;
  double _nearParallaxOffset = 0;

  double _obstacleSpawnTimer = 0;
  double _nextObstacleSpawnTime = 1.45;
  double _coinSpawnTimer = 0;
  double _nextCoinSpawnTime = 1.15;

  int _lastCoinSoundAtMs = 0;

  final List<Obstacle> _obstacles = [];
  final List<CoinItem> _coins = [];

  double get _groundTop => _screenHeight - _groundHeight;
  double get _playerGroundY => _groundTop - _playerSize;

  @override
  void initState() {
    super.initState();
    _loadHighScore();

    _ticker = createTicker(_onTick)..start();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHighScore = prefs.getInt(_highScoreKey) ?? 0;

    if (!mounted) return;

    setState(() {
      _prefs = prefs;
      _highScore = savedHighScore;
    });
  }

  Future<void> _saveHighScore() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setInt(_highScoreKey, _highScore);
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;

    final dt = (delta.inMicroseconds / 1000000.0).clamp(0.0, 0.05);

    if (_screenWidth <= 0 || _screenHeight <= 0) {
      if (mounted) setState(() {});
      return;
    }

    if (_isPlaying && !_gameOver && !_isPaused) {
      _updateGame(dt);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _updateGame(double dt) {
    _animationTime += dt;
    _updateDifficulty();

    _playerVelocityY += _gravity * dt;
    _playerY += _playerVelocityY * dt;

    if (_playerY >= _playerGroundY) {
      _playerY = _playerGroundY;
      _playerVelocityY = 0;
      _jumpsUsed = 0;
    }

    _score += dt * (7.5 + (_difficultyLevel - 1) * 0.18);

    _groundStripeOffset = (_groundStripeOffset + (_worldSpeed * dt)) % 44.0;
    _farParallaxOffset = (_farParallaxOffset + (_worldSpeed * 0.07 * dt)) % 420;
    _midParallaxOffset = (_midParallaxOffset + (_worldSpeed * 0.14 * dt)) % 520;
    _nearParallaxOffset = (_nearParallaxOffset + (_worldSpeed * 0.24 * dt)) % 620;

    _obstacleSpawnTimer += dt;
    if (_obstacleSpawnTimer >= _nextObstacleSpawnTime) {
      _spawnObstacleWave();
      _obstacleSpawnTimer = 0;
      _scheduleNextObstacleSpawn();
    }

    _coinSpawnTimer += dt;
    if (_coinSpawnTimer >= _nextCoinSpawnTime) {
      _spawnCoinPattern();
      _coinSpawnTimer = 0;
      _scheduleNextCoinSpawn();
    }

    for (final obstacle in _obstacles) {
      obstacle.x -= _worldSpeed * dt;
    }
    _obstacles.removeWhere((o) => o.x + o.width < -24);

    for (final coin in _coins) {
      coin.x -= _worldSpeed * dt;
    }
    _coins.removeWhere((c) => c.x + c.size < -20);

    _checkCollisions();
  }

  void _updateDifficulty() {
    _difficultyLevel = max(1, 1 + (_score ~/ 40));

    final ramp = min(_score / 35.0, 10.0);
    _worldSpeed = 250 + ramp * 11;
  }

  void _scheduleNextObstacleSpawn() {
    final ramp = min(_score / 40.0, 8.0);
    final base = max(0.95, 1.55 - ramp * 0.05);
    _nextObstacleSpawnTime = base + _random.nextDouble() * 0.38;
  }

  void _scheduleNextCoinSpawn() {
    final ramp = min(_score / 45.0, 8.0);
    final base = max(0.95, 1.20 - ramp * 0.03);
    _nextCoinSpawnTime = base + _random.nextDouble() * 0.40;
  }

  void _spawnObstacleWave() {
    final startX = _screenWidth + 20;
    final difficultyBias = min(_score / 70.0, 3.0);

    int count = 1;
    if (_score >= 80 && _random.nextDouble() < 0.18) {
      count = 2;
    }

    double currentX = startX;

    for (int i = 0; i < count; i++) {
      final width = 30 + _random.nextDouble() * 20 + difficultyBias * 3;
      final height = 34 + _random.nextDouble() * (42 + difficultyBias * 10);

      _obstacles.add(
        Obstacle(
          x: currentX,
          width: width,
          height: height,
        ),
      );

      currentX += 150 + _random.nextDouble() * 70;
    }
  }

  void _spawnCoinPattern() {
    final startX = _screenWidth + 60;
    final isArc = _random.nextBool();

    int count;
    if (_score < 50) {
      count = 3 + _random.nextInt(2);
    } else {
      count = 3 + _random.nextInt(3);
    }

    final spacing = 42.0;
    final baseHeight = 95 + _random.nextDouble() * 90;

    for (int i = 0; i < count; i++) {
      final x = startX + i * spacing;
      double y = _groundTop - baseHeight;

      if (isArc) {
        final progress = count == 1 ? 0.0 : i / (count - 1);
        final arcOffset = sin(progress * pi) * 26;
        y -= arcOffset;
      } else {
        y -= (i.isEven ? 0 : 10);
      }

      final safeY = _adjustCoinYToAvoidObstacles(
        x: x,
        proposedY: y,
        size: 18,
      );

      if (safeY != null) {
        _coins.add(
          CoinItem(
            x: x,
            baseY: safeY,
            size: 18,
            phase: _random.nextDouble() * pi * 2,
          ),
        );
      }
    }
  }

  double? _adjustCoinYToAvoidObstacles({
    required double x,
    required double proposedY,
    required double size,
  }) {
    double y = proposedY;

    for (int attempt = 0; attempt < 6; attempt++) {
      final coinRect = Rect.fromLTWH(x, y - 10, size, size + 20);
      bool hasOverlap = false;
      double highestTop = double.infinity;

      for (final obstacle in _obstacles) {
        final obstacleRect = Rect.fromLTWH(
          obstacle.x - 6,
          _groundTop - obstacle.height - 6,
          obstacle.width + 12,
          obstacle.height + 12,
        );

        if (coinRect.overlaps(obstacleRect)) {
          hasOverlap = true;
          highestTop = min(highestTop, obstacleRect.top);
        }
      }

      if (!hasOverlap) {
        return y;
      }

      y = highestTop - size - 26;
    }

    if (y < 40) {
      return null;
    }

    return y;
  }

  double _coinVisualY(CoinItem coin) {
    return coin.baseY + sin((_animationTime * 4.2) + coin.phase) * 8.0;
  }

  void _checkCollisions() {
    final playerRect = Rect.fromLTWH(
      _playerX,
      _playerY,
      _playerSize,
      _playerSize,
    );

    for (final obstacle in _obstacles) {
      final obstacleRect = Rect.fromLTWH(
        obstacle.x,
        _groundTop - obstacle.height,
        obstacle.width,
        obstacle.height,
      );

      if (playerRect.overlaps(obstacleRect)) {
        _handleGameOver();
        return;
      }
    }

    for (int i = _coins.length - 1; i >= 0; i--) {
      final coin = _coins[i];
      final coinRect = Rect.fromLTWH(
        coin.x,
        _coinVisualY(coin),
        coin.size,
        coin.size,
      );

      if (playerRect.overlaps(coinRect)) {
        _coinsCollected += 1;
        _score += 1.5;
        _coins.removeAt(i);
        _playCoinSound();
      }
    }
  }

  void _handleGameOver() {
    _gameOver = true;
    _isPlaying = false;
    _isPaused = false;

    final finalScore = _score.floor();
    if (finalScore > _highScore) {
      _highScore = finalScore;
      _saveHighScore();
    }
  }

  void _playJumpSound() {
    SystemSound.play(SystemSoundType.click);
  }

  void _playCoinSound() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCoinSoundAtMs < 90) return;

    _lastCoinSoundAtMs = now;
    SystemSound.play(SystemSoundType.click);

    Future.delayed(const Duration(milliseconds: 45), () {
      if (!mounted || _gameOver) return;
      SystemSound.play(SystemSoundType.click);
    });
  }

  void _jump() {
    if (!_isPlaying || _gameOver || _isPaused) return;
    if (_jumpsUsed >= _maxJumps) return;

    _playerVelocityY =
    _jumpsUsed == 0 ? _jumpVelocity : _jumpVelocity * 0.92;
    _jumpsUsed += 1;
    _playJumpSound();
  }

  void _resetWorld({required bool startPlaying, bool autoJump = false}) {
    _obstacles.clear();
    _coins.clear();

    _score = 0;
    _coinsCollected = 0;
    _difficultyLevel = 1;
    _worldSpeed = 250;
    _groundStripeOffset = 0;

    _animationTime = 0;
    _farParallaxOffset = 0;
    _midParallaxOffset = 0;
    _nearParallaxOffset = 0;

    _playerY = _playerGroundY;
    _playerVelocityY = 0;
    _jumpsUsed = 0;

    _obstacleSpawnTimer = 0;
    _coinSpawnTimer = 0;
    _scheduleNextObstacleSpawn();
    _scheduleNextCoinSpawn();

    _gameOver = false;
    _isPaused = false;
    _isPlaying = startPlaying;

    if (autoJump) {
      _jump();
    }
  }

  void _startGame() {
    _resetWorld(startPlaying: true, autoJump: true);
  }

  void _restartGame() {
    _resetWorld(startPlaying: true, autoJump: true);
  }

  void _togglePause() {
    if (!_isPlaying || _gameOver) return;

    setState(() {
      _isPaused = !_isPaused;
    });
  }

  void _handlePrimaryAction() {
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

    if (_isPaused) {
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
      _handlePrimaryAction();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyP ||
        key == LogicalKeyboardKey.escape) {
      _togglePause();
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
                _playerY = _playerGroundY;
              } else if (_playerY > _playerGroundY) {
                _playerY = _playerGroundY;
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handlePrimaryAction,
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
                          farParallaxOffset: _farParallaxOffset,
                          midParallaxOffset: _midParallaxOffset,
                          nearParallaxOffset: _nearParallaxOffset,
                          obstacles: _obstacles,
                          coins: _coins,
                          jumpsRemaining: _maxJumps - _jumpsUsed,
                          gameOver: _gameOver,
                          isPaused: _isPaused,
                          animationTime: _animationTime,
                        ),
                      ),
                    ),

                    Positioned(
                      top: 14,
                      left: 14,
                      right: 14,
                      child: Row(
                        children: [
                          Expanded(
                            child: TopHudBar(
                              score: _score.floor(),
                              coins: _coinsCollected,
                            ),
                          ),
                          const SizedBox(width: 10),
                          PauseButton(
                            isPaused: _isPaused,
                            onTap: _togglePause,
                          ),
                        ],
                      ),
                    ),

                    if (!_isPlaying && !_gameOver)
                      Center(
                        child: OverlayPanel(
                          title: 'Infinite Runner',
                          subtitle:
                          'Recorde: $_highScore\n\n'
                              'Toque na tela ou pressione Espaço / ↑ / W para começar.\n'
                              'Duplo pulo, moedas flutuantes, parallax e pausa com P.',
                        ),
                      ),

                    if (_isPaused)
                      const Center(
                        child: OverlayPanel(
                          title: 'Pausado',
                          subtitle:
                          'Pressione P, ESC ou o botão de pausa para continuar.',
                        ),
                      ),

                    if (_gameOver)
                      const Center(
                        child: OverlayPanel(
                          title: 'Game Over',
                          subtitle: 'Toque para reiniciar.',
                        ),
                      ),

                    if (_gameOver)
                      Positioned(
                        left: 22,
                        right: 22,
                        bottom: 70,
                        child: ResultSummary(
                          score: _score.floor(),
                          coins: _coinsCollected,
                          highScore: _highScore,
                        ),
                      ),

                    const Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Text(
                        'Controles: toque, Espaço, ↑, W | Pausa: P ou ESC',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
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

class CoinItem {
  CoinItem({
    required this.x,
    required this.baseY,
    required this.size,
    required this.phase,
  });

  double x;
  final double baseY;
  final double size;
  final double phase;
}

class RunnerPainter extends CustomPainter {
  RunnerPainter({
    required this.playerX,
    required this.playerY,
    required this.playerSize,
    required this.groundHeight,
    required this.groundStripeOffset,
    required this.farParallaxOffset,
    required this.midParallaxOffset,
    required this.nearParallaxOffset,
    required this.obstacles,
    required this.coins,
    required this.jumpsRemaining,
    required this.gameOver,
    required this.isPaused,
    required this.animationTime,
  });

  final double playerX;
  final double playerY;
  final double playerSize;
  final double groundHeight;
  final double groundStripeOffset;
  final double farParallaxOffset;
  final double midParallaxOffset;
  final double nearParallaxOffset;
  final List<Obstacle> obstacles;
  final List<CoinItem> coins;
  final int jumpsRemaining;
  final bool gameOver;
  final bool isPaused;
  final double animationTime;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawMoon(canvas, size);
    _drawParallaxLayers(canvas, size);
    _drawGround(canvas, size);
    _drawCoins(canvas);
    _drawObstacles(canvas, size);
    _drawPlayer(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF091120),
          Color(0xFF13233F),
          Color(0xFF1F3B61),
          Color(0xFF0F1826),
        ],
      ).createShader(rect);

    canvas.drawRect(rect, bgPaint);

    final starPaint = Paint()..color = Colors.white24;
    for (int i = 0; i < 28; i++) {
      final dx = (i * 91.0) % size.width;
      final dy = 24 + ((i * 57.0) % (size.height * 0.34));
      final radius = i % 4 == 0 ? 2.0 : 1.2;
      canvas.drawCircle(Offset(dx, dy), radius, starPaint);
    }
  }

  void _drawMoon(Canvas canvas, Size size) {
    final moonPaint = Paint()..color = const Color(0x33FFFFFF);
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.16),
      36,
      moonPaint,
    );

    final cutPaint = Paint()..color = const Color(0xFF13233F);
    canvas.drawCircle(
      Offset(size.width * 0.845, size.height * 0.145),
      30,
      cutPaint,
    );
  }

  void _drawParallaxLayers(Canvas canvas, Size size) {
    final farY = size.height - groundHeight - 80;
    final midY = size.height - groundHeight - 60;
    final nearY = size.height - groundHeight - 42;

    _drawCityLayer(
      canvas,
      size,
      baseY: farY,
      offset: farParallaxOffset,
      color: const Color(0xFF0F2038).withOpacity(0.45),
      minWidth: 26,
      widthRange: 20,
      minHeight: 30,
      heightRange: 30,
      gap: 16,
    );

    _drawCityLayer(
      canvas,
      size,
      baseY: midY,
      offset: midParallaxOffset,
      color: const Color(0xFF152744).withOpacity(0.72),
      minWidth: 30,
      widthRange: 24,
      minHeight: 40,
      heightRange: 42,
      gap: 14,
    );

    _drawCityLayer(
      canvas,
      size,
      baseY: nearY,
      offset: nearParallaxOffset,
      color: const Color(0xFF1B3154).withOpacity(0.95),
      minWidth: 36,
      widthRange: 28,
      minHeight: 55,
      heightRange: 46,
      gap: 12,
    );
  }

  void _drawCityLayer(
      Canvas canvas,
      Size size, {
        required double baseY,
        required double offset,
        required Color color,
        required double minWidth,
        required double widthRange,
        required double minHeight,
        required double heightRange,
        required double gap,
      }) {
    final paint = Paint()..color = color;

    double x = -offset;
    int i = 0;

    while (x < size.width + 120) {
      final width = minWidth + (i % 4) * (widthRange / 3);
      final height = minHeight + ((i * 7) % 5) * (heightRange / 4);

      canvas.drawRect(
        Rect.fromLTWH(x, baseY - height, width, height),
        paint,
      );

      if (i.isEven) {
        canvas.drawRect(
          Rect.fromLTWH(x + width * 0.22, baseY - height - 10, width * 0.16, 10),
          paint,
        );
      }

      x += width + gap;
      i++;
    }
  }

  void _drawGround(Canvas canvas, Size size) {
    final groundTop = size.height - groundHeight;

    final groundPaint = Paint()..color = const Color(0xFF25232B);
    final topLinePaint = Paint()..color = const Color(0xFF5B5963);
    final stripePaint = Paint()..color = const Color(0xFF4B4754);
    final dotPaint = Paint()..color = const Color(0xFF3A3741);

    canvas.drawRect(
      Rect.fromLTWH(0, groundTop, size.width, groundHeight),
      groundPaint,
    );

    canvas.drawRect(
      Rect.fromLTWH(0, groundTop, size.width, 4),
      topLinePaint,
    );

    double x = -groundStripeOffset;
    const stripeWidth = 28.0;
    const stripeGap = 16.0;

    while (x < size.width + stripeWidth) {
      canvas.drawRect(
        Rect.fromLTWH(x, groundTop + 44, stripeWidth, 10),
        stripePaint,
      );
      x += stripeWidth + stripeGap;
    }

    for (int i = 0; i < 30; i++) {
      final dx = (i * 41.0) % size.width;
      final dy = groundTop + 18 + (i % 3) * 18.0;
      canvas.drawCircle(Offset(dx, dy), 1.8, dotPaint);
    }
  }

  double _coinVisualY(CoinItem coin) {
    return coin.baseY + sin((animationTime * 4.2) + coin.phase) * 8.0;
  }

  void _drawCoins(Canvas canvas) {
    final outerPaint = Paint()..color = const Color(0xFFFFD54F);
    final innerPaint = Paint()..color = const Color(0xFFFFB300);
    final shinePaint = Paint()..color = Colors.white70;

    for (final coin in coins) {
      final y = _coinVisualY(coin);
      final center = Offset(coin.x + coin.size / 2, y + coin.size / 2);

      canvas.drawCircle(center, coin.size / 2, outerPaint);
      canvas.drawCircle(center, coin.size / 2.8, innerPaint);
      canvas.drawCircle(
        Offset(center.dx - 3, center.dy - 3),
        2.5,
        shinePaint,
      );
    }
  }

  void _drawObstacles(Canvas canvas, Size size) {
    final groundTop = size.height - groundHeight;

    final obstaclePaint = Paint()..color = const Color(0xFFE86A7A);
    final accentPaint = Paint()..color = const Color(0xFFB34052);
    final edgePaint = Paint()..color = const Color(0x55FFFFFF);

    for (final obstacle in obstacles) {
      final rect = Rect.fromLTWH(
        obstacle.x,
        groundTop - obstacle.height,
        obstacle.width,
        obstacle.height,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        obstaclePaint,
      );

      canvas.drawRect(
        Rect.fromLTWH(rect.left + 4, rect.top + 6, rect.width - 8, 7),
        accentPaint,
      );

      canvas.drawRect(
        Rect.fromLTWH(rect.left + 3, rect.top + 3, rect.width - 6, 2),
        edgePaint,
      );
    }
  }

  void _drawPlayer(Canvas canvas, Size size) {
    final groundTop = size.height - groundHeight;

    final shadowPaint = Paint()..color = Colors.black26;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(playerX + playerSize / 2, groundTop + 8),
        width: playerSize * 0.86,
        height: 11,
      ),
      shadowPaint,
    );

    final bodyRect = Rect.fromLTWH(
      playerX,
      playerY,
      playerSize,
      playerSize,
    );

    final bodyColor = gameOver
        ? const Color(0xFFFF6B6B)
        : isPaused
        ? const Color(0xFF8AC6D1)
        : const Color(0xFF50E3C2);

    final bodyPaint = Paint()..color = bodyColor;
    final detailPaint = Paint()..color = Colors.black12;
    final eyePaint = Paint()..color = Colors.white;
    final pupilPaint = Paint()..color = Colors.black87;
    final jumpPaint = Paint()..color = const Color(0x88FFFFFF);

    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(9)),
      bodyPaint,
    );

    canvas.drawRect(
      Rect.fromLTWH(playerX + 8, playerY + playerSize - 8, playerSize - 16, 4),
      detailPaint,
    );

    canvas.drawCircle(
      Offset(playerX + playerSize * 0.66, playerY + playerSize * 0.32),
      4.4,
      eyePaint,
    );

    canvas.drawCircle(
      Offset(playerX + playerSize * 0.70, playerY + playerSize * 0.32),
      2.0,
      pupilPaint,
    );

    for (int i = 0; i < jumpsRemaining; i++) {
      canvas.drawCircle(
        Offset(playerX + 10 + i * 10, playerY - 8),
        3.2,
        jumpPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RunnerPainter oldDelegate) => true;
}

class TopHudBar extends StatelessWidget {
  const TopHudBar({
    super.key,
    required this.score,
    required this.coins,
  });

  final int score;
  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [
            Color(0xAA101B2D),
            Color(0xAA1C2D4A),
          ],
        ),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.speed_rounded, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          Text(
            'Pontos: $score',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          const Icon(
            Icons.monetization_on_rounded,
            size: 18,
            color: Color(0xFFFFD54F),
          ),
          const SizedBox(width: 6),
          Text(
            '$coins',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class PauseButton extends StatelessWidget {
  const PauseButton({
    super.key,
    required this.isPaused,
    required this.onTap,
  });

  final bool isPaused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [
                Color(0xAA101B2D),
                Color(0xAA24395C),
              ],
            ),
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(
            isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class ResultSummary extends StatelessWidget {
  const ResultSummary({
    super.key,
    required this.score,
    required this.coins,
    required this.highScore,
  });

  final int score;
  final int coins;
  final int highScore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [
            Color(0xCC101A2C),
            Color(0xCC213558),
          ],
        ),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ResultItem(label: 'Pontuação', value: '$score'),
          _ResultItem(label: 'Moedas', value: '$coins'),
          _ResultItem(label: 'Recorde', value: '$highScore'),
        ],
      ),
    );
  }
}

class _ResultItem extends StatelessWidget {
  const _ResultItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class OverlayPanel extends StatelessWidget {
  const OverlayPanel({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 28),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            Color(0xD9101A2C),
            Color(0xD9213558),
          ],
        ),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}