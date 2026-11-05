// lib/src/model/folder_appearance_value.dart — 05-library 6.11 / 6.12.
import 'package:flutter/foundation.dart' show immutable;

/// Color and icon of a folder as the appearance dialog edits them.
@immutable
final class FolderAppearance {
  const FolderAppearance({this.colorArgb, this.icon});

  /// null = no color.
  final int? colorArgb;

  /// FolderIcons key, null = default.
  final String? icon;

  @override
  bool operator ==(Object other) =>
      other is FolderAppearance &&
      other.colorArgb == colorArgb &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(colorArgb, icon);

  @override
  String toString() => 'FolderAppearance(color: $colorArgb, icon: $icon)';
}

/// What the new folder dialog returns.
@immutable
final class NewFolderSpec {
  const NewFolderSpec({
    required this.name,
    this.appearance = const FolderAppearance(),
  });

  /// Already validated.
  final String name;
  final FolderAppearance appearance;

  @override
  bool operator ==(Object other) =>
      other is NewFolderSpec &&
      other.name == name &&
      other.appearance == appearance;

  @override
  int get hashCode => Object.hash(name, appearance);

  @override
  String toString() => 'NewFolderSpec("$name", $appearance)';
}
