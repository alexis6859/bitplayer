import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:text_scroll/text_scroll.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widgets/interactive_button.dart';
import 'models/retro_themes.dart';
import 'games/games_main.dart';
import 'services/lang.dart';
import 'painters/custom_paints.dart';

late final MyAudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(Player()),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.bitplayer.audio.channel',
      androidNotificationChannelName: 'BitPlayer Media Controls',
      androidNotificationOngoing: true,
    ),
  );

  runApp(const MyApp());
}

class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final Player player;

  MyAudioHandler(this.player) {
    _initListeners();
  }

  void _initListeners() {
    player.stream.playing.listen((playing) {
      playbackState.add(
        playbackState.value.copyWith(
          playing: playing,
          controls: [
            MediaControl.skipToPrevious,
            playing ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
          ],
          systemActions: const {MediaAction.seek},
          processingState: AudioProcessingState.ready,
        ),
      );
    });

    player.stream.position.listen((position) {
      playbackState.add(playbackState.value.copyWith(updatePosition: position));
    });
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.previous();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  void updateTrackInfo(String title, Duration duration) {
    mediaItem.add(
      MediaItem(
        id: title,
        album: "BitPlayer",
        title: title,
        duration: duration,
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BitPlayer',
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'RetroFont'),
      home: RetroDeviceScreen(audioHandler: audioHandler),
    );
  }
}

class RetroDeviceScreen extends StatefulWidget {
  final MyAudioHandler audioHandler;
  const RetroDeviceScreen({super.key, required this.audioHandler});

  @override
  State<RetroDeviceScreen> createState() => _RetroDeviceScreenState();
}

class _RetroDeviceScreenState extends State<RetroDeviceScreen>
    with TickerProviderStateMixin {
  late final Player player;
  late AnimationController _spectrumController;

  String currentLang = 'pt';
  String currentView = 'player';
  int currentThemeIndex = 0;
  String visualStyle = 'spectrum';

  bool isPlaying = false;
  bool isShuffle = false;
  bool isRepeat = false;
  bool isLoadingFolder = false;

  bool isDraggingLetter = false;
  String currentLetter = '';

  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  List<String> libraryPaths = [];
  List<String> queuePaths = [];
  int currentIndex = 0;
  String currentTrackName = "NENHUMA FAIXA";
  int currentTrackBpm = 120;

  double currentVolume = 100.0;
  bool showVolumeIndicator = false;
  Timer? volumeTimer;

  int selectedMenuItem = 0;
  int selectedLibraryItem = 0;
  int selectedGameItem = 0;
  int selectedEqPreset = 0;

  final ScrollController _menuScrollController = ScrollController();
  final ScrollController _libraryScrollController = ScrollController();
  final ScrollController _queueScrollController = ScrollController();
  final ScrollController _gameMenuScrollController = ScrollController();
  final ScrollController _settingsScrollController = ScrollController();

  final int barCount = 12;
  late List<double> spectrumBars;
  late List<double> spectrumTarget;
  double wavePhase = 0.0;
  double currentWaveAmplitude = 0.05;
  double currentWaveComplexity = 0.02;

  bool _showSearchBar = true;
  double _lastLibraryScrollOffset = 0.0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  DateTime? _focusModeEndTime;
  int _focusModeDuration = 0;

  final List<Map<String, dynamic>> eqPresets = [
    {
      'id': 'normal',
      'pt': 'NORMAL',
      'en': 'NORMAL',
      'descriptionPt': 'Som equilibrado',
      'descriptionEn': 'Balanced sound',
      'bands': [0.5, 0.5, 0.5, 0.5, 0.5],
    },
    {
      'id': 'bass',
      'pt': 'BASS BOOST',
      'en': 'BASS BOOST',
      'descriptionPt': 'Graves reforçados',
      'descriptionEn': 'Enhanced low frequencies',
      'bands': [1.0, 0.85, 0.55, 0.35, 0.4],
    },
    {
      'id': 'voice',
      'pt': 'VOZ',
      'en': 'VOICE',
      'descriptionPt': 'Vozes mais nítidas',
      'descriptionEn': 'Clearer vocals',
      'bands': [0.25, 0.45, 1.0, 0.85, 0.5],
    },
    {
      'id': 'pop',
      'pt': 'POP',
      'en': 'POP',
      'descriptionPt': 'Brilho e presença',
      'descriptionEn': 'Brightness and presence',
      'bands': [0.7, 0.55, 0.8, 0.65, 0.85],
    },
    {
      'id': 'electronic',
      'pt': 'ELETRÓNICA',
      'en': 'ELECTRONIC',
      'descriptionPt': 'Impacto e energia',
      'descriptionEn': 'Impact and energy',
      'bands': [0.9, 0.65, 0.45, 0.8, 1.0],
    },
  ];

  List<Map<String, dynamic>> get menuItems => [
    {'icon': Icons.folder_open, 'id': 'open_folder'},
    {'icon': Icons.album, 'id': 'library'},
    {'icon': Icons.queue_music, 'id': 'queue'},
    {'icon': Icons.equalizer, 'id': 'equalizer'},
    {'icon': Icons.settings, 'id': 'settings'},
    {'icon': Icons.sports_esports, 'id': 'games'},
  ];

  RetroTheme get currentTheme => retroThemes[currentThemeIndex];

  List<String> get filteredLibraryPaths {
    if (_searchQuery.isEmpty) return libraryPaths;
    return libraryPaths
        .where(
          (path) => p
              .basenameWithoutExtension(path)
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    player = widget.audioHandler.player;
    player.setVolume(currentVolume);

    spectrumBars = List.filled(barCount, 0.1);
    spectrumTarget = List.filled(barCount, 0.1);

    _spectrumController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 60),
    )..repeat();
    _spectrumController.addListener(() {
      if (mounted) {
        setState(() {
          wavePhase -= isPlaying ? 0.08 : 0.02;

          if (isPlaying) {
            int currentChunk = position.inMilliseconds ~/ 150;
            int seed = currentChunk + currentTrackName.hashCode;
            var rand = Random(seed);

            double targetAmp = 0.15 + (rand.nextDouble() * 0.35);
            double targetComp = 0.015 + (rand.nextDouble() * 0.045);

            currentWaveAmplitude += (targetAmp - currentWaveAmplitude) * 0.2;
            currentWaveComplexity += (targetComp - currentWaveComplexity) * 0.1;
          } else {
            currentWaveAmplitude += (0.05 - currentWaveAmplitude) * 0.1;
            currentWaveComplexity += (0.02 - currentWaveComplexity) * 0.1;
          }

          for (int i = 0; i < barCount; i++) {
            if (isPlaying) {
              final time = position.inMilliseconds.toDouble();
              double frequencySpeed = 0.002 + (i / barCount) * 0.015;
              double wave =
                  (sin(time * frequencySpeed) +
                      cos(time * frequencySpeed * 1.3)) /
                  2.0;
              double noise = Random().nextDouble() * (0.1 + (i * 0.02));
              spectrumTarget[i] = (wave.abs() * 0.85) + noise;
              spectrumBars[i] =
                  (1 - 0.25) * spectrumBars[i] + 0.25 * spectrumTarget[i];
            } else {
              spectrumBars[i] = (1 - 0.2) * spectrumBars[i];
            }
          }
        });
      }
    });

    _libraryScrollController.addListener(() {
      if (mounted && currentView == 'library') {
        if (_libraryScrollController.hasClients &&
            _libraryScrollController.position.maxScrollExtent < 50) {
          if (!_showSearchBar) setState(() => _showSearchBar = true);
          return;
        }
        double offset = _libraryScrollController.offset;
        if (offset > _lastLibraryScrollOffset + 10 && offset > 20) {
          if (_showSearchBar) setState(() => _showSearchBar = false);
        } else if (offset < _lastLibraryScrollOffset - 10) {
          if (!_showSearchBar) setState(() => _showSearchBar = true);
        }
        _lastLibraryScrollOffset = offset;
      }
    });

    player.stream.playing.listen((bool playing) {
      if (mounted) setState(() => isPlaying = playing);
    });
    player.stream.position.listen((Duration p) {
      if (mounted) setState(() => position = p);
    });
    player.stream.duration.listen((Duration d) {
      if (mounted) {
        setState(() => duration = d);
        widget.audioHandler.updateTrackInfo(currentTrackName, d);
      }
    });

    player.stream.playlist.listen((Playlist playlist) {
      if (mounted && playlist.medias.isNotEmpty && playlist.index >= 0) {
        setState(() {
          currentIndex = playlist.index;
          if (currentIndex < queuePaths.length) {
            currentTrackName = p.basenameWithoutExtension(
              playlist.medias[currentIndex].uri,
            );
            currentTrackBpm = 80 + (currentTrackName.hashCode.abs() % 100);
            widget.audioHandler.updateTrackInfo(currentTrackName, duration);
          }
        });
      }
    });

    _loadData();
  }

  @override
  void dispose() {
    _spectrumController.dispose();
    _menuScrollController.dispose();
    _libraryScrollController.dispose();
    _queueScrollController.dispose();
    _gameMenuScrollController.dispose();
    _settingsScrollController.dispose();
    _searchController.dispose();
    volumeTimer?.cancel();
    snakeTimer?.cancel();
    tetrisTimer?.cancel();
    racingTimer?.cancel();
    flappyTimer?.cancel();
    froggerTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('retro_lang');
    if (savedLang != null) currentLang = savedLang;

    final savedTheme = prefs.getInt('retro_theme_index');
    if (savedTheme != null &&
        savedTheme >= 0 &&
        savedTheme < retroThemes.length) {
      currentThemeIndex = savedTheme;
    }

    final savedVisual = prefs.getString('retro_visual_style');
    if (savedVisual != null) {
      visualStyle = savedVisual;
    }

    final savedEqPreset = prefs.getInt('retro_eq_preset');
    if (savedEqPreset != null &&
        savedEqPreset >= 0 &&
        savedEqPreset < eqPresets.length) {
      selectedEqPreset = savedEqPreset;
    }

    snakeTopScore = prefs.getInt('snake_top_score') ?? 0;
    tetrisTopScore = prefs.getInt('tetris_top_score') ?? 0;
    topScore2048 = prefs.getInt('2048_top_score') ?? 0;
    racingTopScore = prefs.getInt('racing_top_score') ?? 0;
    flappyTopScore = prefs.getInt('flappy_top_score') ?? 0;
    froggerTopScore = prefs.getInt('frogger_top_score') ?? 0;

    final savedLibs = prefs.getStringList('retro_playlist');
    final savedQueue = prefs.getStringList('retro_queue');
    if (savedLibs != null && savedLibs.isNotEmpty) {
      libraryPaths = savedLibs;
      _sortAlphabetically();
      queuePaths = (savedQueue != null && savedQueue.isNotEmpty)
          ? savedQueue
          : List.from(libraryPaths);
      _playPlaylist(startIndex: 0, autoPlay: false);
    }
    setState(() {});
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('retro_playlist', libraryPaths);
    await prefs.setStringList('retro_queue', queuePaths);
    await prefs.setString('retro_lang', currentLang);
    await prefs.setInt('retro_theme_index', currentThemeIndex);
    await prefs.setString('retro_visual_style', visualStyle);
    await prefs.setInt('retro_eq_preset', selectedEqPreset);
  }

  void _sortAlphabetically() {
    libraryPaths.sort(
      (a, b) => p
          .basenameWithoutExtension(a)
          .toLowerCase()
          .compareTo(p.basenameWithoutExtension(b).toLowerCase()),
    );
  }

  void _handleShuffleToggle() async {
    if (libraryPaths.isEmpty) return;
    String currentTrackPath = "";
    if (queuePaths.isNotEmpty &&
        currentIndex >= 0 &&
        currentIndex < queuePaths.length) {
      currentTrackPath = queuePaths[currentIndex];
    } else if (libraryPaths.isNotEmpty) {
      currentTrackPath = libraryPaths.first;
    }

    setState(() {
      isShuffle = !isShuffle;
      if (isShuffle) {
        List<String> remaining = List.from(libraryPaths)
          ..remove(currentTrackPath);
        remaining.shuffle();
        queuePaths = [currentTrackPath, ...remaining];
        currentIndex = 0;
      } else {
        queuePaths = List.from(libraryPaths);
        currentIndex = queuePaths.indexOf(currentTrackPath);
        if (currentIndex == -1) currentIndex = 0;
      }
    });

    await _saveData();
    final currentPos = player.state.position;
    final wasPlaying = player.state.playing;

    await player.open(
      Playlist(
        queuePaths.map((path) => Media(path)).toList(),
        index: currentIndex,
      ),
      play: false,
    );
    if (currentPos > Duration.zero) await player.seek(currentPos);
    if (wasPlaying) await player.play();
  }

  Future<void> requestPermissionsAndPickFolder() async {
    if (Platform.isAndroid) {
      PermissionStatus statusAudio = await Permission.audio.request();
      if (statusAudio.isDenied || statusAudio.isPermanentlyDenied) {
        PermissionStatus statusStorage = await Permission.storage.request();
        if (statusStorage.isDenied) return;
      }
    }
    String? dirPath = await FilePicker.getDirectoryPath();
    if (dirPath != null) {
      setState(() => isLoadingFolder = true);
      final dir = Directory(dirPath);
      List<String> audioFiles = [];
      final validExtensions = ['.mp3', '.wav', '.flac', '.m4a', '.aac', '.ogg'];

      try {
        await for (var entity
            in dir.list(recursive: true).handleError((e) {})) {
          if (entity is File &&
              validExtensions.contains(
                p.extension(entity.path).toLowerCase(),
              )) {
            audioFiles.add(entity.path);
          }
        }
      } catch (e) {
        debugPrint("Erro: $e");
      }

      setState(() => isLoadingFolder = false);

      if (audioFiles.isNotEmpty) {
        libraryPaths = audioFiles;
        _sortAlphabetically();
        queuePaths = List.from(libraryPaths);
        setState(() {
          isShuffle = false;
          currentView = 'player';
        });
        await _saveData();
        await _playPlaylist(startIndex: 0, autoPlay: true);
      }
    }
  }

  Future<void> _playPlaylist({
    required int startIndex,
    required bool autoPlay,
  }) async {
    final medias = queuePaths.map((path) => Media(path)).toList();
    final playlist = Playlist(medias, index: startIndex);
    await player.open(playlist, play: autoPlay);
  }

  void _scrollToItem(ScrollController controller, int index) {
    if (controller.hasClients) {
      controller.animateTo(
        index * 50.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  void _handleVolumeChange(double delta) {
    setState(() {
      currentVolume = (currentVolume + delta).clamp(0.0, 100.0);
      player.setVolume(currentVolume);
      showVolumeIndicator = true;
    });
    volumeTimer?.cancel();
    volumeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => showVolumeIndicator = false);
    });
  }

  void _reorderQueue(int oldI, int newI) async {
    if (oldI < newI) newI -= 1;
    int realOldIndex = currentIndex + oldI;
    int realNewIndex = currentIndex + newI;
    final String currentTrackPath = queuePaths[currentIndex];

    setState(() {
      final String item = queuePaths.removeAt(realOldIndex);
      queuePaths.insert(realNewIndex, item);
      currentIndex = queuePaths.indexOf(currentTrackPath);
    });

    await _saveData();
    try {
      await player.move(realOldIndex, realNewIndex);
    } catch (e) {
      debugPrint("Erro ao reordenar fila: $e");
    }
  }

  // --- SNAKE LOGIC (BPM Adaptativo) ---
  void _startSnakeGame() {
    setState(() {
      snakeBody = [const Point(7, 7), const Point(7, 8), const Point(7, 9)];
      snakeDir = const Point(0, -1);
      isPlayingSnake = true;
      isSnakeGameOver = false;
      snakeScore = 0;
      _spawnSnakeFood();
    });
    snakeTimer?.cancel();
    int speed = (180 - ((currentTrackBpm - 120) * 1.5)).toInt().clamp(50, 250);
    snakeTimer = Timer.periodic(
      Duration(milliseconds: speed),
      (_) => _updateSnake(),
    );
  }

  void _spawnSnakeFood() {
    final rand = Random();
    while (true) {
      Point<int> p = Point(
        rand.nextInt(snakeGridSize),
        rand.nextInt(snakeGridSize),
      );
      if (!snakeBody.contains(p)) {
        snakeFood = p;
        break;
      }
    }
  }

  void _updateSnake() {
    if (!isPlayingSnake) return;
    setState(() {
      Point<int> newHead = Point(
        snakeBody.first.x + snakeDir.x,
        snakeBody.first.y + snakeDir.y,
      );
      if (newHead.x < 0 ||
          newHead.x >= snakeGridSize ||
          newHead.y < 0 ||
          newHead.y >= snakeGridSize ||
          snakeBody.contains(newHead)) {
        isPlayingSnake = false;
        isSnakeGameOver = true;
        snakeTimer?.cancel();
        if (snakeScore > snakeTopScore)
          SharedPreferences.getInstance().then(
            (prefs) =>
                prefs.setInt('snake_top_score', snakeTopScore = snakeScore),
          );
        return;
      }
      snakeBody.insert(0, newHead);
      if (newHead == snakeFood) {
        snakeScore += 10;
        _spawnSnakeFood();
      } else {
        snakeBody.removeLast();
      }
    });
  }

  // --- TETRIS LOGIC (BPM Adaptativo) ---
  void _startTetrisGame() {
    setState(() {
      tetrisBoard = List.generate(
        tetrisRows,
        (_) => List.filled(tetrisCols, 0),
      );
      tetrisScore = 0;
      isPlayingTetris = true;
      isTetrisGameOver = false;
      _spawnTetrisPiece();
    });
    tetrisTimer?.cancel();
    int speed = (450 - ((currentTrackBpm - 120) * 2.0)).toInt().clamp(150, 600);
    tetrisTimer = Timer.periodic(
      Duration(milliseconds: speed),
      (_) => _updateTetris(),
    );
  }

  void _spawnTetrisPiece() {
    tetrisPieceType = Random().nextInt(tetrisShapes.length);
    tetrisPiece = tetrisShapes[tetrisPieceType];
    tetrisPieceOffset = Point(tetrisCols ~/ 2 - 1, 0);
    if (_checkTetrisCollision(tetrisPiece, tetrisPieceOffset)) {
      isPlayingTetris = false;
      isTetrisGameOver = true;
      tetrisTimer?.cancel();
      if (tetrisScore > tetrisTopScore)
        SharedPreferences.getInstance().then(
          (prefs) =>
              prefs.setInt('tetris_top_score', tetrisTopScore = tetrisScore),
        );
    }
  }

  bool _checkTetrisCollision(List<Point<int>> piece, Point<int> offset) {
    for (var p in piece) {
      int x = p.x + offset.x, y = p.y + offset.y;
      if (x < 0 || x >= tetrisCols || y >= tetrisRows) return true;
      if (y >= 0 && tetrisBoard[y][x] != 0) return true;
    }
    return false;
  }

  void _updateTetris() {
    if (!isPlayingTetris) return;
    setState(() {
      Point<int> nextOffset = Point(
        tetrisPieceOffset.x,
        tetrisPieceOffset.y + 1,
      );
      if (!_checkTetrisCollision(tetrisPiece, nextOffset)) {
        tetrisPieceOffset = nextOffset;
      } else {
        for (var p in tetrisPiece) {
          int x = p.x + tetrisPieceOffset.x, y = p.y + tetrisPieceOffset.y;
          if (y >= 0 && y < tetrisRows && x >= 0 && x < tetrisCols)
            tetrisBoard[y][x] = tetrisPieceType + 1;
        }
        for (int r = tetrisRows - 1; r >= 0; r--) {
          if (tetrisBoard[r].every((cell) => cell != 0)) {
            tetrisBoard.removeAt(r);
            tetrisBoard.insert(0, List.filled(tetrisCols, 0));
            tetrisScore += 100;
          }
        }
        _spawnTetrisPiece();
      }
    });
  }

  void _moveTetris(int dx) {
    if (!isPlayingTetris) return;
    setState(() {
      Point<int> nextOffset = Point(
        tetrisPieceOffset.x + dx,
        tetrisPieceOffset.y,
      );
      if (!_checkTetrisCollision(tetrisPiece, nextOffset))
        tetrisPieceOffset = nextOffset;
    });
  }

  void _rotateTetris() {
    if (!isPlayingTetris) return;
    setState(() {
      List<Point<int>> rotated = tetrisPiece
          .map((p) => Point(-p.y, p.x))
          .toList();
      if (!_checkTetrisCollision(rotated, tetrisPieceOffset))
        tetrisPiece = rotated;
    });
  }

  // --- 2048 LOGIC ---
  void _start2048() {
    board2048 = List.filled(16, 0);
    score2048 = 0;
    isGameOver2048 = false;
    _spawn2048();
    _spawn2048();
    setState(() {});
  }

  void _spawn2048() {
    List<int> empty = [];
    for (int i = 0; i < 16; i++) if (board2048[i] == 0) empty.add(i);
    if (empty.isEmpty) return;
    board2048[empty[Random().nextInt(empty.length)]] =
        Random().nextDouble() < 0.9 ? 2 : 4;
  }

  void _move2048(int dx, int dy) {
    if (isGameOver2048) return;
    bool moved = false;
    List<int> newBoard = List.from(board2048);

    List<int> slide(List<int> line) {
      List<int> res = line.where((v) => v != 0).toList();
      for (int i = 0; i < res.length - 1; i++) {
        if (res[i] == res[i + 1]) {
          res[i] *= 2;
          score2048 += res[i];
          res.removeAt(i + 1);
        }
      }
      while (res.length < 4) res.add(0);
      return res;
    }

    for (int i = 0; i < 4; i++) {
      List<int> line = [];
      for (int j = 0; j < 4; j++) {
        if (dx == -1) line.add(board2048[i * 4 + j]);
        if (dx == 1) line.add(board2048[i * 4 + (3 - j)]);
        if (dy == -1) line.add(board2048[j * 4 + i]);
        if (dy == 1) line.add(board2048[(3 - j) * 4 + i]);
      }
      line = slide(line);
      for (int j = 0; j < 4; j++) {
        int index = 0;
        if (dx == -1) index = i * 4 + j;
        if (dx == 1) index = i * 4 + (3 - j);
        if (dy == -1) index = j * 4 + i;
        if (dy == 1) index = (3 - j) * 4 + i;
        if (newBoard[index] != line[j]) moved = true;
        newBoard[index] = line[j];
      }
    }

    if (moved) {
      board2048 = newBoard;
      _spawn2048();
      if (!board2048.contains(0)) {
        bool hasMove = false;
        for (int i = 0; i < 16; i++) {
          int x = i % 4, y = i ~/ 4;
          if (x < 3 && board2048[i] == board2048[i + 1]) hasMove = true;
          if (y < 3 && board2048[i] == board2048[i + 4]) hasMove = true;
        }
        if (!hasMove) {
          isGameOver2048 = true;
          if (score2048 > topScore2048)
            SharedPreferences.getInstance().then(
              (p) => p.setInt('2048_top_score', topScore2048 = score2048),
            );
        }
      }
      setState(() {});
    }
  }

  // --- RACING LOGIC (BPM Adaptativo) ---
  void _startRacing() {
    playerLane = 1;
    enemyCars.clear();
    racingScore = 0;
    isRacingGameOver = false;
    isPlayingRacing = true;
    racingTimer?.cancel();
    double speedFactor = 0.4 + ((currentTrackBpm) * 0.002);
    racingTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!isPlayingRacing) return;
      setState(() {
        for (var c in enemyCars) c['y'] = c['y']! + speedFactor;
        if (enemyCars.isNotEmpty && enemyCars.first['y']! > 20) {
          enemyCars.removeAt(0);
          racingScore += 10;
        }
        if (enemyCars.isEmpty || enemyCars.last['y']! > 6) {
          if (Random().nextDouble() < 0.3)
            enemyCars.add({'lane': Random().nextInt(3).toDouble(), 'y': -4});
        }
        for (var c in enemyCars) {
          if (c['lane'] == playerLane && c['y']! + 2.8 > 16 && c['y']! < 18.8) {
            isPlayingRacing = false;
            isRacingGameOver = true;
            racingTimer?.cancel();
            if (racingScore > racingTopScore)
              SharedPreferences.getInstance().then(
                (p) =>
                    p.setInt('racing_top_score', racingTopScore = racingScore),
              );
          }
        }
      });
    });
  }

  // --- FLAPPY BIRD LOGIC (BPM Adaptativo) ---
  void _startFlappy() {
    birdY = 10;
    birdVelocity = 0;
    pipes.clear();
    flappyScore = 0;
    isFlappyGameOver = false;
    isPlayingFlappy = true;
    flappyTimer?.cancel();
    // Velocidade de deslocamento dos canos e gravidade adaptada ao BPM
    double pipeSpeed = 0.5 + ((currentTrackBpm - 120) * 0.003);
    flappyTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!isPlayingFlappy) return;
      setState(() {
        birdVelocity += 0.2;
        birdY += birdVelocity;
        for (var p in pipes) p['x'] = p['x']! - pipeSpeed;
        if (pipes.isNotEmpty && pipes.first['x']! < -3) {
          pipes.removeAt(0);
          flappyScore += 10;
        }
        if (pipes.isEmpty || pipes.last['x']! < 10)
          pipes.add({'x': 20, 'gapY': Random().nextInt(8) + 2.0});

        if (birdY < 0 || birdY > 19) _gameOverFlappy();
        for (var p in pipes) {
          if (p['x']! < 4 && p['x']! + 2 > 1.5) {
            if (birdY < p['gapY']! || birdY + 1.5 > p['gapY']! + 5)
              _gameOverFlappy();
          }
        }
      });
    });
  }

  void _gameOverFlappy() {
    isPlayingFlappy = false;
    isFlappyGameOver = true;
    flappyTimer?.cancel();
    if (flappyScore > flappyTopScore)
      SharedPreferences.getInstance().then(
        (p) => p.setInt('flappy_top_score', flappyTopScore = flappyScore),
      );
  }

  // --- FROGGER LOGIC (BPM Adaptativo) ---
  void _startFrogger() {
    frogPos = const Point(7, 14);
    froggerScore = 0;
    isFroggerGameOver = false;
    isPlayingFrogger = true;
    double bpmMultiplier = 1.0 + ((currentTrackBpm - 120) * 0.005);
    roadCars = [
      {'row': 12, 'x': 0.0, 'speed': 0.5 * bpmMultiplier, 'dir': 1, 'len': 2},
      {'row': 10, 'x': 10.0, 'speed': 0.8 * bpmMultiplier, 'dir': -1, 'len': 3},
      {'row': 8, 'x': 5.0, 'speed': 1.0 * bpmMultiplier, 'dir': 1, 'len': 2},
      {'row': 6, 'x': 12.0, 'speed': 0.6 * bpmMultiplier, 'dir': -1, 'len': 4},
      {'row': 4, 'x': 2.0, 'speed': 1.2 * bpmMultiplier, 'dir': 1, 'len': 2},
      {'row': 2, 'x': 8.0, 'speed': 0.9 * bpmMultiplier, 'dir': -1, 'len': 3},
    ];
    froggerTimer?.cancel();
    froggerTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!isPlayingFrogger) return;
      setState(() {
        for (var c in roadCars) {
          c['x'] += c['speed'] * c['dir'];
          if (c['dir'] == 1 && c['x'] > 15) c['x'] = -c['len'].toDouble();
          if (c['dir'] == -1 && c['x'] < -c['len']) c['x'] = 15.0;
          if (frogPos.y == c['row']) {
            if (frogPos.x + 0.8 > c['x'] && frogPos.x < c['x'] + c['len']) {
              isPlayingFrogger = false;
              isFroggerGameOver = true;
              froggerTimer?.cancel();
              if (froggerScore > froggerTopScore)
                SharedPreferences.getInstance().then(
                  (p) => p.setInt(
                    'frogger_top_score',
                    froggerTopScore = froggerScore,
                  ),
                );
            }
          }
        }
      });
    });
  }

  void _moveFrogger(int dx, int dy) {
    if (!isPlayingFrogger || isFroggerGameOver) return;
    setState(() {
      int nx = (frogPos.x + dx).clamp(0, 14),
          ny = (frogPos.y + dy).clamp(0, 14);
      frogPos = Point(nx, ny);
      if (ny == 0) {
        froggerScore += 50;
        frogPos = const Point(7, 14);
        for (var c in roadCars) c['speed'] += 0.1;
      }
    });
  }

  void _handleMenuSelection() {
    final id = menuItems[selectedMenuItem]['id'];
    if (id == 'open_folder')
      requestPermissionsAndPickFolder();
    else if (id == 'library')
      setState(() {
        currentView = 'library';
        selectedLibraryItem = max(
          0,
          filteredLibraryPaths.indexOf(
            queuePaths.isNotEmpty ? queuePaths[currentIndex] : '',
          ),
        );
      });
    else if (id == 'queue')
      setState(() => currentView = 'queue');
    else if (id == 'equalizer')
      setState(() {
        currentView = 'equalizer';
        selectedEqPreset = selectedEqPreset
            .clamp(0, eqPresets.length - 1)
            .toInt();
      });
    else if (id == 'settings')
      setState(() {
        currentView = 'settings';
        selectedMenuItem = 0;
      });
    else if (id == 'games') {
      if (_focusModeEndTime != null &&
          DateTime.now().isBefore(_focusModeEndTime!)) {
        setState(() {
          currentView = 'player';
          currentTrackName = "FOCO ATIVO!";
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && currentView == 'player') {
            setState(() {
              if (queuePaths.isNotEmpty &&
                  currentIndex >= 0 &&
                  currentIndex < queuePaths.length) {
                currentTrackName = p.basenameWithoutExtension(
                  queuePaths[currentIndex],
                );
              } else {
                currentTrackName = "NENHUMA FAIXA";
              }
            });
          }
        });
        return;
      }
      setState(() {
        currentView = 'game_menu';
        selectedGameItem = 0;
      });
    }
  }

  void _handleGameSelection() {
    final String? gameId = gameList[selectedGameItem]['id'];
    if (gameId == null) return;

    setState(() {
      currentView = gameId;
      if (gameId == 'snake') {
        isPlayingSnake = false;
        isSnakeGameOver = false;
        snakeScore = 0;
      }
      if (gameId == 'tetris') {
        isPlayingTetris = false;
        isTetrisGameOver = false;
        tetrisScore = 0;
      }
      if (gameId == '2048') {
        isGameOver2048 = false;
        score2048 = 0;
        board2048 = List.filled(16, 0);
        _spawn2048();
        _spawn2048();
      }
      if (gameId == 'racing') {
        isPlayingRacing = false;
        isRacingGameOver = false;
        racingScore = 0;
        enemyCars.clear();
        playerLane = 1;
      }
      if (gameId == 'flappy') {
        isPlayingFlappy = false;
        isFlappyGameOver = false;
        flappyScore = 0;
        pipes.clear();
        birdY = 10;
      }
      if (gameId == 'frogger') {
        isPlayingFrogger = false;
        isFroggerGameOver = false;
        froggerScore = 0;
        roadCars.clear();
        frogPos = const Point(7, 14);
      }
    });
  }

  void _handleBackButton() {
    setState(() {
      if ([
        'snake',
        'tetris',
        '2048',
        'racing',
        'flappy',
        'frogger',
      ].contains(currentView)) {
        snakeTimer?.cancel();
        tetrisTimer?.cancel();
        racingTimer?.cancel();
        flappyTimer?.cancel();
        froggerTimer?.cancel();
        isPlayingSnake = false;
        isPlayingTetris = false;
        isPlayingRacing = false;
        isPlayingFlappy = false;
        isPlayingFrogger = false;
        currentView = 'game_menu';
      } else if (currentView == 'game_menu' ||
          currentView == 'library' ||
          currentView == 'queue' ||
          currentView == 'equalizer' ||
          currentView == 'settings') {
        currentView = 'menu';
        selectedMenuItem = 0;
      } else if (currentView == 'menu') {
        currentView = 'player';
      } else if (currentView == 'player') {
        isRepeat = !isRepeat;
        player.setPlaylistMode(
          isRepeat ? PlaylistMode.loop : PlaylistMode.none,
        );
      }
    });
  }

  String formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = currentTheme;
    return Scaffold(
      backgroundColor: const Color(0xFF1E292B),
      body: Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.deviceColor,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.black, width: 4),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  flex: 4,
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.screenColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.black, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: theme.screenColor.withValues(alpha: 0.3),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(17),
                          child: CustomPaint(
                            painter: CRTGridPainter(),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: isLoadingFolder
                                  ? const Center(
                                      key: ValueKey('Loading'),
                                      child: CircularProgressIndicator(
                                        color: Colors.black,
                                      ),
                                    )
                                  : _buildCurrentScreen(),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 12,
                        child: Row(
                          children: [
                            const Text(
                              "POWER",
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'RetroFont',
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isPlaying
                                    ? theme.ledColor
                                    : Colors.black38,
                                boxShadow: isPlaying
                                    ? [
                                        BoxShadow(
                                          color: theme.ledColor,
                                          blurRadius: 6,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : [],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          InteractiveRetroButton(
                            color: theme.menuColor,
                            borderColor: Colors.black,
                            width: 120,
                            height: 35,
                            borderRadius: 15,
                            onTap: () => setState(() {
                              if (currentView == 'menu') {
                                currentView = 'player';
                              } else {
                                currentView = 'menu';
                                selectedMenuItem = 0;
                              }
                            }),
                            child: const Center(
                              child: Text(
                                'MENU',
                                style: TextStyle(
                                  color: Color(0xFF88CBB0),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 40),
                          Column(
                            children: [
                              InteractiveRetroButton(
                                color: theme.okColor,
                                borderColor: Colors.black,
                                width: 30,
                                height: 30,
                                isCircle: true,
                                onTap: () {
                                  if (currentView == 'menu')
                                    _handleMenuSelection();
                                  else if (currentView == 'game_menu')
                                    _handleGameSelection();
                                  else if (currentView == 'equalizer') {
                                    _saveData();
                                  } else if (currentView == 'library' &&
                                      libraryPaths.isNotEmpty) {
                                    if (filteredLibraryPaths.isEmpty) return;
                                    final tappedItem =
                                        filteredLibraryPaths[selectedLibraryItem];
                                    queuePaths = List.from(libraryPaths);
                                    if (isShuffle) {
                                      List<String> remaining = List.from(
                                        libraryPaths,
                                      )..remove(tappedItem);
                                      remaining.shuffle();
                                      queuePaths = [tappedItem, ...remaining];
                                      currentIndex = 0;
                                    } else {
                                      currentIndex = libraryPaths.indexOf(
                                        tappedItem,
                                      );
                                    }
                                    _playPlaylist(
                                      startIndex: currentIndex,
                                      autoPlay: true,
                                    );
                                    setState(() {
                                      currentView = 'player';
                                      _searchController.clear();
                                      _searchQuery = '';
                                      _showSearchBar = true;
                                    });
                                  } else if (currentView == 'settings') {
                                    if (selectedMenuItem == 0) {
                                      setState(
                                        () => currentLang = currentLang == 'pt'
                                            ? 'en'
                                            : 'pt',
                                      );
                                      _saveData();
                                    } else if (selectedMenuItem == 1) {
                                      setState(
                                        () => currentThemeIndex =
                                            (currentThemeIndex + 1) %
                                            retroThemes.length,
                                      );
                                      _saveData();
                                    } else if (selectedMenuItem == 2) {
                                      setState(
                                        () => visualStyle =
                                            visualStyle == 'spectrum'
                                            ? 'waves'
                                            : 'spectrum',
                                      );
                                      _saveData();
                                    } else if (selectedMenuItem == 3) {
                                      setState(() {
                                        _focusModeDuration =
                                            _focusModeDuration == 0
                                            ? 15
                                            : _focusModeDuration == 15
                                            ? 30
                                            : _focusModeDuration == 30
                                            ? 60
                                            : 0;
                                        if (_focusModeDuration > 0) {
                                          _focusModeEndTime = DateTime.now()
                                              .add(
                                                Duration(
                                                  minutes: _focusModeDuration,
                                                ),
                                              );
                                        } else {
                                          _focusModeEndTime = null;
                                        }
                                      });
                                    } else {
                                      setState(() {
                                        libraryPaths.clear();
                                        queuePaths.clear();
                                        currentView = 'player';
                                      });
                                      _saveData();
                                    }
                                  }
                                },
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'OK',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          InteractiveDPad(
                            color: theme.dpadColor,
                            onUp: () {
                              if (currentView == 'library') {
                                setState(
                                  () => selectedLibraryItem = max(
                                    0,
                                    selectedLibraryItem - 1,
                                  ),
                                );
                                _scrollToItem(
                                  _libraryScrollController,
                                  selectedLibraryItem,
                                );
                              } else if (currentView == 'menu') {
                                setState(
                                  () => selectedMenuItem = max(
                                    0,
                                    selectedMenuItem - 1,
                                  ),
                                );
                                _scrollToItem(
                                  _menuScrollController,
                                  selectedMenuItem,
                                );
                              } else if (currentView == 'equalizer') {
                                setState(
                                  () => selectedEqPreset = max(
                                    0,
                                    selectedEqPreset - 1,
                                  ),
                                );
                                _saveData();
                              } else if (currentView == 'settings') {
                                setState(
                                  () => selectedMenuItem = max(
                                    0,
                                    selectedMenuItem - 1,
                                  ),
                                );
                                _scrollToItem(
                                  _settingsScrollController,
                                  selectedMenuItem,
                                );
                              } else if (currentView == 'game_menu') {
                                setState(
                                  () => selectedGameItem = max(
                                    0,
                                    selectedGameItem - 1,
                                  ),
                                );
                                _scrollToItem(
                                  _gameMenuScrollController,
                                  selectedGameItem,
                                );
                              } else if (currentView == 'snake') {
                                if (snakeDir != const Point(0, 1))
                                  snakeDir = const Point(0, -1);
                              } else if (currentView == 'tetris')
                                _rotateTetris();
                              else if (currentView == '2048')
                                _move2048(0, -1);
                              else if (currentView == 'flappy')
                                birdVelocity = -1.8;
                              else if (currentView == 'frogger')
                                _moveFrogger(0, -1);
                              else if (currentView == 'player')
                                _handleVolumeChange(10.0);
                            },
                            onDown: () {
                              if (currentView == 'library') {
                                setState(
                                  () => selectedLibraryItem = min(
                                    filteredLibraryPaths.length - 1,
                                    selectedLibraryItem + 1,
                                  ),
                                );
                                _scrollToItem(
                                  _libraryScrollController,
                                  selectedLibraryItem,
                                );
                              } else if (currentView == 'menu') {
                                setState(
                                  () => selectedMenuItem = min(
                                    menuItems.length - 1,
                                    selectedMenuItem + 1,
                                  ),
                                );
                                _scrollToItem(
                                  _menuScrollController,
                                  selectedMenuItem,
                                );
                              } else if (currentView == 'equalizer') {
                                setState(
                                  () => selectedEqPreset = min(
                                    eqPresets.length - 1,
                                    selectedEqPreset + 1,
                                  ),
                                );
                                _saveData();
                              } else if (currentView == 'game_menu') {
                                setState(
                                  () => selectedGameItem = min(
                                    gameList.length - 1,
                                    selectedGameItem + 1,
                                  ),
                                );
                                _scrollToItem(
                                  _gameMenuScrollController,
                                  selectedGameItem,
                                );
                              } else if (currentView == 'settings') {
                                setState(
                                  () => selectedMenuItem = min(
                                    4,
                                    selectedMenuItem + 1,
                                  ),
                                );
                                _scrollToItem(
                                  _settingsScrollController,
                                  selectedMenuItem,
                                );
                              } else if (currentView == 'snake') {
                                if (snakeDir != const Point(0, -1))
                                  snakeDir = const Point(0, 1);
                              } else if (currentView == 'tetris')
                                _updateTetris();
                              else if (currentView == '2048')
                                _move2048(0, 1);
                              else if (currentView == 'frogger')
                                _moveFrogger(0, 1);
                              else if (currentView == 'player')
                                _handleVolumeChange(-10.0);
                            },
                            onLeft: () {
                              if (currentView == 'snake') {
                                if (snakeDir != const Point(1, 0))
                                  snakeDir = const Point(-1, 0);
                              } else if (currentView == 'tetris')
                                _moveTetris(-1);
                              else if (currentView == '2048')
                                _move2048(-1, 0);
                              else if (currentView == 'racing')
                                setState(
                                  () => playerLane = max(0, playerLane - 1),
                                );
                              else if (currentView == 'frogger')
                                _moveFrogger(-1, 0);
                              else
                                player.previous();
                            },
                            onRight: () {
                              if (currentView == 'snake') {
                                if (snakeDir != const Point(-1, 0))
                                  snakeDir = const Point(1, 0);
                              } else if (currentView == 'tetris')
                                _moveTetris(1);
                              else if (currentView == '2048')
                                _move2048(1, 0);
                              else if (currentView == 'racing')
                                setState(
                                  () => playerLane = min(2, playerLane + 1),
                                );
                              else if (currentView == 'frogger')
                                _moveFrogger(1, 0);
                              else
                                player.next();
                            },
                          ),
                          Row(
                            children: [
                              Column(
                                children: [
                                  InteractiveRetroButton(
                                    color: theme.playColor,
                                    borderColor: Colors.black,
                                    width: 55,
                                    height: 55,
                                    isCircle: true,
                                    onTap: () {
                                      if (currentView == 'snake') {
                                        if (isSnakeGameOver || !isPlayingSnake)
                                          _startSnakeGame();
                                        else
                                          setState(
                                            () => isPlayingSnake =
                                                !isPlayingSnake,
                                          );
                                      } else if (currentView == 'tetris') {
                                        if (isTetrisGameOver ||
                                            !isPlayingTetris)
                                          _startTetrisGame();
                                        else
                                          setState(
                                            () => isPlayingTetris =
                                                !isPlayingTetris,
                                          );
                                      } else if (currentView == '2048') {
                                        if (isGameOver2048 || score2048 == 0)
                                          _start2048();
                                      } else if (currentView == 'racing') {
                                        if (isRacingGameOver ||
                                            !isPlayingRacing)
                                          _startRacing();
                                        else
                                          setState(
                                            () => isPlayingRacing = false,
                                          );
                                      } else if (currentView == 'flappy') {
                                        if (isFlappyGameOver ||
                                            !isPlayingFlappy)
                                          _startFlappy();
                                        else
                                          setState(
                                            () => isPlayingFlappy = false,
                                          );
                                      } else if (currentView == 'frogger') {
                                        if (isFroggerGameOver ||
                                            !isPlayingFrogger)
                                          _startFrogger();
                                        else
                                          setState(
                                            () => isPlayingFrogger = false,
                                          );
                                      } else
                                        player.playOrPause();
                                    },
                                    child: const Center(
                                      child: Icon(
                                        Icons.play_arrow,
                                        color: Colors.black87,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'PLAY',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 20),
                              Column(
                                children: [
                                  InteractiveRetroButton(
                                    color: theme.mixColor,
                                    borderColor: Colors.black,
                                    width: 40,
                                    height: 40,
                                    isCircle: true,
                                    onTap: _handleShuffleToggle,
                                    child: Icon(
                                      Icons.shuffle,
                                      size: 20,
                                      color: isShuffle
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'MIX',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 10,
                              bottom: 10,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 35,
                                  height: 10,
                                  decoration: boxDecoBorder(
                                    theme.okColor,
                                    radius: 10,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Container(
                                  width: 35,
                                  height: 10,
                                  decoration: boxDecoBorder(
                                    theme.okColor,
                                    radius: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 15),
                                child: InteractiveRetroButton(
                                  color: theme.backColor,
                                  borderColor: Colors.black87,
                                  width: 70,
                                  height: 70,
                                  isCircle: true,
                                  onTap: _handleBackButton,
                                  child: Icon(
                                    currentView != 'player'
                                        ? Icons.undo
                                        : Icons.repeat,
                                    size: 30,
                                    color: isRepeat && currentView == 'player'
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(right: 15, top: 4),
                                child: Text(
                                  'VOLTAR',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (currentView) {
      case 'menu':
        return _buildMenuView();
      case 'library':
        return _buildLibraryView();
      case 'queue':
        return _buildQueueView();
      case 'equalizer':
        return _buildEqualizerView();
      case 'settings':
        return _buildSettingsView();
      case 'game_menu':
        return _buildGameMenuView();
      case 'snake':
        return _buildSnakeView();
      case 'tetris':
        return _buildTetrisView();
      case '2048':
        return _build2048View();
      case 'racing':
        return _buildRacingView();
      case 'flappy':
        return _buildFlappyView();
      case 'frogger':
        return _buildFroggerView();
      default:
        return _buildPlayerView();
    }
  }

  Widget _buildGameWrapper(
    String title,
    int score,
    int top,
    Widget gameChild,
    bool isGameOver,
    bool isPlaying,
    double aspectRatio,
  ) {
    return SizedBox.expand(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SCORE: $score',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'RetroFont',
                    fontSize: 14,
                  ),
                ),
                Text(
                  'TOP: $top',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'RetroFont',
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  double sizeW = min(
                    constraints.maxWidth,
                    constraints.maxHeight * aspectRatio,
                  );
                  double sizeH = sizeW / aspectRatio;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: sizeW,
                      height: sizeH,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black, width: 2),
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                        child: Stack(
                          children: [
                            gameChild,
                            if (isGameOver)
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  color: Colors.black87,
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'GAME OVER',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'RetroFont',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        'PRESS PLAY',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontFamily: 'RetroFont',
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else if (!isPlaying && !isGameOver)
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  color: Colors.black87,
                                  child: const Text(
                                    'PRESS PLAY',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'RetroFont',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnakeView() {
    return _buildGameWrapper(
      "SNAKE",
      snakeScore,
      snakeTopScore,
      GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: snakeGridSize * snakeGridSize,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: snakeGridSize,
          childAspectRatio: 1.0,
        ),
        itemBuilder: (context, index) {
          Point<int> p = Point(index % snakeGridSize, index ~/ snakeGridSize);
          bool isFood = snakeFood == p;
          Color color = snakeBody.contains(p)
              ? (p == snakeBody.first ? Colors.black : Colors.black87)
              : (isFood ? Colors.red : Colors.transparent);
          return Container(
            margin: const EdgeInsets.all(0.5),
            decoration: BoxDecoration(
              color: color,
              shape: isFood ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: isFood ? null : BorderRadius.circular(1),
            ),
          );
        },
      ),
      isSnakeGameOver,
      isPlayingSnake,
      1.0,
    );
  }

  Widget _buildTetrisView() {
    return _buildGameWrapper(
      "TETRIS",
      tetrisScore,
      tetrisTopScore,
      GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tetrisCols * tetrisRows,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: tetrisCols,
          childAspectRatio: 1.0,
        ),
        itemBuilder: (context, index) {
          int r = index ~/ tetrisCols, c = index % tetrisCols;
          bool isPiecePart = tetrisPiece.any(
            (p) =>
                p.x + tetrisPieceOffset.x == c &&
                p.y + tetrisPieceOffset.y == r,
          );
          Color col = isPiecePart
              ? Colors.black
              : (tetrisBoard[r][c] > 0 ? Colors.black87 : Colors.transparent);
          return Container(
            margin: const EdgeInsets.all(0.3),
            decoration: BoxDecoration(
              color: col,
              borderRadius: BorderRadius.circular(1),
            ),
          );
        },
      ),
      isTetrisGameOver,
      isPlayingTetris,
      tetrisCols / tetrisRows,
    );
  }

  Widget _build2048View() {
    return _buildGameWrapper(
      "2048",
      score2048,
      topScore2048,
      GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 16,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
        ),
        itemBuilder: (context, index) {
          int val = board2048[index];
          double opacity = val == 0
              ? 0.08
              : min(1.0, 0.2 + ((log(val) / log(2)).floor() * 0.1));
          return Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(opacity),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                val > 0 ? '$val' : '',
                style: TextStyle(
                  color: opacity > 0.6 ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  fontFamily: 'RetroFont',
                ),
              ),
            ),
          );
        },
      ),
      isGameOver2048,
      true,
      1.0,
    );
  }

  Widget _buildRacingView() {
    return _buildGameWrapper(
      "RACING",
      racingScore,
      racingTopScore,
      LayoutBuilder(
        builder: (ctx, consts) {
          double laneW = consts.maxWidth / 3, cellH = consts.maxHeight / 20;
          return Stack(
            children: [
              Positioned(
                left: laneW,
                top: 0,
                bottom: 0,
                width: 2,
                child: Container(color: Colors.black26),
              ),
              Positioned(
                left: laneW * 2,
                top: 0,
                bottom: 0,
                width: 2,
                child: Container(color: Colors.black26),
              ),
              Positioned(
                left: playerLane * laneW + (laneW * 0.2),
                top: 16 * cellH,
                width: laneW * 0.6,
                height: cellH * 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              ...enemyCars.map(
                (car) => Positioned(
                  left: car['lane']! * laneW + (laneW * 0.2),
                  top: car['y']! * cellH,
                  width: laneW * 0.6,
                  height: cellH * 3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      isRacingGameOver,
      isPlayingRacing,
      0.7,
    );
  }

  Widget _buildFlappyView() {
    return _buildGameWrapper(
      "FLAPPY",
      flappyScore,
      flappyTopScore,
      LayoutBuilder(
        builder: (ctx, consts) {
          double cellW = consts.maxWidth / 20, cellH = consts.maxHeight / 20;
          return Stack(
            children: [
              Positioned(
                left: 3 * cellW,
                top: birdY * cellH,
                width: cellW * 1.5,
                height: cellH * 1.5,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              ...pipes.map(
                (p) => Positioned(
                  left: p['x']! * cellW,
                  top: 0,
                  width: 2 * cellW,
                  height: p['gapY']! * cellH,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              ...pipes.map(
                (p) => Positioned(
                  left: p['x']! * cellW,
                  top: (p['gapY']! + 5) * cellH,
                  width: 2 * cellW,
                  height: (20 - (p['gapY']! + 5)) * cellH,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      isFlappyGameOver,
      isPlayingFlappy,
      1.0,
    );
  }

  Widget _buildFroggerView() {
    return _buildGameWrapper(
      "FROGGER",
      froggerScore,
      froggerTopScore,
      LayoutBuilder(
        builder: (ctx, consts) {
          double cellW = consts.maxWidth / 15, cellH = consts.maxHeight / 15;
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 14 * cellH,
                height: cellH,
                child: Container(color: Colors.black12),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: cellH,
                child: Container(color: Colors.black12),
              ),
              ...roadCars.map(
                (c) => Positioned(
                  left: c['x'] * cellW,
                  top: c['row'] * cellH + (cellH * 0.1),
                  width: c['len'] * cellW,
                  height: cellH * 0.8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: frogPos.x * cellW,
                top: frogPos.y * cellH,
                width: cellW,
                height: cellH,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      isFroggerGameOver,
      isPlayingFrogger,
      1.0,
    );
  }

  Widget _buildPlayerView() {
    return Stack(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextScroll(
                currentTrackName,
                mode: TextScrollMode.bouncing,
                velocity: const Velocity(pixelsPerSecond: Offset(30, 0)),
                pauseBetween: const Duration(seconds: 2),
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  fontFamily: 'RetroFont',
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 30),
            visualStyle == 'spectrum'
                ? CustomPaint(
                    size: const Size(120, 60),
                    painter: SpectrumPainter(bars: spectrumBars),
                  )
                : CustomPaint(
                    size: const Size(180, 60),
                    painter: WaveformPainter(
                      phase: wavePhase,
                      amplitude: currentWaveAmplitude,
                      complexity: currentWaveComplexity,
                      color: Colors.black87,
                    ),
                  ),
            const SizedBox(height: 35),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: Row(
                children: [
                  Text(
                    formatDuration(position),
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'RetroFont',
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: SliderComponentShape.noOverlay,
                        trackHeight: 6,
                        activeTrackColor: Colors.black,
                        inactiveTrackColor: Colors.black26,
                        thumbColor: Colors.black,
                      ),
                      child: Slider(
                        min: 0.0,
                        max: duration.inMilliseconds > 0
                            ? duration.inMilliseconds.toDouble()
                            : 1.0,
                        value: position.inMilliseconds.toDouble().clamp(
                          0.0,
                          duration.inMilliseconds > 0
                              ? duration.inMilliseconds.toDouble()
                              : 1.0,
                        ),
                        onChanged: (v) =>
                            player.seek(Duration(milliseconds: v.toInt())),
                      ),
                    ),
                  ),
                  Text(
                    formatDuration(duration),
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'RetroFont',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (showVolumeIndicator)
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "${lang[currentLang]!['vol']}: ${currentVolume.toInt()}%",
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'RetroFont',
                  fontSize: 14,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMenuView() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              lang[currentLang]!['menu_title']!,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                fontFamily: 'RetroFont',
              ),
            ),
          ),
          const Divider(color: Colors.black, thickness: 2, height: 25),
          Expanded(
            child: ListView.builder(
              controller: _menuScrollController,
              itemCount: menuItems.length,
              itemBuilder: (context, index) {
                final isSelected = index == selectedMenuItem;
                return GestureDetector(
                  onTap: () {
                    setState(() => selectedMenuItem = index);
                    _handleMenuSelection();
                  },
                  child: Container(
                    height: 54,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.black.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(color: Colors.black, width: 2)
                          : Border.all(color: Colors.transparent, width: 2),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          menuItems[index]['icon'],
                          color: Colors.black,
                          size: 28,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          lang[currentLang]![menuItems[index]['id']]!,
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            fontFamily: 'RetroFont',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEqualizerView() {
    final preset = eqPresets[selectedEqPreset];
    final isPortuguese = currentLang == 'pt';
    final presetName = isPortuguese ? preset['pt'] : preset['en'];
    final description = isPortuguese
        ? preset['descriptionPt']
        : preset['descriptionEn'];
    final bands = (preset['bands'] as List).cast<double>();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              lang[currentLang]!['equalizer']!,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                fontFamily: 'RetroFont',
              ),
            ),
          ),
          const Divider(color: Colors.black, thickness: 2, height: 25),
          Expanded(
            child: ListView.builder(
              itemCount: eqPresets.length,
              itemBuilder: (context, index) {
                final item = eqPresets[index];
                final isSelected = index == selectedEqPreset;
                final itemName = isPortuguese ? item['pt'] : item['en'];
                final itemDescription = isPortuguese
                    ? item['descriptionPt']
                    : item['descriptionEn'];
                return GestureDetector(
                  onTap: () {
                    setState(() => selectedEqPreset = index);
                    _saveData();
                  },
                  child: Container(
                    height: 58,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.black.withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: Colors.black,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                itemName,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  fontFamily: 'RetroFont',
                                ),
                              ),
                              Text(
                                itemDescription,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 11,
                                  fontFamily: 'RetroFont',
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 64,
                          height: 32,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: bands
                                .map(
                                  (value) => Container(
                                    width: 8,
                                    height: 8 + value * 22,
                                    color: Colors.black,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '$presetName  •  $description',
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 11,
                fontFamily: 'RetroFont',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameMenuView() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'ESCOLHE O JOGO',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                fontFamily: 'RetroFont',
              ),
            ),
          ),
          const Divider(color: Colors.black, thickness: 2, height: 25),
          Expanded(
            child: ListView.builder(
              controller: _gameMenuScrollController,
              itemCount: gameList.length,
              itemBuilder: (context, index) {
                final isSelected = index == selectedGameItem;
                return GestureDetector(
                  onTap: () {
                    setState(() => selectedGameItem = index);
                    _handleGameSelection();
                  },
                  child: Container(
                    height: 54,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.black.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(color: Colors.black, width: 2)
                          : Border.all(color: Colors.transparent, width: 2),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.sports_esports,
                          color: Colors.black,
                          size: 28,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          gameList[index]['title']!,
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            fontFamily: 'RetroFont',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryView() {
    if (libraryPaths.isEmpty)
      return Center(
        child: Text(
          lang[currentLang]!['lib_empty']!,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
            fontFamily: 'RetroFont',
          ),
        ),
      );

    final currentList = filteredLibraryPaths;

    return Container(
      padding: const EdgeInsets.only(top: 16, bottom: 16, left: 16, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              lang[currentLang]!['library']!,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                fontFamily: 'RetroFont',
              ),
            ),
          ),
          const Divider(color: Colors.black, thickness: 2, height: 10),

          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: _showSearchBar ? 45 : 0,
            margin: EdgeInsets.only(bottom: _showSearchBar ? 10 : 0, right: 8),
            child: ClipRect(
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    selectedLibraryItem = 0;
                    _showSearchBar = true;
                  });
                },
                style: const TextStyle(
                  color: Colors.black,
                  fontFamily: 'RetroFont',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  hintText: 'PESQUISAR...',
                  hintStyle: const TextStyle(
                    color: Colors.black54,
                    fontFamily: 'RetroFont',
                  ),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.1),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.black,
                    size: 20,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.black, width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.black, width: 2),
                  ),
                ),
              ),
            ),
          ),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                double maxExt = _libraryScrollController.hasClients
                    ? _libraryScrollController.position.maxScrollExtent
                    : 0.0;
                double offset = _libraryScrollController.hasClients
                    ? _libraryScrollController.offset
                    : 0.0;
                double progress = maxExt > 0
                    ? (offset / maxExt).clamp(0.0, 1.0)
                    : 0.0;

                return Stack(
                  children: [
                    ListView.builder(
                      controller: _libraryScrollController,
                      itemCount: currentList.length,
                      itemBuilder: (context, index) {
                        final isSelected = index == selectedLibraryItem;
                        final isPlayingTrack =
                            queuePaths.isNotEmpty &&
                            queuePaths[currentIndex] == currentList[index];
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedLibraryItem = index;
                              final tappedItem = currentList[index];
                              queuePaths = List.from(libraryPaths);
                              if (isShuffle) {
                                List<String> remaining = List.from(libraryPaths)
                                  ..remove(tappedItem);
                                remaining.shuffle();
                                queuePaths = [tappedItem, ...remaining];
                                currentIndex = 0;
                              } else {
                                currentIndex = libraryPaths.indexOf(tappedItem);
                              }
                              _playPlaylist(
                                startIndex: currentIndex,
                                autoPlay: true,
                              );
                              currentView = 'player';
                              _searchController.clear();
                              _searchQuery = '';
                              _showSearchBar = true;
                            });
                          },
                          child: Container(
                            height: 50,
                            margin: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.black.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(color: Colors.black, width: 2)
                                  : Border.all(
                                      color: Colors.transparent,
                                      width: 2,
                                    ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isPlayingTrack
                                      ? Icons.play_arrow
                                      : Icons.music_note,
                                  color: Colors.black,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    p.basenameWithoutExtension(
                                      currentList[index],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: isPlayingTrack
                                          ? FontWeight.w900
                                          : FontWeight.bold,
                                      fontSize: 13,
                                      fontFamily: 'RetroFont',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    Positioned(
                      right: 4,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onVerticalDragUpdate: (details) {
                          if (currentList.isEmpty) return;
                          double percentage =
                              (details.localPosition.dy / constraints.maxHeight)
                                  .clamp(0.0, 1.0);
                          int targetIndex = (percentage * currentList.length)
                              .clamp(0, currentList.length - 1)
                              .toInt();
                          setState(() {
                            isDraggingLetter = true;
                            currentLetter = p
                                .basenameWithoutExtension(
                                  currentList[targetIndex],
                                )[0]
                                .toUpperCase();
                            selectedLibraryItem = targetIndex;
                          });
                          if (maxExt > 0)
                            _libraryScrollController.jumpTo(
                              percentage * maxExt,
                            );
                        },
                        onVerticalDragEnd: (_) =>
                            setState(() => isDraggingLetter = false),
                        child: Container(
                          width: 25,
                          color: Colors.transparent,
                          child: Stack(
                            children: [
                              Center(
                                child: Container(
                                  width: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.black12,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment(
                                  0,
                                  -1.0 + (progress * 2.0),
                                ),
                                child: Container(
                                  width: 12,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (isDraggingLetter)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            currentLetter,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'RetroFont',
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueView() {
    return Theme(
      data: ThemeData(canvasColor: Colors.transparent),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                lang[currentLang]!['queue']!,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  fontFamily: 'RetroFont',
                ),
              ),
            ),
            const Divider(color: Colors.black, thickness: 2, height: 25),
            Expanded(
              child: ReorderableListView.builder(
                scrollController: _queueScrollController,
                itemCount: queuePaths.length - currentIndex,
                onReorderItem: _reorderQueue,
                itemBuilder: (context, i) {
                  final realIndex = currentIndex + i;
                  final isPlayingTrack = realIndex == currentIndex;
                  return Container(
                    key: ValueKey(queuePaths[realIndex] + realIndex.toString()),
                    height: 50,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isPlayingTrack
                          ? Colors.black.withValues(alpha: 0.25)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isPlayingTrack
                          ? Border.all(color: Colors.black, width: 1.5)
                          : Border.all(color: Colors.transparent, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isPlayingTrack ? Icons.play_arrow : Icons.drag_handle,
                          color: Colors.black54,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            p.basenameWithoutExtension(queuePaths[realIndex]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: isPlayingTrack
                                  ? FontWeight.w900
                                  : FontWeight.bold,
                              fontSize: 13,
                              fontFamily: 'RetroFont',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsView() {
    final settingsOptions = [
      Icons.language,
      Icons.palette,
      Icons.waves,
      Icons.timer,
      Icons.delete_forever,
      Icons.local_cafe,
    ];
    final settingsTitles = [
      lang[currentLang]!['set_lang']!,
      "${lang[currentLang]!['set_theme']}${currentTheme.name}",
      "${lang[currentLang]!['set_visual']}${visualStyle.toUpperCase()}",
      "${lang[currentLang]!['set_focus']}${_focusModeDuration == 0 ? 'OFF' : '$_focusModeDuration MIN'}",
      lang[currentLang]!['set_clear']!,
      lang[currentLang]!['set_github']!,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              lang[currentLang]!['set_title']!,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                fontFamily: 'RetroFont',
              ),
            ),
          ),
          const Divider(color: Colors.black, thickness: 2, height: 25),
          Expanded(
            child: ListView.builder(
              controller: _settingsScrollController,
              itemCount: settingsOptions.length,
              itemBuilder: (context, index) {
                return _buildSettingItem(
                  index,
                  settingsOptions[index],
                  settingsTitles[index],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem(int index, IconData icon, String title) {
    final isSelected = index == selectedMenuItem;
    return GestureDetector(
      onTap: () {
        setState(() => selectedMenuItem = index);
        if (index == 0) {
          setState(() => currentLang = currentLang == 'pt' ? 'en' : 'pt');
          _saveData();
        } else if (index == 1) {
          setState(
            () => currentThemeIndex =
                (currentThemeIndex + 1) % retroThemes.length,
          );
          _saveData();
        } else if (index == 2) {
          setState(
            () =>
                visualStyle = visualStyle == 'spectrum' ? 'waves' : 'spectrum',
          );
          _saveData();
        } else if (index == 3) {
          setState(() {
            _focusModeDuration = _focusModeDuration == 0
                ? 15
                : _focusModeDuration == 15
                ? 30
                : _focusModeDuration == 30
                ? 60
                : 0;
            if (_focusModeDuration > 0) {
              _focusModeEndTime = DateTime.now().add(
                Duration(minutes: _focusModeDuration),
              );
            } else {
              _focusModeEndTime = null;
            }
          });
        } else if (index == 4) {
          setState(() {
            libraryPaths.clear();
            queuePaths.clear();
            currentView = 'player';
          });
          _saveData();
        } else if (index == 5) {
          final Uri url = Uri.parse('https://github.com/alexis6859/bitplayer');
          launchUrl(url, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        height: 54,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.black.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: Colors.black, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.black, size: 28),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                fontFamily: 'RetroFont',
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration boxDecoBorder(
    Color color, {
    bool isCircle = false,
    double radius = 0,
  }) {
    return BoxDecoration(
      color: color,
      shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: isCircle ? null : BorderRadius.circular(radius),
      border: Border.all(color: Colors.black, width: 3.0),
    );
  }
}
