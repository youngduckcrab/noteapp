// lib/src/integration/overrides.dart — contract 00-overview 7.2.18, 05-library 4.3.
import 'package:flutter_riverpod/misc.dart' show Override;

/// Overrides the app shell adds for this package. Always empty: every LIBRARY
/// provider has a default, and the PDF slots are wired by the app shell's
/// FeatureWiringModule (contract 7.3.3).
List<Override> featureLibraryOverrides() => const <Override>[];
