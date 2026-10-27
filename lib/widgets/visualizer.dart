import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../painters/custom_paints.dart';
import '../services/audio_utils.dart';

/// Visualizador do leitor (espectro ou onda).
///
/// Reage ao áudio real: o mpv mede 12 bandas de frequência (ver
/// `buildAudioFilter`) e cada barra do espectro é uma banda; a onda segue o
/// volume e o timbre. Se as medições não estiverem disponíveis, recorre a
/// uma animação simulada.
///
/// Só redesenha o [CustomPaint] — o resto do ecrã não é reconstruído. Anima
/// a ~30 fps enquanto há música e pára por completo quando está em pausa e a
/// animação já assentou, para não gerar frames (e gastar bateria) à toa.
/// Como só existe no ecrã do leitor, também não corre nos menus e jogos.
class RetroVisualizer extends StatefulWidget {
  final Player player;
  final String style; // 'spectrum' | 'waves'
  final String trackName;

  const RetroVisualizer({
    super.key,
    required this.player,
    required this.style,
    required this.trackName,
  });

  @override
  State<RetroVisualizer> createState() => _RetroVisualizerState();
}

class _RetroVisualizerState extends State<RetroVisualizer> {
  static const Duration _frameInterval = Duration(milliseconds: 33);

  final VisualizerModel _model = VisualizerModel(barCount: 12);
  final Random _random = Random();
  final Stopwatch _clock = Stopwatch()..start();
  Duration _lastTick = Duration.zero;
  Timer? _timer;
  StreamSubscription<bool>? _playingSub;

  // Últimas medições do mpv e quando chegaram.
  static const Duration _staleAfter = Duration(milliseconds: 800);
  AudioLevels? _levels;
  Duration _levelsAt = Duration.zero;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _start();
    _playingSub = widget.player.stream.playing.listen((playing) {
      if (playing) _start();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _playingSub?.cancel();
    _model.dispose();
    super.dispose();
  }

  void _start() {
    if (_timer != null) return;
    _lastTick = _clock.elapsed;
    _timer = Timer.periodic(_frameInterval, (_) => _tick(_clock.elapsed));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Em pausa, a animação "assenta" quando as barras caíram e a onda
  /// voltou à amplitude de repouso.
  bool get _isSettled =>
      _model.bars.every((b) => b < 0.01) &&
      (_model.amplitude - 0.05).abs() < 0.002 &&
      (_model.complexity - 0.02).abs() < 0.0005;

  void _tick(Duration elapsed) {
    // Normaliza o passo para 60 fps, compensando atrasos do timer.
    final frames = ((elapsed - _lastTick).inMicroseconds / 16667).clamp(
      0.0,
      4.0,
    );
    _lastTick = elapsed;
    if (frames == 0) return;

    final playing = widget.player.state.playing;
    if (playing) _pollLevels(elapsed);
    final levels = playing && elapsed - _levelsAt < _staleAfter
        ? _levels
        : null;

    if (!playing) {
      _settle(frames);
    } else if (levels != null) {
      _followAudio(levels, frames);
    } else {
      _simulate(frames);
    }
    _model.markChanged();
    if (!playing && _isSettled) _stop();
  }

  double _ease(double k, double frames) => 1 - pow(1 - k, frames).toDouble();

  /// Pede ao mpv os níveis mais recentes (sem bloquear a animação).
  void _pollLevels(Duration now) {
    final platform = widget.player.platform;
    if (_fetching || platform is! NativePlayer) return;
    _fetching = true;
    platform
        .getProperty('af-metadata/$analysisLabel', waitForInitialization: false)
        .then((raw) {
          final parsed = parseAudioLevels(raw);
          if (parsed != null) {
            _levels = parsed;
            _levelsAt = _clock.elapsed;
          }
        })
        .catchError((_) {})
        .whenComplete(() => _fetching = false);
  }

  /// Anima a partir do áudio real: cada barra é uma banda de frequência e a
  /// onda segue o volume (amplitude) e o timbre (graves vs agudos).
  void _followAudio(AudioLevels levels, double frames) {
    final bars = _model.bars;
    double weighted = 0, total = 0;
    for (int i = 0; i < bars.length; i++) {
      final target = bandLevelToBar(levels.bandsDb[i], i);
      // Sobe depressa, desce devagar (como um VU-meter).
      final k = target > bars[i] ? 0.6 : 0.18;
      bars[i] += (target - bars[i]) * _ease(k, frames);
      weighted += i * target;
      total += target;
    }

    final intensity = overallLevelToIntensity(levels.overallDb);
    final brightness = total > 0 ? weighted / total / (bars.length - 1) : 0.0;
    _model.phase -= (0.03 + intensity * 0.12) * frames;
    _model.amplitude +=
        (0.04 + intensity * 0.44 - _model.amplitude) * _ease(0.35, frames);
    _model.complexity +=
        (0.012 + brightness * 0.06 - _model.complexity) * _ease(0.15, frames);
  }

  /// Animação de recurso quando o mpv não fornece medições.
  void _simulate(double frames) {
    final posMs = widget.player.state.position.inMilliseconds;
    final rand = Random((posMs ~/ 150) + widget.trackName.hashCode);
    final targetAmp = 0.15 + rand.nextDouble() * 0.35;
    final targetComp = 0.015 + rand.nextDouble() * 0.045;
    _model.phase -= 0.08 * frames;
    _model.amplitude += (targetAmp - _model.amplitude) * _ease(0.2, frames);
    _model.complexity += (targetComp - _model.complexity) * _ease(0.1, frames);

    final bars = _model.bars;
    final time = posMs.toDouble();
    for (int i = 0; i < bars.length; i++) {
      final speed = 0.002 + (i / bars.length) * 0.015;
      final wave = (sin(time * speed) + cos(time * speed * 1.3)) / 2.0;
      final noise = _random.nextDouble() * (0.1 + i * 0.02);
      final target = wave.abs() * 0.85 + noise;
      bars[i] += (target - bars[i]) * _ease(0.25, frames);
    }
  }

  /// Em pausa: barras caem e a onda volta ao repouso.
  void _settle(double frames) {
    _model.phase -= 0.02 * frames;
    _model.amplitude += (0.05 - _model.amplitude) * _ease(0.1, frames);
    _model.complexity += (0.02 - _model.complexity) * _ease(0.1, frames);
    final bars = _model.bars;
    for (int i = 0; i < bars.length; i++) {
      bars[i] *= pow(0.8, frames).toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.style == 'spectrum'
        ? CustomPaint(
            size: const Size(120, 60),
            painter: SpectrumPainter(model: _model),
          )
        : CustomPaint(
            size: const Size(180, 60),
            painter: WaveformPainter(model: _model, color: Colors.black87),
          );
  }
}
