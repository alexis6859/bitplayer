import 'dart:io';
import 'dart:math';

import 'package:bitplayer/games/games_main.dart';
import 'package:bitplayer/services/audio_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduz a semântica de `playlist-move` do mpv sobre uma lista.
void applyMpvMove(List<String> list, int from, int to) {
  final item = list[from];
  list.insert(to, item);
  list.removeAt(from < to ? from : from + 1);
}

List<List<int>> board(List<String> rows) => [
  for (final r in rows) [for (final c in r.split('')) c == '#' ? 1 : 0],
];

void main() {
  group('Tetris', () {
    test('limpa 3 linhas completas ao mesmo tempo', () {
      final b = board(['....', '#...', '####', '####', '####']);
      expect(clearFullTetrisLines(b), 3);
      expect(b, board(['....', '....', '....', '....', '#...']));
    });

    test('limpa 4 linhas (tetris)', () {
      final b = board(['.#..', '####', '####', '####', '####']);
      expect(clearFullTetrisLines(b), 4);
      expect(b, board(['....', '....', '....', '....', '.#..']));
    });

    test('limpa linhas não adjacentes e preserva a ordem', () {
      final b = board(['#...', '####', '.#..', '####', '..#.']);
      expect(clearFullTetrisLines(b), 2);
      expect(b, board(['....', '....', '#...', '.#..', '..#.']));
    });

    test('sem linhas completas não altera nada', () {
      final b = board(['#...', '.###']);
      expect(clearFullTetrisLines(b), 0);
      expect(b, board(['#...', '.###']));
    });

    test('pontuação por linhas', () {
      expect([0, 1, 2, 3, 4].map(tetrisLineScore), [0, 100, 300, 500, 800]);
    });

    test('tem as 7 peças clássicas com 4 blocos cada', () {
      expect(tetrisShapes.length, 7);
      for (final s in tetrisShapes) {
        expect(s.toSet().length, 4);
      }
    });
  });

  group('2048', () {
    test('junta pares sem fusões em cadeia', () {
      void check(List<int> input, List<int> line, int score) {
        final (res, gained) = slide2048Line(input);
        expect(res, line, reason: '$input');
        expect(gained, score, reason: '$input');
      }

      check([2, 2, 2, 2], [4, 4, 0, 0], 8);
      check([4, 4, 8, 0], [8, 8, 0, 0], 8);
      check([0, 2, 0, 2], [4, 0, 0, 0], 4);
      check([2, 4, 8, 16], [2, 4, 8, 16], 0);
    });
  });

  group('Playlist (mpv)', () {
    test('mpvMoveTarget converte posição final para semântica do mpv', () {
      for (final (from, to) in [(0, 3), (3, 0), (1, 2), (2, 1), (4, 4)]) {
        final list = ['a', 'b', 'c', 'd', 'e'];
        final expectedFinal = List.of(list);
        expectedFinal.insert(to, expectedFinal.removeAt(from));

        final mpv = List.of(list);
        applyMpvMove(mpv, from, mpvMoveTarget(from, to));
        expect(mpv, expectedFinal, reason: 'from=$from to=$to');
      }
    });

    test('computePlaylistMoves transforma qualquer ordem na pretendida', () {
      final rand = Random(42);
      for (int n = 0; n < 30; n++) {
        final current = [for (int i = 0; i < 25; i++) 't$i'];
        final target = List.of(current)..shuffle(rand);
        final live = List.of(current);
        for (final m in computePlaylistMoves(current, target)) {
          applyMpvMove(live, m.from, m.to);
        }
        expect(live, target);
      }
    });

    test('não gera movimentos se a ordem já é a pretendida', () {
      expect(computePlaylistMoves(['a', 'b'], ['a', 'b']), isEmpty);
    });
  });

  group('Equalizador', () {
    test('preset neutro limpa os filtros', () {
      expect(buildEqualizerFilter([0.5, 0.5, 0.5, 0.5, 0.5]), '');
    });

    test('preset com ganhos gera cadeia lavfi', () {
      final f = buildEqualizerFilter([1.0, 0.85, 0.55, 0.35, 0.4]);
      expect(f, startsWith('lavfi=['));
      expect(f, contains('equalizer=f=60:width_type=o:width=2:g=8.0'));
      expect(f, contains('volume=-4.0dB'));
      expect(f, endsWith(']'));
    });

    test('a força multiplica os ganhos', () {
      const bass = [1.0, 0.85, 0.55, 0.35, 0.4];
      expect(
        buildEqualizerFilter(bass, strength: 0.5),
        contains('f=60:width_type=o:width=2:g=4.0'),
      );
      expect(
        buildEqualizerFilter(bass, strength: 2.0),
        contains('f=60:width_type=o:width=2:g=16.0'),
      );
      expect(buildEqualizerFilter(bass, strength: 0.0), '');
    });
  });

  group('Análise de áudio', () {
    test('12 bandas logarítmicas de 40 Hz a 16 kHz', () {
      final f = analysisFrequencies();
      expect(f.length, analysisBandCount);
      expect(f.first, closeTo(40, 0.01));
      expect(f.last, closeTo(16000, 0.01));
      for (int i = 1; i < f.length; i++) {
        expect(f[i] / f[i - 1], closeTo(f[1] / f[0], 1e-9));
      }
    });

    test('filtro completo inclui EQ, análise e volta a estéreo', () {
      final af = buildAudioFilter(eqBands: [1.0, 0.5, 0.5, 0.5, 0.5]);
      expect(af, startsWith('@$analysisLabel:lavfi=['));
      expect(af, contains('equalizer=f=60'));
      expect('bandpass='.allMatches(af).length, analysisBandCount);
      expect(af, contains('amerge=inputs=${analysisBandCount + 1}'));
      expect(af, endsWith('pan=stereo|c0=c0|c1=c1]'));
      // Sem análise fica só o equalizador.
      expect(
        buildAudioFilter(
          eqBands: [0.5, 0.5, 0.5, 0.5, 0.5],
          withAnalysis: false,
        ),
        '',
      );
    });

    test('lê os níveis dos metadados do mpv', () {
      final entries = [
        '"lavfi.astats.1.RMS_level":"-20.0"',
        '"lavfi.astats.2.RMS_level":"-22.0"',
        for (int i = 0; i < analysisBandCount; i++)
          '"lavfi.astats.${i + 3}.RMS_level":"${i == 4 ? '-inf' : '-${30 + i}.5'}"',
      ];
      final levels = parseAudioLevels('{${entries.join(',')}}')!;
      expect(levels.overallDb, -21.0);
      expect(levels.bandsDb[0], -30.5);
      expect(levels.bandsDb[4], -120.0);
      expect(levels.bandsDb.length, analysisBandCount);
    });

    test('sem medições devolve null', () {
      expect(parseAudioLevels(''), isNull);
      expect(parseAudioLevels('{}'), isNull);
    });

    test('conversão para barras fica entre 0 e 1', () {
      expect(bandLevelToBar(-120, 0), 0);
      expect(bandLevelToBar(0, 11), 1);
      expect(bandLevelToBar(-30, 0), inInclusiveRange(0.3, 0.9));
      expect(overallLevelToIntensity(-120), 0);
      expect(overallLevelToIntensity(-10), 1);
    });
  });

  test(
    'scanAudioFiles encontra áudio recursivamente e ignora o resto',
    () async {
      final dir = await Directory.systemTemp.createTemp('bitplayer_scan');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/a.MP3').create();
      await Directory('${dir.path}/sub').create();
      await File('${dir.path}/sub/b.flac').create();
      await File('${dir.path}/sub/capa.jpg').create();
      final found = await scanAudioFiles(dir.path);
      expect(found.map((f) => f.split(Platform.pathSeparator).last).toSet(), {
        'a.MP3',
        'b.flac',
      });
    },
  );
}
