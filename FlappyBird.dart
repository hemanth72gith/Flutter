// Flappy Bird - Fixed Bird Direction + Wings (DartPad Flutter)
// Paste into DartPad main.dart and Run.
// Tap anywhere to flap. Avoid pipes. Score increases for each pipe passed.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() => runApp(FlappyApp());

class FlappyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flappy Bird - Fixed + Wings',
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: SafeArea(child: FlappyHome())),
    );
  }
}

class FlappyHome extends StatefulWidget {
  @override
  _FlappyHomeState createState() => _FlappyHomeState();
}

class _FlappyHomeState extends State<FlappyHome> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final math.Random _rng = math.Random();

  // Screen layout
  Size screen = Size(360, 640);
  double groundHeight = 80;

  // Bird physics
  Offset bird = Offset(80, 300);
  Offset velocity = Offset.zero;
  double birdRadius = 14;
  double gravity = 1000;
  double flapStrength = -320;

  // Pipes
  List<Pipe> pipes = [];
  double pipeSpeed = 180;
  double spawnTimer = 0;
  double spawnInterval = 1.6;
  double gapSize = 160;

  // Game state
  bool running = false;
  bool gameOver = false;
  int score = 0;

  double lastT = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      screen = MediaQuery.of(context).size;
      resetGame();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void resetGame() {
    setState(() {
      bird = Offset(screen.width * 0.22, screen.height * 0.45);
      velocity = Offset.zero;
      pipes.clear();
      spawnTimer = 0;
      score = 0;
      running = true;
      gameOver = false;

      // Pre-spawn a few pipes
      double startX = screen.width + 60;
      for (int i = 0; i < 3; i++) {
        double centerY = _rng.nextDouble() * (screen.height - gapSize - groundHeight - 120) + 80 + gapSize / 2;
        pipes.add(Pipe(x: startX + i * 220.0, gapCenterY: centerY, gap: gapSize));
      }
    });
  }

  void endGame() {
    if (!mounted) return;
    setState(() {
      running = false;
      gameOver = true;
    });
  }

  void flap() {
    if (!mounted) return;
    if (!running) {
      resetGame();
      return;
    }
    setState(() {
      velocity = Offset(velocity.dx, flapStrength);
    });
  }

  void _onTick(Duration elapsed) {
    final double t = elapsed.inMilliseconds / 1000.0;
    double dt = lastT == 0 ? (1 / 60) : (t - lastT);
    if (dt > 0.05) dt = 0.05;
    lastT = t;
    if (!mounted || !running) return;

    setState(() {
      // physics
      velocity = Offset(velocity.dx, velocity.dy + gravity * dt);
      bird = bird + velocity * dt;

      // pipes move
      for (int i = 0; i < pipes.length; i++) {
        pipes[i] = pipes[i].translated(-pipeSpeed * dt);
      }

      // spawn new pipes
      spawnTimer += dt;
      if (spawnTimer >= spawnInterval) {
        spawnTimer = 0;
        double centerY = _rng.nextDouble() * (screen.height - gapSize - groundHeight - 120) + 80 + gapSize / 2;
        double spawnX = (pipes.isNotEmpty ? pipes.last.x + 220.0 : screen.width + 80);
        pipes.add(Pipe(x: spawnX, gapCenterY: centerY, gap: gapSize));
      }

      // remove off-screen
      if (pipes.isNotEmpty && pipes.first.x + Pipe.pipeWidth < -40) pipes.removeAt(0);

      // scoring
      for (var p in pipes) {
        if (!p.passed && p.x + Pipe.pipeWidth / 2 < bird.dx) {
          p.passed = true;
          score++;
        }
      }

      // ground collision
      final double groundTop = screen.height - groundHeight;
      if (bird.dy + birdRadius > groundTop) {
        bird = Offset(bird.dx, groundTop - birdRadius);
        endGame();
        return;
      }

      // ceiling
      if (bird.dy - birdRadius < 0) {
        bird = Offset(bird.dx, birdRadius);
        velocity = Offset(velocity.dx, 0);
      }

      // pipe collision
      for (var p in pipes) {
        Rect top = Rect.fromLTWH(p.x, 0, Pipe.pipeWidth, p.gapCenterY - p.gap / 2);
        Rect bottom = Rect.fromLTWH(p.x, p.gapCenterY + p.gap / 2, Pipe.pipeWidth, screen.height - groundHeight - (p.gapCenterY + p.gap / 2));
        if (_circleRectCollision(bird, birdRadius, top) || _circleRectCollision(bird, birdRadius, bottom)) {
          endGame();
          return;
        }
      }
    });
  }

  bool _circleRectCollision(Offset c, double r, Rect rect) {
    final double closestX = c.dx.clamp(rect.left, rect.right);
    final double closestY = c.dy.clamp(rect.top, rect.bottom);
    final double dx = c.dx - closestX;
    final double dy = c.dy - closestY;
    return dx * dx + dy * dy <= r * r;
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.of(context).size;
    if (s != screen) screen = s;

    return GestureDetector(
      onTap: flap,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _FlappyPainter(
                bird: bird,
                birdRadius: birdRadius,
                pipes: pipes,
                groundHeight: groundHeight,
                score: score,
                running: running,
                gameOver: gameOver,
              ),
            ),
          ),
          Positioned(
            top: 18,
            left: 14,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              // FIX: Replaced Colors.white.withOpacity(0.12) with Color.fromRGBO to avoid deprecated method.
              decoration: BoxDecoration(color: Color.fromRGBO(255, 255, 255, 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text('Score: $score', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          if (gameOver)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: Center(
                  child: Card(
                    margin: EdgeInsets.symmetric(horizontal: 28),
                    elevation: 12,
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('Game Over', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('Score: $score', style: TextStyle(fontSize: 20)),
                        SizedBox(height: 12),
                        ElevatedButton(onPressed: resetGame, child: Text('Play Again')),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class Pipe {
  static const double pipeWidth = 64;
  double x;
  double gapCenterY;
  double gap;
  bool passed = false;

  Pipe({required this.x, required this.gapCenterY, required this.gap});

  Pipe translated(double dx) {
    final p = Pipe(x: x + dx, gapCenterY: gapCenterY, gap: gap);
    p.passed = passed;
    return p;
  }
}

class _FlappyPainter extends CustomPainter {
  final Offset bird;
  final double birdRadius;
  final List<Pipe> pipes;
  final double groundHeight;
  final int score;
  final bool running;
  final bool gameOver;

  _FlappyPainter({
    required this.bird,
    required this.birdRadius,
    required this.pipes,
    required this.groundHeight,
    required this.score,
    required this.running,
    required this.gameOver,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    final Rect bg = Offset.zero & size;
    final Paint sky = Paint()..shader = LinearGradient(colors: [Color(0xFF87CEEB), Color(0xFFB3E5FC)]).createShader(bg);
    canvas.drawRect(bg, sky);

    // Pipes
    final Paint pipeTop = Paint()..color = Colors.green.shade800;
    final Paint pipeSide = Paint()..color = Colors.green.shade900;
    for (var p in pipes) {
      Rect top = Rect.fromLTWH(p.x, 0, Pipe.pipeWidth, p.gapCenterY - p.gap / 2);
      Rect bottom = Rect.fromLTWH(p.x, p.gapCenterY + p.gap / 2, Pipe.pipeWidth, size.height - groundHeight - (p.gapCenterY + p.gap / 2));
      canvas.drawRect(top, pipeTop);
      canvas.drawRect(bottom, pipeTop);
      // caps
      canvas.drawRect(Rect.fromLTWH(p.x - 6, top.bottom - 12, Pipe.pipeWidth + 12, 12), pipeSide);
      canvas.drawRect(Rect.fromLTWH(p.x - 6, bottom.top, Pipe.pipeWidth + 12, 12), pipeSide);
    }

    // Ground
    canvas.drawRect(Rect.fromLTWH(0, size.height - groundHeight, size.width, groundHeight), Paint()..color = Colors.brown.shade700);
    canvas.drawRect(Rect.fromLTWH(0, size.height - groundHeight, size.width, 6), Paint()..color = Colors.green.shade600);

    // ---- Wing (draw behind body so beak/eye stay visible) ----
    // Wing animation amount controlled by bird's vertical velocity and position
    final double flap = math.sin(bird.dy * 0.08 + bird.dx * 0.015) * 8.0; // -8..8
    final Paint wingPaint = Paint()..color = Colors.deepOrange.shade200;
    final Paint wingShade = Paint()..color = Colors.deepOrange.shade400;

    // draw a top wing and a small lower wing slightly behind the bird
    final Path topWing = Path();
    topWing.moveTo(bird.dx - 4, bird.dy - 2 + flap * 0.2);
    topWing.quadraticBezierTo(bird.dx - 18, bird.dy - 12 + flap, bird.dx - 6, bird.dy - 22 + flap * 0.6);
    topWing.quadraticBezierTo(bird.dx - 2, bird.dy - 12 + flap * 0.3, bird.dx - 4, bird.dy - 2 + flap * 0.2);
    canvas.drawPath(topWing, wingPaint);
    // slight darker overlay for depth
    canvas.drawPath(topWing, wingShade..style = PaintingStyle.stroke..strokeWidth = 1.2);

    final Path lowerWing = Path();
    lowerWing.moveTo(bird.dx - 6, bird.dy + 4 + flap * 0.1);
    lowerWing.quadraticBezierTo(bird.dx - 20, bird.dy + 10 + flap * 0.5, bird.dx - 8, bird.dy + 20 + flap * 0.2);
    lowerWing.quadraticBezierTo(bird.dx - 4, bird.dy + 8 + flap * 0.15, bird.dx - 6, bird.dy + 4 + flap * 0.1);
    canvas.drawPath(lowerWing, Paint()..color = Colors.orange.shade200);
    canvas.drawPath(lowerWing, Paint()..color = Colors.orange.shade400..style = PaintingStyle.stroke..strokeWidth = 0.8);

    // Bird (body) - draw on top of wings
    final Paint birdBody = Paint()..color = Colors.orangeAccent;
    canvas.drawCircle(bird, birdRadius + 2, Paint()..color = Colors.black12);
    canvas.drawCircle(bird, birdRadius, birdBody);

    // Beak (points forward)
    final Path beak = Path();
    beak.moveTo(bird.dx + birdRadius - 2, bird.dy - 4);
    beak.lineTo(bird.dx + birdRadius + 8, bird.dy);
    beak.lineTo(bird.dx + birdRadius - 2, bird.dy + 4);
    beak.close();
    canvas.drawPath(beak, Paint()..color = Colors.deepOrangeAccent);

    // Eye (correct side)
    canvas.drawCircle(bird + Offset(5, -4), 3, Paint()..color = Colors.white);
    canvas.drawCircle(bird + Offset(5, -4), 1.3, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant _FlappyPainter old) => true;
}