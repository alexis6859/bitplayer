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
Timer? snakeTimer;
final int snakeGridSize = 15;

int tetrisScore = 0, tetrisTopScore = 0;
bool isPlayingTetris = false, isTetrisGameOver = false;
Timer? tetrisTimer;
final int tetrisCols = 10, tetrisRows = 18;
late List<List<int>> tetrisBoard;
List<Point<int>> tetrisPiece = [];
Point<int> tetrisPieceOffset = const Point(0, 0);
int tetrisPieceType = 0;
final List<List<Point<int>>> tetrisShapes = [
  [const Point(0, 0), const Point(1, 0), const Point(2, 0), const Point(3, 0)],
  [const Point(0, 0), const Point(1, 0), const Point(0, 1), const Point(1, 1)],
  [const Point(1, 0), const Point(0, 1), const Point(1, 1), const Point(2, 1)],
  [const Point(1, 0), const Point(2, 0), const Point(0, 1), const Point(1, 1)],
  [const Point(0, 0), const Point(1, 0), const Point(1, 1), const Point(2, 1)],
];

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
