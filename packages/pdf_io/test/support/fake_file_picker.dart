// A scripted file_picker platform (VM and browser tests of FilePickerPdfSource, 06-pdf 8 T6):
// FilePickerPlatform.instance = ScriptedFilePicker(...) answers pickFile with a queued
// PlatformFile, null (cancelled) or an error, and records the options it was called with.
import 'package:file_picker/file_picker.dart';

final class ScriptedFilePicker extends FilePickerPlatform {
  ScriptedFilePicker(this.answers);

  /// PlatformFile, null or an error (thrown) — one per pickFile call.
  final List<Object?> answers;
  final List<({FileType type, List<String>? allowedExtensions})> calls = [];

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls.add((type: type, allowedExtensions: allowedExtensions));
    final answer = answers.removeAt(0);
    if (answer == null) return null;
    if (answer is PlatformFile) return answer;
    Error.throwWithStackTrace(answer, StackTrace.current);
  }
}
