import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

const Set<String> audioExtensions = {
  '.mp3',
  '.wav',
  '.flac',
  '.m4a',
  '.aac',
  '.ogg',
  '.opus',
};

/// Procura recursivamente ficheiros de áudio em [dirPath], ignorando pastas
/// sem permissões de leitura.
Future<List<String>> scanAudioFiles(String dirPath) async {
  final List<String> audioFiles = [];
  try {
    await for (final entity in Directory(
      dirPath,
    ).list(recursive: true).handleError((_) {})) {
      if (entity is File &&
          audioExtensions.contains(p.extension(entity.path).toLowerCase())) {
        audioFiles.add(entity.path);
      }
    }
  } catch (_) {
    // Pasta inacessível: devolve o que foi encontrado até aqui.
  }
  return audioFiles;
}

/// Converte uma posição final (semântica de List.insert após removeAt) no
/// índice esperado pelo comando `playlist-move` do mpv, que coloca o item
/// ANTES do elemento que está em `to`.
int mpvMoveTarget(int from, int finalIndex) =>
    finalIndex > from ? finalIndex + 1 : finalIndex;

class PlaylistMove {
  final int from;
  final int to;
  const PlaylistMove(this.from, this.to);

  @override
  String toString() => 'PlaylistMove($from -> $to)';
}

/// Calcula os `playlist-move` (semântica mpv) que transformam [current] em
/// [target]. As duas listas têm de ter os mesmos elementos.
List<PlaylistMove> computePlaylistMoves(
  List<String> current,
  List<String> target,
) {
  final live = List<String>.from(current);
  final moves = <PlaylistMove>[];
  for (int j = 0; j < target.length; j++) {
    final from = live.indexOf(target[j], j);
    if (from == -1 || from == j) continue;
    moves.add(PlaylistMove(from, mpvMoveTarget(from, j)));
    live.insert(j, live.removeAt(from));
  }
  return moves;
}

/// Frequências centrais (Hz) das 5 bandas mostradas no equalizador.
const List<int> equalizerFrequencies = [60, 230, 910, 3600, 14000];

/// Ganho máximo (dB) aplicado quando uma banda está a 0.0 ou 1.0 com a
/// força a 100%.
const double equalizerMaxGainDb = 8.0;

/// Limites e passo da "força" do equalizador (1.0 = 100%).
const double equalizerMinStrength = 0.0;
const double equalizerMaxStrength = 2.0;
const double equalizerStrengthStep = 0.25;

/// Filtros lavfi do equalizador para as [bands] (0.0–1.0, sendo 0.5 neutro),
/// com os ganhos multiplicados por [strength].
List<String> equalizerFilters(List<double> bands, {double strength = 1.0}) {
  final gains = [
    for (final b in bands) ((b - 0.5) * 2 * equalizerMaxGainDb * strength),
  ];
  if (gains.every((g) => g.abs() < 0.05)) return [];

  final filters = <String>[];
  // Pré-atenuação para não saturar quando há bandas reforçadas.
  final maxBoost = gains.reduce((a, b) => a > b ? a : b);
  if (maxBoost > 0) {
    filters.add('volume=${(-maxBoost / 2).toStringAsFixed(1)}dB');
  }
  for (int i = 0; i < gains.length && i < equalizerFrequencies.length; i++) {
    if (gains[i].abs() < 0.05) continue;
    filters.add(
      'equalizer=f=${equalizerFrequencies[i]}:width_type=o:width=2'
      ':g=${gains[i].toStringAsFixed(1)}',
    );
  }
  return filters;
}

/// Valor da propriedade `af` do mpv só com o equalizador (string vazia
/// quando não há nada a aplicar).
String buildEqualizerFilter(List<double> bands, {double strength = 1.0}) =>
    buildAudioFilter(eqBands: bands, eqStrength: strength, withAnalysis: false);

// --- ANÁLISE DE ÁUDIO PARA O VISUALIZADOR ---

/// Etiqueta do filtro de análise: os níveis lêem-se em `af-metadata/vis`.
const String analysisLabel = 'vis';

/// Uma banda por barra do espectro.
const int analysisBandCount = 12;

/// Frequências centrais das bandas, espaçadas logaritmicamente (40 Hz–16 kHz).
List<double> analysisFrequencies() => [
  for (int i = 0; i < analysisBandCount; i++)
    40 * pow(16000 / 40, i / (analysisBandCount - 1)).toDouble(),
];

/// Largura (oitavas) de cada banda, para cobrirem o espectro sem buracos.
double get _analysisBandWidth =>
    (log(16000 / 40) / ln2) / (analysisBandCount - 1);

/// Formato de trabalho: estéreo a 48 kHz (a taxa nativa da maioria das
/// placas de som). Uma taxa fixa garante que os filtros acima de 14 kHz
/// ficam estáveis em ficheiros de baixa taxa (ex.: 22 kHz) e que o `amerge`
/// consegue juntar os ramos (exige a mesma taxa em todos).
const String _audioFormat =
    'aformat=sample_fmts=fltp:channel_layouts=stereo:sample_rates=48000';

/// Gera o `af` completo: equalizador + análise por bandas.
///
/// O áudio é dividido: um ramo segue intacto para a saída; o outro passa por
/// [analysisBandCount] filtros passa-banda. Tudo é junto num único sinal
/// multicanal, medido com `astats` (que anexa o RMS de cada canal aos
/// metadados) e reduzido de novo a estéreo. A medição tem de ser feita
/// depois do `amerge`, porque o `amerge` descarta os metadados de entrada.
String buildAudioFilter({
  required List<double> eqBands,
  double eqStrength = 1.0,
  bool withAnalysis = true,
}) {
  final eq = equalizerFilters(eqBands, strength: eqStrength);
  if (!withAnalysis) {
    return eq.isEmpty ? '' : 'lavfi=[${[_audioFormat, ...eq].join(',')}]';
  }

  final n = analysisBandCount;
  final width = _analysisBandWidth.toStringAsFixed(2);
  final freqs = analysisFrequencies();
  final graph = StringBuffer()
    ..write([_audioFormat, ...eq, 'asplit=2[main][an]'].join(','))
    ..write(';[an]pan=mono|c0=0.5*c0+0.5*c1,asplit=$n')
    ..writeAll([for (int i = 0; i < n; i++) '[b$i]']);
  for (int i = 0; i < n; i++) {
    graph.write(
      ';[b$i]bandpass=f=${freqs[i].round()}:width_type=o:width=$width[m$i]',
    );
  }
  graph
    ..write(';[main]')
    ..writeAll([for (int i = 0; i < n; i++) '[m$i]'])
    ..write(
      'amerge=inputs=${n + 1},'
      'astats=metadata=1:reset=1:measure_overall=none'
      ':measure_perchannel=RMS_level,'
      'pan=stereo|c0=c0|c1=c1',
    );
  return '@$analysisLabel:lavfi=[$graph]';
}

/// Níveis medidos num instante (em dB; silêncio = -120).
class AudioLevels {
  final double overallDb;
  final List<double> bandsDb;
  const AudioLevels(this.overallDb, this.bandsDb);
}

final RegExp _rmsPattern = RegExp(
  r'astats\.(\d+)\.RMS_level["\s:=]*(-?inf|-?\d+(?:\.\d+)?)',
);

/// Lê o conteúdo de `af-metadata/vis`. Devolve `null` se ainda não houver
/// medições (ex.: filtro não suportado nesta build do mpv).
AudioLevels? parseAudioLevels(String metadata) {
  final values = <int, double>{};
  for (final m in _rmsPattern.allMatches(metadata)) {
    final v = m.group(2)!;
    values[int.parse(m.group(1)!)] = v.endsWith('inf')
        ? -120.0
        : max(-120.0, double.parse(v));
  }
  // Canais 1–2: saída estéreo; 3…: bandas.
  if (values.length < analysisBandCount + 2) return null;
  final overall = ((values[1] ?? -120) + (values[2] ?? -120)) / 2;
  return AudioLevels(overall, [
    for (int i = 0; i < analysisBandCount; i++) values[i + 3] ?? -120.0,
  ]);
}

/// Converte o nível de uma banda (dB) na altura da barra (0–1). As bandas
/// agudas recebem um pequeno reforço, porque a música tem naturalmente
/// menos energia nas frequências altas.
double bandLevelToBar(double db, int band) =>
    ((db + 58 + band * 1.5) / 46).clamp(0.0, 1.0);

/// Converte o nível global (dB) em intensidade (0–1).
double overallLevelToIntensity(double db) => ((db + 45) / 35).clamp(0.0, 1.0);
