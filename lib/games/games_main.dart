import 'dart:async';
import 'dart:math';

// --- GAMES STATE ---
int snakeScore = 0, snakeTopScore = 0;
bool isPlayingSnake = false, isSnakeGameOver = false;
List<Point<int>> snakeBody = [
  const Point(7, 7),
  const Point(7, 8),
  const Point(7, 9),
];
Point<int> snakeDir = const Point(0, -1), snakeFood = const Point(3, 3);
// Direção usada no último passo: impede inverter a cobra com 2 toques rápidos.
Point<int> snakeLastMoveDir = const Point(0, -1);
Timer? snakeTimer;
final int snakeGridSize = 15;

int tetrisScore = 0, tetrisTopScore = 0;
bool isPlayingTetris = false, isTetrisGameOver = false;
Timer? tetrisTimer;
final int tetrisCols = 10, tetrisRows = 18;
List<List<int>> tetrisBoard = emptyTetrisBoard();

List<List<int>> emptyTetrisBoard() =>
    List.generate(tetrisRows, (_) => List.filled(tetrisCols, 0));
List<Point<int>> tetrisPiece = [];
Point<int> tetrisPieceOffset = const Point(0, 0);
int tetrisPieceType = 0;
final List<List<Point<int>>> tetrisShapes = [
  [const Point(0, 0), const Point(1, 0), const Point(2, 0), const Point(3, 0)],
  [const Point(0, 0), const Point(1, 0), const Point(0, 1), const Point(1, 1)],
  [const Point(1, 0), const Point(0, 1), const Point(1, 1), const Point(2, 1)],
  [const Point(1, 0), const Point(2, 0), const Point(0, 1), const Point(1, 1)],
  [const Point(0, 0), const Point(1, 0), const Point(1, 1), const Point(2, 1)],
  [const Point(0, 0), const Point(0, 1), const Point(1, 1), const Point(2, 1)],
  [const Point(2, 0), const Point(0, 1), const Point(1, 1), const Point(2, 1)],
];

/// Remove todas as linhas completas do [board] (no lugar) e devolve quantas
/// foram limpas. Funciona com qualquer número de linhas simultâneas.
int clearFullTetrisLines(List<List<int>> board) {
  final cols = board.isEmpty ? 0 : board.first.length;
  final remaining = board.where((row) => row.any((c) => c == 0)).toList();
  final cleared = board.length - remaining.length;
  if (cleared == 0) return 0;
  board
    ..clear()
    ..addAll(List.generate(cleared, (_) => List.filled(cols, 0)))
    ..addAll(remaining);
  return cleared;
}

/// Pontuação clássica por número de linhas limpas de uma vez.
int tetrisLineScore(int lines) =>
    const [0, 100, 300, 500, 800][lines.clamp(0, 4)];

/// Desliza e junta uma linha do 2048 para o início. Devolve a nova linha e
/// os pontos ganhos.
(List<int>, int) slide2048Line(List<int> line) {
  final res = line.where((v) => v != 0).toList();
  int gained = 0;
  for (int i = 0; i < res.length - 1; i++) {
    if (res[i] == res[i + 1]) {
      res[i] *= 2;
      gained += res[i];
      res.removeAt(i + 1);
    }
  }
  while (res.length < line.length) {
    res.add(0);
  }
  return (res, gained);
}

int score2048 = 0, topScore2048 = 0;
List<int> board2048 = List.filled(16, 0);
bool isGameOver2048 = false;

int racingScore = 0, racingTopScore = 0;
bool isPlayingRacing = false, isRacingGameOver = false;
int playerLane = 1;
List<Map<String, double>> enemyCars = [];
Timer? racingTimer;

int flappyScore = 0, flappyTopScore = 0;
bool isPlayingFlappy = false, isFlappyGameOver = false;
double birdY = 10, birdVelocity = 0;
List<Map<String, double>> pipes = [];
Timer? flappyTimer;

int froggerScore = 0, froggerTopScore = 0;
bool isPlayingFrogger = false, isFroggerGameOver = false;
Point<int> frogPos = const Point(7, 14);
List<Map<String, dynamic>> roadCars = [];
Timer? froggerTimer;

final List<Map<String, String>> gameList = [
  {'id': 'snake', 'title': 'SNAKE'},
  {'id': 'tetris', 'title': 'TETRIS'},
  {'id': '2048', 'title': '2048'},
  {'id': 'racing', 'title': 'RACING'},
  {'id': 'flappy', 'title': 'FLAPPY BIRD'},
  {'id': 'frogger', 'title': 'CROSSY ROAD'},
];
