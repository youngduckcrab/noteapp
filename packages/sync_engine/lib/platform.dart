/// Platform adapters of sync_engine (07-sync 4.0, 4.10):
/// `ConnectivityPlusSignal`.
///
/// Not pure Dart: imports the connectivity_plus Flutter plugin. Only the app
/// shell imports it, when sync is wired in at M4 (contract 00-overview
/// 7.3.3).
///
/// Foundation step B7 (00-overview 7.6): empty frame. The exports are added
/// during concurrent development (07-sync 8).
library;
