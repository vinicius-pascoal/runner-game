import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

enum ObstacleKind { ground, flying }

enum ObstaclePatternKind { singleGround, doubleGround, flying }

enum UpgradeType { extraJumps, magnet, extraLife, fortune }

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
  static const String _bankCoinsKey = 'infinite_runner_bank_coins';
  static const String _extraJumpsUpgradeKey =
      'infinite_runner_extra_jumps_upgrade';
  static const String _magnetUpgradeKey = 'infinite_runner_magnet_upgrade';
  static const String _extraLifeUpgradeKey =
      'infinite_runner_extra_life_upgrade';
  static const String _fortuneUpgradeKey = 'infinite_runner_fortune_upgrade';

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
  final int _baseJumps = 2;

  double _playerY = 0;
  double _playerVelocityY = 0;
  int _jumpsUsed = 0;

  bool _isPlaying = false;
  bool _gameOver = false;
  bool _isPaused = false;

  bool _showEvolutionTree = false;
  bool _resumeAfterClosingTree = false;

  double _score = 0;
  int _runCoinsCollected = 0;
  int _bankCoins = 0;
  int _highScore = 0;
  int _difficultyLevel = 1;

  int _extraJumpsUpgradeLevel = 0;
  int _magnetUpgradeLevel = 0;
  int _extraLifeUpgradeLevel = 0;
  int _fortuneUpgradeLevel = 0;

  int _currentLives = 1;
  double _invulnerabilityTimer = 0;

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

  int _lastFeedbackAtMs = 0;

  final List<Obstacle> _obstacles = [];
  final List<CoinItem> _coins = [];
  final List<DustParticle> _dustParticles = [];
  final List<SparkParticle> _sparkParticles = [];

  double get _groundTop => _screenHeight - _groundHeight;
  double get _playerGroundY => _groundTop - _playerSize;
  bool get _isOnGround => (_playerY - _playerGroundY).abs() < 1.0;

  int get _effectiveMaxJumps => _baseJumps + _extraJumpsUpgradeLevel;
  int get _maxLives => 1 + _extraLifeUpgradeLevel;
  double get _magnetRadius => 18.0 * _magnetUpgradeLevel;
  int get _bankCoinsPerPickup => 1 + _fortuneUpgradeLevel;

  @override
  void initState() {
    super.initState();

    _loadProgress();

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

  Future<void> _loadProgress() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _prefs = prefs;
      _highScore = prefs.getInt(_highScoreKey) ?? 0;
      _bankCoins = prefs.getInt(_bankCoinsKey) ?? 0;
      _extraJumpsUpgradeLevel = prefs.getInt(_extraJumpsUpgradeKey) ?? 0;
      _magnetUpgradeLevel = prefs.getInt(_magnetUpgradeKey) ?? 0;
      _extraLifeUpgradeLevel = prefs.getInt(_extraLifeUpgradeKey) ?? 0;
      _fortuneUpgradeLevel = prefs.getInt(_fortuneUpgradeKey) ?? 0;
      _currentLives = _maxLives;
    });
  }

  Future<void> _saveProgress() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;

    await prefs.setInt(_highScoreKey, _highScore);
    await prefs.setInt(_bankCoinsKey, _bankCoins);
    await prefs.setInt(_extraJumpsUpgradeKey, _extraJumpsUpgradeLevel);
    await prefs.setInt(_magnetUpgradeKey, _magnetUpgradeLevel);
    await prefs.setInt(_extraLifeUpgradeKey, _extraLifeUpgradeLevel);
    await prefs.setInt(_fortuneUpgradeKey, _fortuneUpgradeLevel);
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;

    final dt = (delta.inMicroseconds / 1000000.0).clamp(0.0, 0.05);

    if (_screenWidth <= 0 || _screenHeight <= 0) {
      if (mounted) setState(() {});
      return;
    }

    if (_isPlaying && !_gameOver && !_isPaused && !_showEvolutionTree) {
      _updateGame(dt);
    } else {
      _animationTime += dt;
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _updateGame(double dt) {
    _animationTime += dt;
    _updateDifficulty();

    if (_invulnerabilityTimer > 0) {
      _invulnerabilityTimer = max(0, _invulnerabilityTimer - dt);
    }

    _playerVelocityY += _gravity * dt;
    _playerY += _playerVelocityY * dt;

    if (_playerY >= _playerGroundY) {
      _playerY = _playerGroundY;
      _playerVelocityY = 0;
      _jumpsUsed = 0;
    }

    _score += dt * (7.0 + (_difficultyLevel - 1) * 0.16);

    _groundStripeOffset = (_groundStripeOffset + (_worldSpeed * dt)) % 44.0;
    _farParallaxOffset = (_farParallaxOffset + (_worldSpeed * 0.07 * dt)) % 420;
    _midParallaxOffset = (_midParallaxOffset + (_worldSpeed * 0.14 * dt)) % 520;
    _nearParallaxOffset =
        (_nearParallaxOffset + (_worldSpeed * 0.24 * dt)) % 620;

    _obstacleSpawnTimer += dt;
    if (_obstacleSpawnTimer >= _nextObstacleSpawnTime) {
      _spawnFairObstaclePattern();
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

    _updateParticles(dt);
    _checkCollisions();
  }

  void _updateDifficulty() {
    _difficultyLevel = max(1, 1 + (_score ~/ 45));
    final ramp = min(_score / 40.0, 10.0);
    _worldSpeed = 250 + ramp * 10.5;
  }

  void _scheduleNextObstacleSpawn() {
    final ramp = min(_score / 45.0, 8.0);
    final base = max(1.0, 1.58 - ramp * 0.045);
    _nextObstacleSpawnTime = base + _random.nextDouble() * 0.36;
  }

  void _scheduleNextCoinSpawn() {
    final ramp = min(_score / 50.0, 8.0);
    final base = max(0.95, 1.18 - ramp * 0.025);
    _nextCoinSpawnTime = base + _random.nextDouble() * 0.42;
  }

  ObstaclePatternKind _pickObstaclePatternKind() {
    final roll = _random.nextDouble();

    if (_score < 20) {
      return roll < 0.82
          ? ObstaclePatternKind.singleGround
          : ObstaclePatternKind.flying;
    }

    if (_score < 60) {
      if (roll < 0.58) return ObstaclePatternKind.singleGround;
      if (roll < 0.82) return ObstaclePatternKind.flying;
      return ObstaclePatternKind.doubleGround;
    }

    if (roll < 0.45) return ObstaclePatternKind.singleGround;
    if (roll < 0.72) return ObstaclePatternKind.flying;
    return ObstaclePatternKind.doubleGround;
  }

  double? _rightMostObstacleEdge() {
    if (_obstacles.isEmpty) return null;

    double edge = -1e9;
    for (final obstacle in _obstacles) {
      edge = max(edge, obstacle.x + obstacle.width);
    }
    return edge;
  }

  ObstacleKind? _rightMostObstacleKind() {
    if (_obstacles.isEmpty) return null;

    Obstacle? rightMost;
    double edge = -1e9;

    for (final obstacle in _obstacles) {
      final currentEdge = obstacle.x + obstacle.width;
      if (currentEdge > edge) {
        edge = currentEdge;
        rightMost = obstacle;
      }
    }

    return rightMost?.kind;
  }

  double _requiredGapForPattern(
      ObstaclePatternKind nextPattern,
      ObstacleKind? previousKind,
      ) {
    switch (nextPattern) {
      case ObstaclePatternKind.singleGround:
        return previousKind == ObstacleKind.flying ? 180 : 160;
      case ObstaclePatternKind.doubleGround:
        return previousKind == ObstacleKind.flying ? 220 : 195;
      case ObstaclePatternKind.flying:
        return previousKind == ObstacleKind.ground ? 245 : 175;
    }
  }

  void _spawnFairObstaclePattern() {
    final pattern = _pickObstaclePatternKind();
    final rightMostEdge = _rightMostObstacleEdge();
    final previousKind = _rightMostObstacleKind();

    final requiredGap = _requiredGapForPattern(pattern, previousKind);
    final startX = rightMostEdge == null
        ? _screenWidth + 20
        : max(_screenWidth + 20, rightMostEdge + requiredGap);

    switch (pattern) {
      case ObstaclePatternKind.singleGround:
        _spawnSingleGroundObstacle(startX);
        break;
      case ObstaclePatternKind.doubleGround:
        _spawnDoubleGroundPattern(startX);
        break;
      case ObstaclePatternKind.flying:
        _spawnFlyingObstacle(startX);
        break;
    }
  }

  void _spawnSingleGroundObstacle(double startX) {
    final difficultyBias = min(_score / 80.0, 3.0);
    final width = 30 + _random.nextDouble() * 22 + difficultyBias * 2;
    final height = 36 + _random.nextDouble() * (34 + difficultyBias * 8);

    _obstacles.add(
      Obstacle(
        x: startX,
        y: _groundTop - height,
        width: width,
        height: height,
        kind: ObstacleKind.ground,
        phase: 0,
      ),
    );
  }

  void _spawnDoubleGroundPattern(double startX) {
    final difficultyBias = min(_score / 90.0, 2.8);

    final firstWidth = 30 + _random.nextDouble() * 16;
    final secondWidth = 30 + _random.nextDouble() * 18;

    final firstHeight = 36 + _random.nextDouble() * (24 + difficultyBias * 7);
    final secondHeight = 36 + _random.nextDouble() * (26 + difficultyBias * 8);

    final innerGap = 150 + _random.nextDouble() * 45;

    _obstacles.add(
      Obstacle(
        x: startX,
        y: _groundTop - firstHeight,
        width: firstWidth,
        height: firstHeight,
        kind: ObstacleKind.ground,
        phase: 0,
      ),
    );

    _obstacles.add(
      Obstacle(
        x: startX + firstWidth + innerGap,
        y: _groundTop - secondHeight,
        width: secondWidth,
        height: secondHeight,
        kind: ObstacleKind.ground,
        phase: 0,
      ),
    );
  }

  void _spawnFlyingObstacle(double startX) {
    final width = 56 + _random.nextDouble() * 26;
    final height = 20 + _random.nextDouble() * 14;

    final clearanceFromGround = 78 + _random.nextDouble() * 18;
    final y = _groundTop - clearanceFromGround - height;

    _obstacles.add(
      Obstacle(
        x: startX,
        y: y,
        width: width,
        height: height,
        kind: ObstacleKind.flying,
        phase: _random.nextDouble() * pi * 2,
      ),
    );
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
          obstacle.y - 6,
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

  void _updateParticles(double dt) {
    for (final particle in _dustParticles) {
      particle.update(dt);
    }
    _dustParticles.removeWhere((p) => !p.alive);

    for (final particle in _sparkParticles) {
      particle.update(dt);
    }
    _sparkParticles.removeWhere((p) => !p.alive);
  }

  void _spawnJumpDust() {
    for (int i = 0; i < 8; i++) {
      _dustParticles.add(
        DustParticle(
          x: _playerX + 8 + _random.nextDouble() * (_playerSize - 16),
          y: _groundTop + 2,
          vx: -70 + _random.nextDouble() * 140,
          vy: -30 - _random.nextDouble() * 85,
          size: 3 + _random.nextDouble() * 5,
          maxLife: 0.22 + _random.nextDouble() * 0.18,
        ),
      );
    }
  }

  void _spawnCoinSparkles(double x, double y) {
    for (int i = 0; i < 12; i++) {
      final angle = _random.nextDouble() * pi * 2;
      final speed = 35 + _random.nextDouble() * 120;

      _sparkParticles.add(
        SparkParticle(
          x: x,
          y: y,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed,
          size: 2 + _random.nextDouble() * 3,
          maxLife: 0.22 + _random.nextDouble() * 0.22,
          fillColor: const Color(0xFFFFF59D),
          strokeColor: Colors.white,
        ),
      );
    }
  }

  void _spawnHitBurst(double x, double y) {
    for (int i = 0; i < 16; i++) {
      final angle = _random.nextDouble() * pi * 2;
      final speed = 45 + _random.nextDouble() * 145;

      _sparkParticles.add(
        SparkParticle(
          x: x,
          y: y,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed,
          size: 2 + _random.nextDouble() * 4,
          maxLife: 0.28 + _random.nextDouble() * 0.18,
          fillColor: const Color(0xFFFF8A65),
          strokeColor: const Color(0xFFFFCCBC),
        ),
      );
    }
  }

  Future<void> _playJumpFeedback() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}

    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  Future<void> _playCoinFeedback() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFeedbackAtMs < 70) return;
    _lastFeedbackAtMs = now;

    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}

    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  Future<void> _playHitFeedback() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}

    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  void _checkCollisions() {
    final playerRect = Rect.fromLTWH(
      _playerX,
      _playerY,
      _playerSize,
      _playerSize,
    );

    final coinCollectRect = playerRect.inflate(_magnetRadius);

    if (_invulnerabilityTimer <= 0) {
      for (int i = _obstacles.length - 1; i >= 0; i--) {
        final obstacle = _obstacles[i];
        final obstacleRect = Rect.fromLTWH(
          obstacle.x,
          obstacle.visualY(_animationTime),
          obstacle.width,
          obstacle.height,
        );

        if (playerRect.overlaps(obstacleRect)) {
          _handleObstacleHit(i, obstacleRect.center);
          return;
        }
      }
    }

    for (int i = _coins.length - 1; i >= 0; i--) {
      final coin = _coins[i];
      final visualY = _coinVisualY(coin);
      final coinRect = Rect.fromLTWH(
        coin.x,
        visualY,
        coin.size,
        coin.size,
      );

      if (coinCollectRect.overlaps(coinRect)) {
        _runCoinsCollected += 1;
        _bankCoins += _bankCoinsPerPickup;
        _score += 1.5;

        _spawnCoinSparkles(
          coin.x + coin.size / 2,
          visualY + coin.size / 2,
        );

        _coins.removeAt(i);
        _playCoinFeedback();
        _saveProgress();
      }
    }
  }

  void _handleObstacleHit(int obstacleIndex, Offset hitCenter) {
    if (_currentLives > 1) {
      _currentLives -= 1;
      _invulnerabilityTimer = 1.15;

      if (obstacleIndex >= 0 && obstacleIndex < _obstacles.length) {
        _obstacles.removeAt(obstacleIndex);
      }

      _spawnHitBurst(hitCenter.dx, hitCenter.dy);
      _playHitFeedback();
      return;
    }

    _handleGameOver();
  }

  void _handleGameOver() {
    _gameOver = true;
    _isPlaying = false;
    _isPaused = false;

    final finalScore = _score.floor();
    if (finalScore > _highScore) {
      _highScore = finalScore;
    }

    _saveProgress();
  }

  void _jump() {
    if (!_isPlaying || _gameOver || _isPaused || _showEvolutionTree) return;
    if (_jumpsUsed >= _effectiveMaxJumps) return;

    final wasGrounded = _isOnGround;

    _playerVelocityY =
    _jumpsUsed == 0 ? _jumpVelocity : _jumpVelocity * 0.92;
    _jumpsUsed += 1;

    if (wasGrounded) {
      _spawnJumpDust();
    }

    _playJumpFeedback();
  }

  void _resetWorld({required bool startPlaying, bool autoJump = false}) {
    _obstacles.clear();
    _coins.clear();
    _dustParticles.clear();
    _sparkParticles.clear();

    _score = 0;
    _runCoinsCollected = 0;
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
    _currentLives = _maxLives;
    _invulnerabilityTimer = 0;

    _obstacleSpawnTimer = 0;
    _coinSpawnTimer = 0;
    _scheduleNextObstacleSpawn();
    _scheduleNextCoinSpawn();

    _gameOver = false;
    _isPaused = false;
    _isPlaying = startPlaying;
    _showEvolutionTree = false;
    _resumeAfterClosingTree = false;

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
    if (!_isPlaying || _gameOver || _showEvolutionTree) return;

    setState(() {
      _isPaused = !_isPaused;
    });
  }

  void _toggleEvolutionTree() {
    setState(() {
      if (_showEvolutionTree) {
        _showEvolutionTree = false;

        if (_resumeAfterClosingTree && _isPlaying && !_gameOver) {
          _isPaused = false;
        }

        _resumeAfterClosingTree = false;
        return;
      }

      _resumeAfterClosingTree = _isPlaying && !_gameOver && !_isPaused;

      if (_isPlaying && !_gameOver) {
        _isPaused = true;
      }

      _showEvolutionTree = true;
    });
  }

  int _upgradeLevel(UpgradeType type) {
    switch (type) {
      case UpgradeType.extraJumps:
        return _extraJumpsUpgradeLevel;
      case UpgradeType.magnet:
        return _magnetUpgradeLevel;
      case UpgradeType.extraLife:
        return _extraLifeUpgradeLevel;
      case UpgradeType.fortune:
        return _fortuneUpgradeLevel;
    }
  }

  void _setUpgradeLevel(UpgradeType type, int value) {
    switch (type) {
      case UpgradeType.extraJumps:
        _extraJumpsUpgradeLevel = value;
        break;
      case UpgradeType.magnet:
        _magnetUpgradeLevel = value;
        break;
      case UpgradeType.extraLife:
        _extraLifeUpgradeLevel = value;
        break;
      case UpgradeType.fortune:
        _fortuneUpgradeLevel = value;
        break;
    }
  }

  int _maxUpgradeLevel(UpgradeType type) => 3;

  List<int> _upgradeCosts(UpgradeType type) {
    switch (type) {
      case UpgradeType.extraJumps:
        return const [28, 52, 86];
      case UpgradeType.magnet:
        return const [32, 58, 94];
      case UpgradeType.extraLife:
        return const [48, 84, 132];
      case UpgradeType.fortune:
        return const [44, 76, 118];
    }
  }

  String _upgradeTitle(UpgradeType type) {
    switch (type) {
      case UpgradeType.extraJumps:
        return 'Pulso Aéreo';
      case UpgradeType.magnet:
        return 'Ímã de Moedas';
      case UpgradeType.extraLife:
        return 'Vida Extra';
      case UpgradeType.fortune:
        return 'Fortuna';
    }
  }

  String _upgradeDescription(UpgradeType type) {
    switch (type) {
      case UpgradeType.extraJumps:
        return 'Adiciona um pulo extra por nível.';
      case UpgradeType.magnet:
        return 'Aumenta o raio de coleta automática das moedas.';
      case UpgradeType.extraLife:
        return 'Concede uma vida adicional por nível em cada partida.';
      case UpgradeType.fortune:
        return 'Cada moeda coletada rende mais moedas no banco.';
    }
  }

  String _upgradeCurrentEffectText(UpgradeType type) {
    switch (type) {
      case UpgradeType.extraJumps:
        return 'Atual: $_effectiveMaxJumps pulos máximos';
      case UpgradeType.magnet:
        return 'Atual: ${_magnetRadius.toStringAsFixed(0)}px de alcance';
      case UpgradeType.extraLife:
        return 'Atual: $_maxLives vida(s) por partida';
      case UpgradeType.fortune:
        return 'Atual: $_bankCoinsPerPickup moeda(s) por coleta';
    }
  }

  String _upgradeNextEffectText(UpgradeType type) {
    switch (type) {
      case UpgradeType.extraJumps:
        return 'Próximo: ${_effectiveMaxJumps + 1} pulos máximos';
      case UpgradeType.magnet:
        return 'Próximo: ${(18.0 * (_magnetUpgradeLevel + 1)).toStringAsFixed(0)}px';
      case UpgradeType.extraLife:
        return 'Próximo: ${_maxLives + 1} vida(s)';
      case UpgradeType.fortune:
        return 'Próximo: ${_bankCoinsPerPickup + 1} moeda(s) por coleta';
    }
  }

  String _upgradeRequirementText(UpgradeType type) {
    switch (type) {
      case UpgradeType.extraJumps:
      case UpgradeType.magnet:
        return 'Desbloqueado desde o início';
      case UpgradeType.extraLife:
        return 'Requer Pulso Aéreo 1 + Ímã de Moedas 1';
      case UpgradeType.fortune:
        return 'Requer Vida Extra 1';
    }
  }

  bool _isUpgradeUnlocked(UpgradeType type) {
    switch (type) {
      case UpgradeType.extraJumps:
      case UpgradeType.magnet:
        return true;
      case UpgradeType.extraLife:
        return _extraJumpsUpgradeLevel >= 1 && _magnetUpgradeLevel >= 1;
      case UpgradeType.fortune:
        return _extraLifeUpgradeLevel >= 1;
    }
  }

  int? _upgradeNextCost(UpgradeType type) {
    final level = _upgradeLevel(type);
    final costs = _upgradeCosts(type);

    if (level >= costs.length) return null;
    return costs[level];
  }

  bool _canBuyUpgrade(UpgradeType type) {
    final cost = _upgradeNextCost(type);
    if (cost == null) return false;
    if (!_isUpgradeUnlocked(type)) return false;
    return _bankCoins >= cost;
  }

  Future<void> _buyUpgrade(UpgradeType type) async {
    if (!_canBuyUpgrade(type)) return;

    final cost = _upgradeNextCost(type);
    if (cost == null) return;

    setState(() {
      _bankCoins -= cost;
      _setUpgradeLevel(type, _upgradeLevel(type) + 1);

      if (!_isPlaying || _gameOver) {
        _currentLives = _maxLives;
      }
    });

    await _saveProgress();
  }

  Widget _buildSummaryChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEvolutionTreeOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.72),
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 780),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xF0111B2F),
                    Color(0xF01B2D4A),
                    Color(0xF0243E67),
                  ],
                ),
                border: Border.all(color: Colors.white12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 26,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: Colors.white.withOpacity(0.08),
                          ),
                          child: const Icon(
                            Icons.account_tree_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Árvore de Melhorias',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Invista moedas do banco para deixar cada run mais forte.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PauseButton(
                          isPaused: false,
                          onTap: _toggleEvolutionTree,
                          icon: Icons.close_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildSummaryChip(
                          Icons.account_balance_wallet_rounded,
                          'Banco',
                          '$_bankCoins',
                        ),
                        _buildSummaryChip(
                          Icons.monetization_on_rounded,
                          'Run atual',
                          '$_runCoinsCollected',
                        ),
                        _buildSummaryChip(
                          Icons.favorite_rounded,
                          'Vidas',
                          '$_maxLives',
                        ),
                        _buildSummaryChip(
                          Icons.workspace_premium_rounded,
                          'Recorde',
                          '$_highScore',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            UpgradeSectionCard(
                              title: 'Mobilidade e Coleta',
                              subtitle:
                              'A primeira camada melhora mobilidade e eficiência para farmar moedas.',
                              accentColor: const Color(0xFF4FC3F7),
                              children: [
                                EvolutionUpgradeCard(
                                  title: _upgradeTitle(UpgradeType.extraJumps),
                                  description:
                                  _upgradeDescription(UpgradeType.extraJumps),
                                  currentEffect: _upgradeCurrentEffectText(
                                    UpgradeType.extraJumps,
                                  ),
                                  nextEffect: _upgradeNextEffectText(
                                    UpgradeType.extraJumps,
                                  ),
                                  requirementText: _upgradeRequirementText(
                                    UpgradeType.extraJumps,
                                  ),
                                  level: _upgradeLevel(UpgradeType.extraJumps),
                                  maxLevel:
                                  _maxUpgradeLevel(UpgradeType.extraJumps),
                                  nextCost:
                                  _upgradeNextCost(UpgradeType.extraJumps),
                                  unlocked:
                                  _isUpgradeUnlocked(UpgradeType.extraJumps),
                                  canBuy:
                                  _canBuyUpgrade(UpgradeType.extraJumps),
                                  icon: Icons.rocket_launch_rounded,
                                  onBuy: () =>
                                      _buyUpgrade(UpgradeType.extraJumps),
                                ),
                                EvolutionUpgradeCard(
                                  title: _upgradeTitle(UpgradeType.magnet),
                                  description:
                                  _upgradeDescription(UpgradeType.magnet),
                                  currentEffect: _upgradeCurrentEffectText(
                                    UpgradeType.magnet,
                                  ),
                                  nextEffect: _upgradeNextEffectText(
                                    UpgradeType.magnet,
                                  ),
                                  requirementText: _upgradeRequirementText(
                                    UpgradeType.magnet,
                                  ),
                                  level: _upgradeLevel(UpgradeType.magnet),
                                  maxLevel: _maxUpgradeLevel(UpgradeType.magnet),
                                  nextCost:
                                  _upgradeNextCost(UpgradeType.magnet),
                                  unlocked:
                                  _isUpgradeUnlocked(UpgradeType.magnet),
                                  canBuy: _canBuyUpgrade(UpgradeType.magnet),
                                  icon: Icons.blur_circular_rounded,
                                  onBuy: () => _buyUpgrade(UpgradeType.magnet),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            const Icon(
                              Icons.keyboard_double_arrow_down_rounded,
                              size: 34,
                              color: Colors.white54,
                            ),
                            const SizedBox(height: 18),
                            UpgradeSectionCard(
                              title: 'Sobrevivência e Economia',
                              subtitle:
                              'A segunda camada aumenta sua margem de erro e a rentabilidade de cada moeda.',
                              accentColor: const Color(0xFFFFA726),
                              children: [
                                EvolutionUpgradeCard(
                                  title: _upgradeTitle(UpgradeType.extraLife),
                                  description:
                                  _upgradeDescription(UpgradeType.extraLife),
                                  currentEffect: _upgradeCurrentEffectText(
                                    UpgradeType.extraLife,
                                  ),
                                  nextEffect: _upgradeNextEffectText(
                                    UpgradeType.extraLife,
                                  ),
                                  requirementText: _upgradeRequirementText(
                                    UpgradeType.extraLife,
                                  ),
                                  level: _upgradeLevel(UpgradeType.extraLife),
                                  maxLevel:
                                  _maxUpgradeLevel(UpgradeType.extraLife),
                                  nextCost:
                                  _upgradeNextCost(UpgradeType.extraLife),
                                  unlocked:
                                  _isUpgradeUnlocked(UpgradeType.extraLife),
                                  canBuy: _canBuyUpgrade(UpgradeType.extraLife),
                                  icon: Icons.favorite_rounded,
                                  onBuy: () =>
                                      _buyUpgrade(UpgradeType.extraLife),
                                ),
                                EvolutionUpgradeCard(
                                  title: _upgradeTitle(UpgradeType.fortune),
                                  description:
                                  _upgradeDescription(UpgradeType.fortune),
                                  currentEffect: _upgradeCurrentEffectText(
                                    UpgradeType.fortune,
                                  ),
                                  nextEffect: _upgradeNextEffectText(
                                    UpgradeType.fortune,
                                  ),
                                  requirementText: _upgradeRequirementText(
                                    UpgradeType.fortune,
                                  ),
                                  level: _upgradeLevel(UpgradeType.fortune),
                                  maxLevel:
                                  _maxUpgradeLevel(UpgradeType.fortune),
                                  nextCost:
                                  _upgradeNextCost(UpgradeType.fortune),
                                  unlocked:
                                  _isUpgradeUnlocked(UpgradeType.fortune),
                                  canBuy: _canBuyUpgrade(UpgradeType.fortune),
                                  icon: Icons.auto_awesome_rounded,
                                  onBuy: () => _buyUpgrade(UpgradeType.fortune),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handlePrimaryAction() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }

    if (_screenWidth <= 0 || _screenHeight <= 0) return;
    if (_showEvolutionTree) return;

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
      if (_showEvolutionTree) {
        _toggleEvolutionTree();
      } else {
        _togglePause();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyE) {
      _toggleEvolutionTree();
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
                          dustParticles: _dustParticles,
                          sparkParticles: _sparkParticles,
                          magnetRadius: _magnetRadius,
                          jumpsRemaining: _effectiveMaxJumps - _jumpsUsed,
                          gameOver: _gameOver,
                          isPaused: _isPaused,
                          animationTime: _animationTime,
                          invulnerabilityTimer: _invulnerabilityTimer,
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
                              runCoins: _runCoinsCollected,
                              lives: _currentLives,
                            ),
                          ),
                          const SizedBox(width: 10),
                          EvolutionButton(
                            bankCoins: _bankCoins,
                            onTap: _toggleEvolutionTree,
                            icon: Icons.account_tree_rounded,
                            label: 'Evoluir',
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
                          'Recorde: $_highScore\n'
                              'Banco: $_bankCoins moedas\n\n'
                              'Toque na tela ou pressione Espaço / ↑ / W para começar.\n'
                              'Pressione E para abrir a árvore de melhorias.',
                        ),
                      ),
                    if (_isPaused && !_showEvolutionTree)
                      const Center(
                        child: OverlayPanel(
                          title: 'Pausado',
                          subtitle:
                          'Pressione P, ESC ou o botão de pausa para continuar.\n'
                              'Pressione E para abrir a árvore de melhorias.',
                        ),
                      ),
                    if (_gameOver && !_showEvolutionTree)
                      const Center(
                        child: OverlayPanel(
                          title: 'Game Over',
                          subtitle:
                          'Toque para reiniciar.\n'
                              'Abra a árvore de melhorias para gastar suas moedas.',
                        ),
                      ),
                    if (_gameOver && !_showEvolutionTree)
                      Positioned(
                        left: 22,
                        right: 22,
                        bottom: 70,
                        child: ResultSummary(
                          score: _score.floor(),
                          runCoins: _runCoinsCollected,
                          bankCoins: _bankCoins,
                          highScore: _highScore,
                        ),
                      ),
                    if (_showEvolutionTree) _buildEvolutionTreeOverlay(),
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
    required this.y,
    required this.width,
    required this.height,
    required this.kind,
    required this.phase,
  });

  double x;
  final double y;
  final double width;
  final double height;
  final ObstacleKind kind;
  final double phase;

  double visualY(double animationTime) {
    if (kind == ObstacleKind.flying) {
      return y + sin((animationTime * 2.8) + phase) * 4.0;
    }
    return y;
  }
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

class DustParticle {
  DustParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.maxLife,
  });

  double x;
  double y;
  double vx;
  double vy;
  final double size;
  double life = 0;
  final double maxLife;

  bool get alive => life < maxLife;
  double get progress => 1 - (life / maxLife).clamp(0.0, 1.0);

  void update(double dt) {
    life += dt;
    x += vx * dt;
    y += vy * dt;
    vy += 200 * dt;
    vx *= 0.96;
  }
}

class SparkParticle {
  SparkParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.maxLife,
    required this.fillColor,
    required this.strokeColor,
  });

  double x;
  double y;
  double vx;
  double vy;
  final double size;
  double life = 0;
  final double maxLife;
  final Color fillColor;
  final Color strokeColor;

  bool get alive => life < maxLife;
  double get progress => 1 - (life / maxLife).clamp(0.0, 1.0);

  void update(double dt) {
    life += dt;
    x += vx * dt;
    y += vy * dt;
    vy += 24 * dt;
    vx *= 0.99;
    vy *= 0.99;
  }
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
    required this.dustParticles,
    required this.sparkParticles,
    required this.magnetRadius,
    required this.jumpsRemaining,
    required this.gameOver,
    required this.isPaused,
    required this.animationTime,
    required this.invulnerabilityTimer,
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
  final List<DustParticle> dustParticles;
  final List<SparkParticle> sparkParticles;
  final double magnetRadius;
  final int jumpsRemaining;
  final bool gameOver;
  final bool isPaused;
  final double animationTime;
  final double invulnerabilityTimer;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawMoon(canvas, size);
    _drawParallaxLayers(canvas, size);
    _drawGround(canvas, size);
    _drawDustParticles(canvas);
    _drawCoins(canvas);
    _drawSparkParticles(canvas);
    _drawObstacles(canvas);
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
          Rect.fromLTWH(
            x + width * 0.22,
            baseY - height - 10,
            width * 0.16,
            10,
          ),
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

  void _drawDustParticles(Canvas canvas) {
    for (final particle in dustParticles) {
      final alpha = (particle.progress * 0.45).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = const Color(0xFFB0BEC5).withOpacity(alpha);

      canvas.drawCircle(
        Offset(particle.x, particle.y),
        particle.size * particle.progress,
        paint,
      );
    }
  }

  void _drawCoins(Canvas canvas) {
    final outerPaint = Paint()..color = const Color(0xFFFFD54F);
    final innerPaint = Paint()..color = const Color(0xFFFFB300);
    final shinePaint = Paint()..color = Colors.white70;
    final magnetPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0x66FFE082);

    for (final coin in coins) {
      final y = _coinVisualY(coin);
      final center = Offset(coin.x + coin.size / 2, y + coin.size / 2);

      if (magnetRadius > 0) {
        canvas.drawCircle(
          center,
          coin.size / 2 + magnetRadius * 0.12,
          magnetPaint,
        );
      }

      canvas.drawCircle(center, coin.size / 2, outerPaint);
      canvas.drawCircle(center, coin.size / 2.8, innerPaint);
      canvas.drawCircle(
        Offset(center.dx - 3, center.dy - 3),
        2.5,
        shinePaint,
      );
    }
  }

  void _drawSparkParticles(Canvas canvas) {
    for (final particle in sparkParticles) {
      final opacity = particle.progress.clamp(0.0, 1.0);
      final radius = particle.size * particle.progress;

      final circlePaint = Paint()
        ..color = particle.fillColor.withOpacity(opacity);

      final linePaint = Paint()
        ..color = particle.strokeColor.withOpacity(opacity)
        ..strokeWidth = max(0.8, particle.progress * 1.8)
        ..strokeCap = StrokeCap.round;

      final center = Offset(particle.x, particle.y);

      canvas.drawCircle(center, radius, circlePaint);

      canvas.drawLine(
        Offset(center.dx - radius * 1.8, center.dy),
        Offset(center.dx + radius * 1.8, center.dy),
        linePaint,
      );

      canvas.drawLine(
        Offset(center.dx, center.dy - radius * 1.8),
        Offset(center.dx, center.dy + radius * 1.8),
        linePaint,
      );
    }
  }

  void _drawObstacles(Canvas canvas) {
    final groundObstaclePaint = Paint()..color = const Color(0xFFE86A7A);
    final groundAccentPaint = Paint()..color = const Color(0xFFB34052);
    final flyingPaint = Paint()..color = const Color(0xFF7E8CFF);
    final flyingAccentPaint = Paint()..color = const Color(0xFF4C5FD7);
    final edgePaint = Paint()..color = const Color(0x55FFFFFF);
    final shadowPaint = Paint()..color = Colors.black26;

    for (final obstacle in obstacles) {
      final y = obstacle.visualY(animationTime);

      if (obstacle.kind == ObstacleKind.ground) {
        final rect = Rect.fromLTWH(
          obstacle.x,
          y,
          obstacle.width,
          obstacle.height,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(5)),
          groundObstaclePaint,
        );

        canvas.drawRect(
          Rect.fromLTWH(rect.left + 4, rect.top + 6, rect.width - 8, 7),
          groundAccentPaint,
        );

        canvas.drawRect(
          Rect.fromLTWH(rect.left + 3, rect.top + 3, rect.width - 6, 2),
          edgePaint,
        );
      } else {
        final rect = Rect.fromLTWH(
          obstacle.x,
          y,
          obstacle.width,
          obstacle.height,
        );

        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(
              rect.center.dx,
              rect.bottom + 22,
            ),
            width: rect.width * 0.8,
            height: 8,
          ),
          shadowPaint,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(12)),
          flyingPaint,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              rect.left + 6,
              rect.top + 5,
              rect.width - 12,
              rect.height * 0.35,
            ),
            const Radius.circular(10),
          ),
          flyingAccentPaint,
        );

        canvas.drawRect(
          Rect.fromLTWH(rect.left - 6, rect.top + rect.height * 0.28, 8, 4),
          edgePaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(rect.right - 2, rect.top + rect.height * 0.28, 8, 4),
          edgePaint,
        );
      }
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

    final blink = invulnerabilityTimer > 0 &&
        (animationTime * 12).floor().isOdd;

    final bodyPaint = Paint()..color = bodyColor.withOpacity(blink ? 0.38 : 1);
    final detailPaint = Paint()..color = Colors.black12.withOpacity(blink ? 0.2 : 1);
    final eyePaint = Paint()..color = Colors.white.withOpacity(blink ? 0.45 : 1);
    final pupilPaint = Paint()..color = Colors.black87.withOpacity(blink ? 0.45 : 1);
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
    required this.runCoins,
    required this.lives,
  });

  final int score;
  final int runCoins;
  final int lives;

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
          Flexible(
            child: Text(
              'Pontos: $score',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          const Icon(
            Icons.monetization_on_rounded,
            size: 18,
            color: Color(0xFFFFD54F),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$runCoins',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          const Icon(
            Icons.favorite_rounded,
            size: 18,
            color: Color(0xFFFF6B6B),
          ),
          const SizedBox(width: 6),
          Text(
            '$lives',
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

class EvolutionButton extends StatelessWidget {
  const EvolutionButton({
    super.key,
    required this.bankCoins,
    required this.onTap,
    required this.icon,
    required this.label,
  });

  final int bankCoins;
  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [
                Color(0xAA18253D),
                Color(0xAA28446E),
              ],
            ),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$bankCoins',
                style: const TextStyle(
                  color: Color(0xFFFFE082),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PauseButton extends StatelessWidget {
  const PauseButton({
    super.key,
    required this.isPaused,
    required this.onTap,
    this.icon,
  });

  final bool isPaused;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final displayIcon =
        icon ?? (isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded);

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
            displayIcon,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class UpgradeSectionCard extends StatelessWidget {
  const UpgradeSectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.children,
  });

  final String title;
  final String subtitle;
  final Color accentColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: children,
          ),
        ],
      ),
    );
  }
}

class EvolutionUpgradeCard extends StatelessWidget {
  const EvolutionUpgradeCard({
    super.key,
    required this.title,
    required this.description,
    required this.currentEffect,
    required this.nextEffect,
    required this.requirementText,
    required this.level,
    required this.maxLevel,
    required this.nextCost,
    required this.unlocked,
    required this.canBuy,
    required this.icon,
    required this.onBuy,
  });

  final String title;
  final String description;
  final String currentEffect;
  final String nextEffect;
  final String requirementText;
  final int level;
  final int maxLevel;
  final int? nextCost;
  final bool unlocked;
  final bool canBuy;
  final IconData icon;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final isMaxed = level >= maxLevel;

    return Container(
      width: 430,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: unlocked
              ? const [
            Color(0xAA16243C),
            Color(0xAA243E67),
          ]
              : const [
            Color(0xAA1B1E27),
            Color(0xAA272B35),
          ],
        ),
        border: Border.all(
          color: unlocked ? Colors.white12 : Colors.white10,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: Colors.white12,
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black.withOpacity(0.18),
                ),
                child: Text(
                  unlocked ? 'Ativo' : 'Bloqueado',
                  style: TextStyle(
                    color: unlocked ? Colors.white70 : Colors.redAccent.shade100,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            description,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(maxLevel, (index) {
              final filled = index < level;
              return Container(
                width: 26,
                height: 8,
                margin: EdgeInsets.only(right: index == maxLevel - 1 ? 0 : 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: filled
                      ? const Color(0xFFFFE082)
                      : Colors.white.withOpacity(0.12),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.black.withOpacity(0.14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentEffect,
                  style: const TextStyle(
                    color: Color(0xFFFFE082),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isMaxed ? 'Próximo: nível máximo alcançado' : nextEffect,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            requirementText,
            style: TextStyle(
              color: unlocked ? Colors.white60 : Colors.redAccent.shade100,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (!unlocked || !canBuy || isMaxed) ? null : onBuy,
              icon: Icon(
                isMaxed ? Icons.verified_rounded : Icons.upgrade_rounded,
              ),
              label: Text(
                isMaxed
                    ? 'MAX'
                    : !unlocked
                    ? 'Bloqueado'
                    : 'Comprar • ${nextCost ?? '-'}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ResultSummary extends StatelessWidget {
  const ResultSummary({
    super.key,
    required this.score,
    required this.runCoins,
    required this.bankCoins,
    required this.highScore,
  });

  final int score;
  final int runCoins;
  final int bankCoins;
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
          _ResultItem(label: 'Run', value: '$runCoins'),
          _ResultItem(label: 'Banco', value: '$bankCoins'),
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