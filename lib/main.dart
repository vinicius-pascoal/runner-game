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

  // Mundo
  final double _groundHeight = 112;
  final double _playerSize = 42;
  final double _playerX = 84;

  // Física
  final double _gravity = 1850;
  final double _jumpVelocity = -760;
  double _playerY = 0;
  double _playerVelocityY = 0;
  int _jumpsUsed = 0;
  final int _maxJumps = 2;

  // Estado do jogo
  bool _isPlaying = false;
  bool _gameOver = false;
  bool _isPaused = false;

  double _score = 0;
  int _coinsCollected = 0;
  int _highScore = 0;
  int _difficultyLevel = 1;

  // Ritmo do mundo
  double _worldSpeed = 280;
  double _groundStripeOffset = 0;

  // Spawn
  double _obstacleSpawnTimer = 0;
  double _nextObstacleSpawnTime = 1.2;
  double _coinSpawnTimer = 0;
  double _nextCoinSpawnTime = 0.95;

  // Objetos em cena
  final List<Obstacle> _obstacles = [];
  final List<CoinItem> _coins = [];

  double get _groundTop => _screenHeight - _groundHeight;
  double get _playerGroundY => _groundTop - _playerSize;
  bool get _isOnGround => (_playerY - _playerGroundY).abs() < 1.0;

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
    _updateDifficulty();

    // Física do jogador
    _playerVelocityY += _gravity * dt;
    _playerY += _playerVelocityY * dt;

    if (_playerY >= _playerGroundY) {
      _playerY = _playerGroundY;
      _playerVelocityY = 0;
      _jumpsUsed = 0;
    }

    // Pontuação baseada em tempo e dificuldade
    _score += dt * (10 + (_difficultyLevel - 1) * 0.45);

    // Movimento do chão
    _groundStripeOffset =
        (_groundStripeOffset + (_worldSpeed * dt)) % 44.0;

    // Spawn obstáculos
    _obstacleSpawnTimer += dt;
    if (_obstacleSpawnTimer >= _nextObstacleSpawnTime) {
      _spawnObstacleWave();
      _obstacleSpawnTimer = 0;
      _scheduleNextObstacleSpawn();
    }

    // Spawn moedas
    _coinSpawnTimer += dt;
    if (_coinSpawnTimer >= _nextCoinSpawnTime) {
      _spawnCoinPattern();
      _coinSpawnTimer = 0;
      _scheduleNextCoinSpawn();
    }

    // Atualiza obstáculos
    for (final obstacle in _obstacles) {
      obstacle.x -= _worldSpeed * dt;
    }
    _obstacles.removeWhere((o) => o.x + o.width < -24);

    // Atualiza moedas
    for (final coin in _coins) {
      coin.x -= _worldSpeed * dt;
    }
    _coins.removeWhere((c) => c.x + c.size < -20);

    _checkCollisions();
  }

  void _updateDifficulty() {
    _difficultyLevel = max(1, 1 + (_score ~/ 25));

    final ramp = min(_score / 18.0, 12.0);
    _worldSpeed = 280 + ramp * 22;
  }

  void _scheduleNextObstacleSpawn() {
    final ramp = min(_score / 18.0, 12.0);
    final base = max(0.58, 1.35 - ramp * 0.065);
    _nextObstacleSpawnTime = base + _random.nextDouble() * 0.35;
  }

  void _scheduleNextCoinSpawn() {
    final ramp = min(_score / 20.0, 10.0);
    final base = max(0.72, 1.12 - ramp * 0.04);
    _nextCoinSpawnTime = base + _random.nextDouble() * 0.45;
  }

  void _spawnObstacleWave() {
    final startX = _screenWidth + 20;
    final difficultyBias = min(_score / 40.0, 4.0);

    int count = 1;
    if (_score >= 35 && _random.nextDouble() < 0.28) {
      count = 2;
    }

    double currentX = startX;

    for (int i = 0; i < count; i++) {
      final width = 30 + _random.nextDouble() * 24 + difficultyBias * 4;
      final height = 36 + _random.nextDouble() * (54 + difficultyBias * 12);

      _obstacles.add(
        Obstacle(
          x: currentX,
          width: width,
          height: height,
        ),
      );

      currentX += 118 + _random.nextDouble() * 56;
    }
  }

  void _spawnCoinPattern() {
    final startX = _screenWidth + 50;
    final isArc = _random.nextBool();

    int count;
    if (_score < 30) {
      count = 3 + _random.nextInt(2); // 3..4
    } else {
      count = 3 + _random.nextInt(3); // 3..5
    }

    final baseHeight = 72 + _random.nextDouble() * 115;
    final spacing = 42.0;

    for (int i = 0; i < count; i++) {
      double y = _groundTop - baseHeight;

      if (isArc) {
        final arcProgress = count == 1 ? 0.0 : i / (count - 1);
        final arcOffset = sin(arcProgress * pi) * 26;
        y -= arcOffset;
      } else {
        y -= (i.isEven ? 0 : 10);
      }

      _coins.add(
        CoinItem(
          x: startX + i * spacing,
          y: y,
          size: 18,
        ),
      );
    }
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
        coin.y,
        coin.size,
        coin.size,
      );

      if (playerRect.overlaps(coinRect)) {
        _coinsCollected += 1;
        _score += 2;
        _coins.removeAt(i);
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

  void _jump() {
    if (!_isPlaying || _gameOver || _isPaused) return;
    if (_jumpsUsed >= _maxJumps) return;

    _playerVelocityY =
    _jumpsUsed == 0 ? _jumpVelocity : _jumpVelocity * 0.92;
    _jumpsUsed += 1;
  }

  void _resetWorld({required bool startPlaying, bool autoJump = false}) {
    _obstacles.clear();
    _coins.clear();

    _score = 0;
    _coinsCollected = 0;
    _difficultyLevel = 1;
    _worldSpeed = 280;
    _groundStripeOffset = 0;

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
                          obstacles: _obstacles,
                          coins: _coins,
                          jumpsRemaining: _maxJumps - _jumpsUsed,
                          gameOver: _gameOver,
                          isPaused: _isPaused,
                        ),
                      ),
                    ),

                    Positioned(
                      top: 14,
                      left: 14,
                      right: 14,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            HudCard(
                              icon: Icons.speed_rounded,
                              label: 'Pontos',
                              value: _score.floor().toString(),
                            ),
                            const SizedBox(width: 10),
                            HudCard(
                              icon: Icons.monetization_on_rounded,
                              label: 'Moedas',
                              value: _coinsCollected.toString(),
                            ),
                            const SizedBox(width: 10),
                            HudCard(
                              icon: Icons.workspace_premium_rounded,
                              label: 'Recorde',
                              value: _highScore.toString(),
                            ),
                            const SizedBox(width: 10),
                            HudCard(
                              icon: Icons.trending_up_rounded,
                              label: 'Nível',
                              value: _difficultyLevel.toString(),
                            ),
                            const SizedBox(width: 10),
                            HudCard(
                              icon: Icons.double_arrow_rounded,
                              label: 'Pulos',
                              value: '${_maxJumps - _jumpsUsed}',
                            ),
                            const SizedBox(width: 12),
                            RoundGlassButton(
                              icon: _isPaused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              tooltip: _isPaused ? 'Continuar' : 'Pausar',
                              onTap: _togglePause,
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (!_isPlaying && !_gameOver)
                      const Center(
                        child: OverlayPanel(
                          title: 'Infinite Runner',
                          subtitle:
                          'Toque na tela ou pressione Espaço / ↑ / W para começar.\n'
                              'Você tem duplo pulo, pode coletar moedas e usar P ou o botão para pausar.',
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
                      Center(
                        child: OverlayPanel(
                          title: 'Game Over',
                          subtitle:
                          'Pontuação: ${_score.floor()}\n'
                              'Moedas: $_coinsCollected\n'
                              'Toque para reiniciar.',
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
    required this.y,
    required this.size,
  });

  double x;
  final double y;
  final double size;
}

class RunnerPainter extends CustomPainter {
  RunnerPainter({
    required this.playerX,
    required this.playerY,
    required this.playerSize,
    required this.groundHeight,
    required this.groundStripeOffset,
    required this.obstacles,
    required this.coins,
    required this.jumpsRemaining,
    required this.gameOver,
    required this.isPaused,
  });

  final double playerX;
  final double playerY;
  final double playerSize;
  final double groundHeight;
  final double groundStripeOffset;
  final List<Obstacle> obstacles;
  final List<CoinItem> coins;
  final int jumpsRemaining;
  final bool gameOver;
  final bool isPaused;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawMoon(canvas, size);
    _drawHorizon(canvas, size);
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

  void _drawHorizon(Canvas canvas, Size size) {
    final horizonY = size.height - groundHeight - 58;

    final farPaint = Paint()..color = const Color(0xFF10203A).withOpacity(0.55);
    final midPaint = Paint()..color = const Color(0xFF152744).withOpacity(0.82);

    for (int i = 0; i < 12; i++) {
      final x = i * (size.width / 10.5) - 16;
      final w = 24 + (i % 3) * 16.0;
      final h = 38 + (i % 4) * 18.0;
      canvas.drawRect(Rect.fromLTWH(x, horizonY - h, w, h), farPaint);
    }

    for (int i = 0; i < 9; i++) {
      final x = i * (size.width / 8) + 8;
      final w = 34 + (i % 2) * 18.0;
      final h = 52 + (i % 3) * 26.0;
      canvas.drawRect(Rect.fromLTWH(x, horizonY - h + 18, w, h), midPaint);
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

  void _drawCoins(Canvas canvas) {
    final outerPaint = Paint()..color = const Color(0xFFFFD54F);
    final innerPaint = Paint()..color = const Color(0xFFFFB300);
    final shinePaint = Paint()..color = Colors.white70;

    for (final coin in coins) {
      final center = Offset(coin.x + coin.size / 2, coin.y + coin.size / 2);

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

    // Sinaliza visualmente o duplo pulo restante
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

class HudCard extends StatelessWidget {
  const HudCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RoundGlassButton extends StatelessWidget {
  const RoundGlassButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  Color(0xAA101B2D),
                  Color(0xAA24395C),
                ],
              ),
              border: Border.all(color: Colors.white12),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
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