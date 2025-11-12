// Bubble Shooter - title fixed (title placed above grid)
// Paste into DartPad main.dart and Run.

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() => runApp(BubbleShooterApp());

class BubbleShooterApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bubble Shooter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Color(0xFF0F1720)),
      home: Scaffold(
        appBar: AppBar(title: Text('Bubble Shooter — DartPad Demo')),
        body: SafeArea(child: BubbleShooterGame()),
      ),
    );
  }
}

class GridBubble {
  int row, col;
  int colorIndex;
  bool popped = false;
  double popProgress = 0; // 0..1
  GridBubble({required this.row, required this.col, required this.colorIndex});
}

class FlyingBubble {
  Offset pos;
  Offset vel;
  int colorIndex;
  bool stuck = false;
  FlyingBubble({required this.pos, required this.vel, required this.colorIndex});
}

class BubbleShooterGame extends StatefulWidget {
  @override
  _BubbleShooterGameState createState() => _BubbleShooterGameState();
}

class _BubbleShooterGameState extends State<BubbleShooterGame> with SingleTickerProviderStateMixin {
  // grid config
  final int cols = 8;
  final int rows = 10;
  final double bubbleDiameter = 36.0;

  // NOTE: increased top padding to make room for title & HUD
  final double gridTopPadding = 68.0; // <- increased so title doesn't overlap
  final double gridLeftPadding = 12.0;
  final List<Color> palette = [
    Colors.redAccent,
    Colors.amber,
    Colors.lightBlueAccent,
    Colors.greenAccent,
    Colors.purpleAccent,
    Colors.orangeAccent,
  ];

  late Ticker _ticker;
  double lastT = 0;

  // grid: rows x cols, null if empty
  late List<List<GridBubble?>> grid;

  // shooter
  Offset shooterPos = Offset.zero;
  double shooterRadius = 16;
  int nextColor = 0;
  int holdColor = 1;

  // flying bubble
  FlyingBubble? flying;

  // input
  Offset? aimTarget;
  bool draggingAim = false;

  // game
  int score = 0;
  int level = 1;
  bool running = true;
  bool gameOver = false;

  final math.Random rng = math.Random();

  @override
  void initState() {
    super.initState();

    // Initialize grid immediately so first build doesn't crash
    grid = List.generate(rows, (_) => List.generate(cols, (_) => null));

    _ticker = this.createTicker(_onTick)..start();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placeInitialRows(5);
      _spawnNext();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _initGrid() {
    grid = List.generate(rows, (_) => List.generate(cols, (_) => null));
  }

  void _placeInitialRows(int filledRows) {
    for (int r = 0; r < filledRows && r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        int ci = rng.nextInt(palette.length);
        grid[r][c] = GridBubble(row: r, col: c, colorIndex: ci);
      }
    }
    setState(() {});
  }

  void _spawnNext() {
    nextColor = rng.nextInt(palette.length);
    holdColor = rng.nextInt(palette.length);
    setState(() {});
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMilliseconds / 1000.0;
    double dt = lastT == 0 ? (1 / 60) : (t - lastT);
    if (dt > 0.05) dt = 0.05;
    lastT = t;
    if (!mounted) return;
    if (!running) return;

    bool stateChanged = false;

    if (flying != null) {
      flying!.pos = flying!.pos + flying!.vel * dt;
      final w = MediaQuery.of(context).size.width;
      if (flying!.pos.dx - bubbleDiameter / 2 <= 0 && flying!.vel.dx < 0) {
        flying!.vel = Offset(-flying!.vel.dx, flying!.vel.dy);
      } else if (flying!.pos.dx + bubbleDiameter / 2 >= w && flying!.vel.dx > 0) {
        flying!.vel = Offset(-flying!.vel.dx, flying!.vel.dy);
      }

      if (flying!.pos.dy - bubbleDiameter / 2 <= gridTopPadding + bubbleDiameter / 2) {
        _attachFlyingToGrid();
        stateChanged = true;
      } else {
        for (int r = 0; r < rows; r++) {
          for (int c = 0; c < cols; c++) {
            final gb = grid[r][c];
            if (gb == null) continue;
            final Offset center = _cellCenterOffset(r, c);
            final double dx = flying!.pos.dx - center.dx;
            final double dy = flying!.pos.dy - center.dy;
            final double dist2 = dx * dx + dy * dy;
            if (dist2 <= (bubbleDiameter * 0.95) * (bubbleDiameter * 0.95)) {
              _attachFlyingNear(r, c);
              stateChanged = true;
              r = rows;
              break;
            }
          }
        }
      }
    }

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final gb = grid[r][c];
        if (gb != null && gb.popped) {
          gb.popProgress += dt * 2.8;
          if (gb.popProgress >= 1.0) {
            grid[r][c] = null;
            stateChanged = true;
          } else {
            stateChanged = true;
          }
        }
      }
    }

    if (stateChanged) setState(() {});
  }

  Offset _cellCenterOffset(int row, int col) {
    final w = MediaQuery.of(context).size.width;
    final totalWidth = cols * bubbleDiameter + (cols - 1) * 4;
    final left = (w - totalWidth) / 2 + gridLeftPadding;
    double x = left + col * (bubbleDiameter + 4) + bubbleDiameter / 2;
    double y = gridTopPadding + row * (bubbleDiameter + 6) + bubbleDiameter / 2;
    if (row % 2 == 1) x += (bubbleDiameter / 2);
    return Offset(x, y);
  }

  void _attachFlyingToGrid() {
    if (flying == null) return;
    int bestR = 0;
    int bestC = 0;
    double bestD = double.infinity;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (grid[r][c] != null) continue;
        final Offset center = _cellCenterOffset(r, c);
        final double d = (center - flying!.pos).distance;
        if (d < bestD) {
          bestD = d;
          bestR = r;
          bestC = c;
        }
      }
    }
    _placeBubbleAt(bestR, bestC, flying!.colorIndex);
    flying = null;
    _afterPlaceProcess(bestR, bestC);
  }

  void _attachFlyingNear(int nbrRow, int nbrCol) {
    if (flying == null) return;
    final neighbors = _neighborOffsets(nbrRow);
    int bestR = -1, bestC = -1;
    double bestD = double.infinity;
    for (final o in neighbors) {
      final rr = nbrRow + o[0];
      final cc = nbrCol + o[1];
      if (rr < 0 || rr >= rows || cc < 0 || cc >= cols) continue;
      if (grid[rr][cc] != null) continue;
      final center = _cellCenterOffset(rr, cc);
      final d = (center - flying!.pos).distance;
      if (d < bestD) {
        bestD = d;
        bestR = rr;
        bestC = cc;
      }
    }
    if (bestR == -1) {
      int br = -1, bc = -1;
      double bd = double.infinity;
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          if (grid[r][c] != null) continue;
          final d = (_cellCenterOffset(r, c) - flying!.pos).distance;
          if (d < bd) {
            bd = d;
            br = r;
            bc = c;
          }
        }
      }
      if (br == -1) {
        flying = null;
        return;
      }
      bestR = br;
      bestC = bc;
    }
    _placeBubbleAt(bestR, bestC, flying!.colorIndex);
    flying = null;
    _afterPlaceProcess(bestR, bestC);
  }

  List<List<int>> _neighborOffsets(int row) {
    if (row % 2 == 0) {
      return [
        [-1, 0],
        [-1, -1],
        [0, -1],
        [0, 1],
        [1, 0],
        [1, -1],
      ];
    } else {
      return [
        [-1, 0],
        [-1, 1],
        [0, -1],
        [0, 1],
        [1, 0],
        [1, 1],
      ];
    }
  }

  void _placeBubbleAt(int r, int c, int colorIndex) {
    if (r < 0 || r >= rows || c < 0 || c >= cols) return;
    grid[r][c] = GridBubble(row: r, col: c, colorIndex: colorIndex);
    setState(() {});
  }

  void _afterPlaceProcess(int r, int c) {
    final matches = _floodFillSameColor(r, c);
    if (matches.length >= 3) {
      for (final p in matches) {
        final gb = grid[p[0]][p[1]];
        if (gb != null) {
          gb.popped = true;
          gb.popProgress = 0;
        }
        score += 10;
      }
      Future.delayed(Duration(milliseconds: 420), () {
        _removeFloatingBubbles();
      });
    } else {
      _removeFloatingBubbles();
    }
    _spawnNext();
    if (score > 0 && score % 150 == 0) {
      _addRowAtTop();
    }
    setState(() {});
  }

  List<List<int>> _floodFillSameColor(int r, int c) {
    final start = grid[r][c];
    List<List<int>> found = [];
    if (start == null) return found;
    final target = start.colorIndex;
    final visited = List.generate(rows, (_) => List.generate(cols, (_) => false));
    final q = Queue<List<int>>();
    q.add([r, c]);
    visited[r][c] = true;
    while (q.isNotEmpty) {
      final cur = q.removeFirst();
      found.add([cur[0], cur[1]]);
      final neighbors = _neighborOffsets(cur[0]);
      for (final o in neighbors) {
        final rr = cur[0] + o[0];
        final cc = cur[1] + o[1];
        if (rr < 0 || rr >= rows || cc < 0 || cc >= cols) continue;
        if (visited[rr][cc]) continue;
        final g = grid[rr][cc];
        if (g != null && g.colorIndex == target && !g.popped) {
          visited[rr][cc] = true;
          q.add([rr, cc]);
        }
      }
    }
    return found;
  }

  void _removeFloatingBubbles() {
    final visited = List.generate(rows, (_) => List.generate(cols, (_) => false));
    final q = Queue<List<int>>();
    for (int c = 0; c < cols; c++) {
      if (grid[0][c] != null && !grid[0][c]!.popped) {
        visited[0][c] = true;
        q.add([0, c]);
      }
    }
    while (q.isNotEmpty) {
      final cur = q.removeFirst();
      final neighbors = _neighborOffsets(cur[0]);
      for (final o in neighbors) {
        final rr = cur[0] + o[0];
        final cc = cur[1] + o[1];
        if (rr < 0 || rr >= rows || cc < 0 || cc >= cols) continue;
        if (visited[rr][cc]) continue;
        final g = grid[rr][cc];
        if (g != null && !g.popped) {
          visited[rr][cc] = true;
          q.add([rr, cc]);
        }
      }
    }
    bool any = false;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final gb = grid[r][c];
        if (gb != null && !gb.popped && !visited[r][c]) {
          gb.popped = true;
          gb.popProgress = 0;
          any = true;
          score += 5;
        }
      }
    }
    if (any) {
      Future.delayed(Duration(milliseconds: 350), () {
        if (!mounted) return;
        setState(() {});
      });
    }
  }

  void _addRowAtTop() {
    for (int r = rows - 1; r > 0; r--) {
      for (int c = 0; c < cols; c++) {
        grid[r][c] = grid[r - 1][c];
        if (grid[r][c] != null) {
          grid[r][c]!.row = r;
        }
      }
    }
    for (int c = 0; c < cols; c++) {
      grid[0][c] = GridBubble(row: 0, col: c, colorIndex: rng.nextInt(palette.length));
    }
    for (int c = 0; c < cols; c++) {
      if (grid[rows - 1][c] != null) {
        setState(() {
          running = false;
          gameOver = true;
        });
        return;
      }
    }
    setState(() {});
  }

  void _startShooting(Offset target) {
    if (flying != null || !running) return;
    final size = MediaQuery.of(context).size;
    shooterPos = Offset(size.width / 2, size.height - 56);
    final dir = (target - shooterPos);
    if (dir.distance < 8) return;
    final norm = dir / dir.distance;
    final speed = 520.0;
    final vel = norm * speed;
    flying = FlyingBubble(pos: shooterPos, vel: vel, colorIndex: nextColor);
    _spawnNext();
    setState(() {
      aimTarget = null;
      draggingAim = false;
    });
  }

  void _swapHold() {
    final tmp = nextColor;
    nextColor = holdColor;
    holdColor = tmp;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    shooterPos = Offset(size.width / 2, size.height - 56);
    return GestureDetector(
      onPanStart: (d) {
        if (!running) return;
        aimTarget = d.localPosition;
        draggingAim = true;
        setState(() {});
      },
      onPanUpdate: (d) {
        if (!running) return;
        aimTarget = d.localPosition;
        setState(() {});
      },
      onPanEnd: (d) {
        if (!running) return;
        if (aimTarget != null) {
          _startShooting(aimTarget!);
        }
        draggingAim = false;
      },
      onTapUp: (d) {
        if (!running) return;
        _startShooting(d.localPosition);
      },
      child: Stack(
        children: [
          // Game canvas
          Positioned.fill(
            child: CustomPaint(
              painter: _BubblePainter(
                grid: grid,
                palette: palette,
                bubbleDiameter: bubbleDiameter,
                cellCenter: _cellCenterOffset,
                flying: flying,
                shooterPos: shooterPos,
                shooterRadius: shooterRadius,
                nextColor: nextColor,
                holdColor: holdColor,
                aimTarget: aimTarget,
                draggingAim: draggingAim,
                score: score,
                level: level,
                gameOver: gameOver,
                running: running,
              ),
            ),
          ),

          // Title placed above the canvas so it never gets hidden
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Bubble Shooter',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),

          // HUD widgets
          Positioned(
            left: 12,
            top: 44,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _hudCard('Score', '$score'),
                SizedBox(height: 8),
                _hudCard('Level', '$level'),
              ],
            ),
          ),
          Positioned(
            right: 12,
            top: 44,
            child: Column(
              children: [
                GestureDetector(
                  onTap: _swapHold,
                  child: _colorPreview(holdColor, 'Hold'),
                ),
                SizedBox(height: 8),
                _colorPreview(nextColor, 'Next'),
              ],
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _initGrid();
                  _placeInitialRows(5);
                  score = 0;
                  level = 1;
                  running = true;
                  gameOver = false;
                  flying = null;
                  _spawnNext();
                });
              },
              child: Text('Restart'),
            ),
          ),
          if (gameOver)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: Center(
                  child: Card(
                    margin: EdgeInsets.symmetric(horizontal: 28),
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('Game Over', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('Score: $score'),
                        SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _initGrid();
                              _placeInitialRows(5);
                              score = 0;
                              level = 1;
                              running = true;
                              gameOver = false;
                              flying = null;
                              _spawnNext();
                            });
                          },
                          child: Text('Play Again'),
                        )
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

  Widget _hudCard(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 12)),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _colorPreview(int ci, String tag) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: palette[ci % palette.length], shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)]),
        ),
        SizedBox(height: 6),
        Text(tag, style: TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _BubblePainter extends CustomPainter {
  final List<List<GridBubble?>> grid;
  final List<Color> palette;
  final double bubbleDiameter;
  final Offset Function(int r, int c) cellCenter;
  final FlyingBubble? flying;
  final Offset shooterPos;
  final double shooterRadius;
  final int nextColor;
  final int holdColor;
  final Offset? aimTarget;
  final bool draggingAim;
  final int score;
  final int level;
  final bool gameOver;
  final bool running;

  _BubblePainter({
    required this.grid,
    required this.palette,
    required this.bubbleDiameter,
    required this.cellCenter,
    required this.flying,
    required this.shooterPos,
    required this.shooterRadius,
    required this.nextColor,
    required this.holdColor,
    required this.aimTarget,
    required this.draggingAim,
    required this.score,
    required this.level,
    required this.gameOver,
    required this.running,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // background
    final Rect full = Offset.zero & size;
    final Paint bg = Paint()..shader = LinearGradient(colors: [Color(0xFF071018), Color(0xFF0E1E2B)]).createShader(full);
    canvas.drawRect(full, bg);

    // draw grid bubbles
    for (int r = 0; r < grid.length; r++) {
      for (int c = 0; c < grid[r].length; c++) {
        final gb = grid[r][c];
        if (gb == null) continue;
        final center = cellCenter(r, c);
        final double prog = gb.popped ? (1 - gb.popProgress) : 1.0;
        final double d = bubbleDiameter * prog;
        final int alpha = ((gb.popped ? (1 - gb.popProgress) : 1.0) * 255).clamp(0, 255).toInt();
        final Paint p = Paint()..color = palette[gb.colorIndex].withAlpha(alpha);
        canvas.drawCircle(center, d / 2, p);
        canvas.drawCircle(center, d / 2, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.black.withAlpha(alpha));
      }
    }

    // aim line
    if (draggingAim && aimTarget != null) {
      // Fix: Replace .withOpacity() with .withAlpha() for better precision.
      final Paint aim = Paint()..color = Colors.white.withAlpha((0.5 * 255).round())..strokeWidth = 2;
      canvas.drawLine(shooterPos, aimTarget!, aim);
      final dir = (aimTarget! - shooterPos);
      if (dir.distance > 12) {
        final norm = dir / dir.distance;
        final p1 = aimTarget! - norm * 12 + Offset(-norm.dy, norm.dx) * 6;
        final p2 = aimTarget! - norm * 12 - Offset(-norm.dy, norm.dx) * 6;
        final path = Path()..moveTo(aimTarget!.dx, aimTarget!.dy)..lineTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)..close();
        canvas.drawPath(path, aim);
      }
    }

    // draw shooter base & next bubble
    canvas.drawCircle(shooterPos, shooterRadius + 6, Paint()..color = Colors.black45);
    final Paint nextPaint = Paint()..color = palette[nextColor % palette.length];
    canvas.drawCircle(shooterPos, bubbleDiameter / 2, nextPaint);
    canvas.drawCircle(shooterPos, bubbleDiameter / 2, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.black);

    // draw flying bubble
    if (flying != null) {
      final Paint fp = Paint()..color = palette[flying!.colorIndex % palette.length];
      canvas.drawCircle(flying!.pos, bubbleDiameter / 2, fp);
      canvas.drawCircle(flying!.pos, bubbleDiameter / 2, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.black);
    }

    // HUD: score & level painted in widgets; painter leaves that to widget layer
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) => true;
}