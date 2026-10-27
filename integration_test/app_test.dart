// Teste ponta-a-ponta da app real (com o mpv a tocar áudio de verdade).
//
// Correr com:  flutter test integration_test -d linux
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bitplayer/games/games_main.dart';
import 'package:bitplayer/main.dart' as app;
import 'package:bitplayer/services/audio_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Gera um WAV mono 16-bit com um tom sinusoidal.
Future<void> writeWav(String path, double freq, int seconds) async {
  const rate = 22050;
  final samples = rate * seconds;
  final data = ByteData(44 + samples * 2);
  void str(int o, String s) {
    for (int i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (int i = 0; i < samples; i++) {
    final v = (sin(2 * pi * freq * i / rate) * 3000).toInt();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  await File(path).writeAsBytes(data.buffer.asUint8List());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory musicDir;
  final shotsDir = Directory(
    Platform.environment['BITPLAYER_SHOTS'] ??
        p.join(Directory.systemTemp.path, 'bitplayer_shots'),
  );
  final tracks = ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo'];

  setUpAll(() async {
    musicDir = await Directory.systemTemp.createTemp('bitplayer_music');
    await Directory(p.join(musicDir.path, 'sub')).create();
    for (int i = 0; i < tracks.length; i++) {
      final sub = i.isOdd ? 'sub' : '';
      await writeWav(
        p.join(musicDir.path, sub, '${tracks[i]}.wav'),
        220.0 * (i + 1),
        30,
      );
    }
    await File(p.join(musicDir.path, 'notes.txt')).writeAsString('x');
    await shotsDir.create(recursive: true);
  });

  tearDownAll(() async => musicDir.delete(recursive: true));

  testWidgets('BitPlayer ponta-a-ponta', (tester) async {
    // Preferências em memória: não toca nos dados reais do utilizador.
    SharedPreferences.setMockInitialValues({});

    Future<void> settle([int ms = 150]) async {
      await Future<void>.delayed(Duration(milliseconds: ms));
      await tester.pump();
    }

    Future<void> waitFor(
      bool Function() cond,
      String reason, {
      int timeoutMs = 10000,
    }) async {
      final end = DateTime.now().add(Duration(milliseconds: timeoutMs));
      while (!cond()) {
        if (DateTime.now().isAfter(end)) fail('Timeout: $reason');
        await settle(50);
      }
    }

    Future<void> key(LogicalKeyboardKey k, {int times = 1}) async {
      for (int i = 0; i < times; i++) {
        await tester.sendKeyEvent(k);
        await settle(80);
      }
    }

    Future<void> shot(String name) async {
      await tester.pump();
      final view = tester.binding.renderViews.first;
      final layer = view.debugLayer! as OffsetLayer;
      final image = await layer.toImage(
        Offset.zero & view.size,
        pixelRatio: 1.0,
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        p.join(shotsDir.path, '$name.png'),
      ).writeAsBytes(bytes!.buffer.asUint8List());
    }

    app.main();
    await waitFor(
      () => find.text('NENHUMA FAIXA').evaluate().isNotEmpty,
      'ecrã inicial',
    );
    await shot('01_inicio');

    final dynamic state = tester.state(find.byType(app.RetroDeviceScreen));
    final player = app.audioHandler.player;
    String playingName() {
      final pl = player.state.playlist;
      if (pl.medias.isEmpty || pl.index < 0) return '';
      return p.basenameWithoutExtension(pl.medias[pl.index].uri);
    }

    List<String> playerOrder() => player.state.playlist.medias
        .map((m) => p.basenameWithoutExtension(m.uri))
        .toList();

    // --- Abrir pasta (recursiva, ignora não-áudio, ordena) ---
    await state.loadFolder(musicDir.path);
    await waitFor(() => player.state.playing, 'começar a tocar');
    await waitFor(
      () => player.state.playlist.medias.length == tracks.length,
      'playlist carregada no mpv',
    );
    expect(playerOrder(), tracks);
    expect(playingName(), 'Alpha');
    await waitFor(
      () => player.state.position > const Duration(milliseconds: 1500),
      'posição avançar (áudio a sair do mpv)',
    );
    expect(find.text('Alpha'), findsWidgets);
    await shot('02_a_tocar');

    // --- Volume com o D-pad ---
    await key(LogicalKeyboardKey.arrowDown);
    expect(player.state.volume, closeTo(90, 0.5));
    await key(LogicalKeyboardKey.arrowUp);
    expect(player.state.volume, closeTo(100, 0.5));

    // --- MIX não reinicia a faixa (bug conhecido do README) ---
    await player.seek(const Duration(seconds: 8));
    await waitFor(
      () => player.state.position >= const Duration(seconds: 8),
      'seek',
    );
    await key(LogicalKeyboardKey.keyS);
    await waitFor(() => state.isShuffle == true, 'ativar shuffle');
    await settle(500);
    expect(playingName(), 'Alpha', reason: 'continua na mesma faixa');
    expect(player.state.playing, isTrue);
    expect(
      player.state.position,
      greaterThanOrEqualTo(const Duration(seconds: 8)),
      reason: 'a faixa não pode recomeçar do zero',
    );
    expect(playerOrder().first, 'Alpha');
    expect(playerOrder().toSet(), tracks.toSet());
    expect(
      playerOrder(),
      List<String>.from(
        state.queuePaths,
      ).map((f) => p.basenameWithoutExtension(f)).toList(),
      reason: 'fila da UI = fila do mpv',
    );

    await key(LogicalKeyboardKey.keyS);
    await waitFor(() => state.isShuffle == false, 'desativar shuffle');
    await settle(500);
    expect(playerOrder(), tracks);
    expect(playingName(), 'Alpha');
    expect(
      player.state.position,
      greaterThanOrEqualTo(const Duration(seconds: 8)),
    );

    // --- Próxima / anterior ---
    await key(LogicalKeyboardKey.arrowRight);
    await waitFor(() => playingName() == 'Bravo', 'próxima faixa');
    await waitFor(
      () => find.text('Bravo').evaluate().isNotEmpty,
      'nome atualizado',
    );
    await key(LogicalKeyboardKey.arrowLeft);
    await waitFor(() => playingName() == 'Alpha', 'faixa anterior');

    // --- Equalizador aplica filtros reais no mpv ---
    final native = player.platform as NativePlayer;
    await key(LogicalKeyboardKey.keyM);
    expect(state.currentView, 'menu');
    await key(LogicalKeyboardKey.arrowDown, times: 3);
    await key(LogicalKeyboardKey.enter);
    expect(state.currentView, 'equalizer');
    await key(LogicalKeyboardKey.arrowDown); // BASS BOOST
    await settle(300);
    final af = await native.getProperty('af');
    expect(af, contains('equalizer'), reason: 'af=$af');
    await shot('03_equalizador');
    // Força do efeito: setas esquerda/direita (100% -> 150% -> 50%).
    expect(state.eqStrength, 1.0);
    expect(af, contains('g=8.0'));
    await key(LogicalKeyboardKey.arrowRight, times: 2);
    expect(state.eqStrength, 1.5);
    expect(await native.getProperty('af'), contains('g=12.0'));
    await key(LogicalKeyboardKey.arrowLeft, times: 4);
    expect(state.eqStrength, 0.5);
    expect(await native.getProperty('af'), contains('g=4.0'));
    expect(find.text('50%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('eq_strength_plus')));
    await settle();
    expect(state.eqStrength, 0.75);
    expect(playingName(), 'Alpha', reason: 'setas no EQ não mudam de faixa');
    await shot('03b_forca');
    await key(LogicalKeyboardKey.arrowUp); // NORMAL
    await settle(300);
    final afNormal = await native.getProperty('af');
    expect(afNormal, isNot(contains('equalizer')));
    expect(
      afNormal,
      isNot(contains('astats')),
      reason: 'fora do leitor a medição fica desligada (poupa CPU)',
    );
    expect(player.state.playing, isTrue, reason: 'EQ não pode parar o som');
    final prefsEq = await SharedPreferences.getInstance();
    expect(prefsEq.getDouble('retro_eq_strength'), 0.75);

    // --- Visualizador: o mpv mede a frequência real da faixa ---
    Future<int> loudestBand() async {
      AudioLevels? levels;
      await waitFor(() {
        native
            .getProperty('af-metadata/$analysisLabel')
            .then((raw) => levels = parseAudioLevels(raw));
        return levels != null;
      }, 'medições de áudio');
      final b = levels!.bandsDb;
      return b.indexOf(b.reduce(max));
    }

    int nearestBand(double hz) {
      final f = analysisFrequencies();
      int best = 0;
      for (int i = 1; i < f.length; i++) {
        if ((log(f[i] / hz)).abs() < (log(f[best] / hz)).abs()) best = i;
      }
      return best;
    }

    // Voltar ao leitor liga a medição sem interromper a música.
    final posBefore = player.state.position;
    await key(LogicalKeyboardKey.keyM); // EQ -> menu
    await key(LogicalKeyboardKey.keyM); // menu -> leitor
    expect(state.currentView, 'player');
    await waitFor(() => state.isPlaying == true, 'continua a tocar');
    await settle(600);
    expect(await native.getProperty('af'), contains('astats'));
    expect(player.state.position, greaterThan(posBefore));
    expect(playingName(), 'Alpha');

    // Alpha = 220 Hz; Echo (5.ª faixa) = 1100 Hz.
    expect(await loudestBand(), nearestBand(220));
    await shot('03c_espectro_alpha');

    // --- Biblioteca: navegar e tocar ---
    await key(LogicalKeyboardKey.keyM);
    expect(state.currentView, 'menu');
    await key(LogicalKeyboardKey.arrowDown);
    await key(LogicalKeyboardKey.enter);
    expect(state.currentView, 'library');
    await key(LogicalKeyboardKey.arrowDown, times: 2);
    await shot('04_biblioteca');
    await key(LogicalKeyboardKey.enter);
    await waitFor(() => playingName() == 'Charlie', 'tocar da biblioteca');
    expect(state.currentView, 'player');

    // Pesquisa: filtra e o teclado continua a funcionar depois.
    await key(LogicalKeyboardKey.keyM);
    await key(LogicalKeyboardKey.arrowDown);
    await key(LogicalKeyboardKey.enter);
    await tester.enterText(find.byType(EditableText), 'ech');
    await settle(200);
    expect(find.text('Echo'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    await key(LogicalKeyboardKey.escape); // sai da caixa de texto
    await key(LogicalKeyboardKey.enter);
    await waitFor(() => playingName() == 'Echo', 'tocar resultado da pesquisa');
    await settle(800);
    expect(await loudestBand(), nearestBand(1100));
    await shot('04b_espectro_echo');

    // --- Fila: começa na faixa atual ---
    await key(LogicalKeyboardKey.keyM);
    await key(LogicalKeyboardKey.arrowDown, times: 2);
    await key(LogicalKeyboardKey.enter);
    expect(state.currentView, 'queue');
    await shot('05_fila');
    await key(LogicalKeyboardKey.escape);

    // --- Jogos ---
    await key(LogicalKeyboardKey.arrowDown, times: 5);
    await key(LogicalKeyboardKey.enter);
    expect(state.currentView, 'game_menu');

    // Snake: dois toques rápidos não podem inverter a cobra.
    await key(LogicalKeyboardKey.enter);
    expect(state.currentView, 'snake');
    await key(LogicalKeyboardKey.space);
    expect(isPlayingSnake, isTrue);
    snakeTimer?.cancel(); // controlamos os passos manualmente
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    state.setState(() {}); // não altera nada; só força um frame
    await settle();
    expect(snakeDir, const Point(-1, 0));
    await key(LogicalKeyboardKey.space); // (re)inicia normalmente
    await settle(150);
    // Pausa sem reiniciar.
    await key(LogicalKeyboardKey.space);
    expect(isPlayingSnake, isFalse);
    expect(isSnakeGameOver, isFalse);
    final pausedBody = List.of(snakeBody);
    await shot('06_snake');
    await settle(600);
    expect(snakeBody, pausedBody, reason: 'pausado não mexe');
    await key(LogicalKeyboardKey.space);
    expect(isPlayingSnake, isTrue);
    expect(snakeBody.length, pausedBody.length, reason: 'retoma, não reinicia');
    // MENU a meio do jogo pára o timer.
    await key(LogicalKeyboardKey.keyM);
    expect(snakeTimer?.isActive ?? false, isFalse);
    await key(LogicalKeyboardKey.arrowDown, times: 5);
    await key(LogicalKeyboardKey.enter);

    // Tetris: pausa e retoma sem recomeçar.
    await key(LogicalKeyboardKey.arrowDown);
    await key(LogicalKeyboardKey.enter);
    expect(state.currentView, 'tetris');
    await key(LogicalKeyboardKey.space);
    await waitFor(() => tetrisPieceOffset.y >= 2, 'peça a cair');
    await key(LogicalKeyboardKey.space);
    expect(isPlayingTetris, isFalse);
    final pausedOffset = tetrisPieceOffset;
    await settle(1200);
    expect(tetrisPieceOffset, pausedOffset);
    await key(LogicalKeyboardKey.space);
    expect(isPlayingTetris, isTrue);
    await waitFor(
      () => tetrisPieceOffset.y > pausedOffset.y,
      'peça continua de onde estava',
    );
    await key(LogicalKeyboardKey.arrowDown, times: 3); // descida rápida
    await shot('07_tetris');
    await key(LogicalKeyboardKey.escape);
    expect(state.currentView, 'game_menu');
    expect(tetrisTimer?.isActive ?? false, isFalse);

    // Restantes jogos arrancam e desenham sem erros.
    for (final (index, view) in [
      (2, '2048'),
      (3, 'racing'),
      (4, 'flappy'),
      (5, 'frogger'),
    ]) {
      state.setState(() => state.selectedGameItem = index);
      await key(LogicalKeyboardKey.enter);
      expect(state.currentView, view);
      await key(LogicalKeyboardKey.space);
      await key(LogicalKeyboardKey.arrowLeft);
      await key(LogicalKeyboardKey.arrowUp);
      await settle(300);
      await shot('08_$view');
      await key(LogicalKeyboardKey.escape);
    }

    // --- Definições ---
    await key(LogicalKeyboardKey.escape);
    await key(LogicalKeyboardKey.arrowDown, times: 4);
    await key(LogicalKeyboardKey.enter);
    expect(state.currentView, 'settings');
    // O último item (GitHub) tem de ser alcançável com o D-pad.
    await key(LogicalKeyboardKey.arrowDown, times: 6);
    expect(state.selectedMenuItem, 5);
    await key(LogicalKeyboardKey.arrowUp, times: 5);
    await key(LogicalKeyboardKey.enter); // idioma -> EN
    expect(state.currentLang, 'en');
    expect(find.text('LANGUAGE: EN'), findsOneWidget);
    await key(LogicalKeyboardKey.arrowDown);
    await key(LogicalKeyboardKey.enter); // tema seguinte
    expect(state.currentThemeIndex, 1);
    await key(LogicalKeyboardKey.arrowDown);
    await key(LogicalKeyboardKey.enter); // estilo -> ondas
    expect(state.visualStyle, 'waves');
    await shot('09_definicoes');
    await key(LogicalKeyboardKey.arrowDown);
    await key(LogicalKeyboardKey.enter); // foco 15 min
    await key(LogicalKeyboardKey.escape);
    await key(LogicalKeyboardKey.arrowDown, times: 5);
    await key(LogicalKeyboardKey.enter); // jogos bloqueados
    expect(state.currentView, 'player');
    expect(find.textContaining('FOCUS ON!'), findsOneWidget);
    await shot('10_foco');
    await settle(2300);
    expect(find.textContaining('FOCUS ON!'), findsNothing);

    // Limpar dados pára a música e esvazia a biblioteca.
    await key(LogicalKeyboardKey.keyM);
    await key(LogicalKeyboardKey.arrowDown, times: 4);
    await key(LogicalKeyboardKey.enter);
    state.setState(() => state.selectedMenuItem = 4);
    await key(LogicalKeyboardKey.enter);
    await waitFor(() => !player.state.playing, 'parar a música');
    expect(state.libraryPaths, isEmpty);
    expect(find.text('NO TRACK'), findsOneWidget);
    await shot('11_limpo');

    // Persistência.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('retro_playlist'), isEmpty);
    expect(prefs.getString('retro_lang'), 'en');
  });
}
