/// Platform adapters of sync_engine (07-sync 4.0, 4.10):
/// `ConnectivityPlusSignal`.
///
/// Not pure Dart: imports the connectivity_plus Flutter plugin. Only the app
/// shell imports it, when sync is wired in at M4 (contract 00-overview
/// 7.3.3).
///
/// Exports `ConnectivityPlusSignal` (07-sync 4.0 table).
library;

export 'src/platform/connectivity_plus_signal.dart';
