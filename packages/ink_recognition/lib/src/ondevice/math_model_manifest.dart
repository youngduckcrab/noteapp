// lib/src/ondevice/math_model_manifest.dart — (internal) the on-device math
// model's files: downloaded on demand (never in the app bundle) from the
// project's Firebase Hosting, where CI publishes hosting/models/ next to the
// web build (.github/workflows/ci.yml 'Build and deploy web').
//
// Pix2Text MFR 1.5 (MIT, BreezeDeus — hosting/models/<version>/LICENSE and
// NOTICE), its encoder and decoder dynamically quantized to int8 per channel
// by this project, and the original tokenizer.json. A new model = a new
// [MathModelManifest.version] directory (old files stay cached by their
// URL) + new sizes and SHA-256 sums here + kOnDeviceMathEngineId.
import 'package:meta/meta.dart';

@immutable
final class MathModelFile {
  const MathModelFile({
    required this.name,
    required this.sha256,
    required this.bytes,
  });

  /// File name, both in the URL and on the device.
  final String name;

  /// Lowercase hex SHA-256 of the whole file.
  final String sha256;
  final int bytes;
}

@immutable
final class MathModelManifest {
  const MathModelManifest({
    required this.version,
    required this.baseUrl,
    required this.files,
  });

  /// The directory name, here and on the device.
  final String version;

  /// Ends with '/'; a file's URL is baseUrl + name.
  final String baseUrl;
  final List<MathModelFile> files;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.bytes);

  Uri urlOf(MathModelFile file) => Uri.parse('$baseUrl${file.name}');

  MathModelFile file(String name) => files.firstWhere((f) => f.name == name);
}

const String kMathModelEncoderFile = 'encoder_model.int8pc.onnx';
const String kMathModelDecoderFile = 'decoder_model.int8pc.onnx';
const String kMathModelTokenizerFile = 'tokenizer.json';

/// Where the model files are published (Firebase Hosting of this project).
const String kMathModelBaseUrl =
    'https://noteapp-3f44e.web.app/models/pix2text-mfr-1.5-int8pc/';

const MathModelManifest kMathModelManifest = MathModelManifest(
  version: 'pix2text-mfr-1.5-int8pc',
  baseUrl: kMathModelBaseUrl,
  files: [
    MathModelFile(
      name: kMathModelEncoderFile,
      sha256:
          'bb574fc15294f268d41c5f384bcd7e55f93be3c0df790d4991f9dea4fded5fa2',
      bytes: 23327303,
    ),
    MathModelFile(
      name: kMathModelDecoderFile,
      sha256:
          '43c3db7d96626da3ba8d9be2bff7ae159c8309c50934a3269daf075efb9e3b96',
      bytes: 8616786,
    ),
    MathModelFile(
      name: kMathModelTokenizerFile,
      sha256:
          '4ffbeb2143e6a38324bb6111b7a8109530d38a076a8439aa5777535f0a32758a',
      bytes: 113168,
    ),
  ],
);
