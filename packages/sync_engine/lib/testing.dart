/// Test helpers of sync_engine (07-sync 4.11, contract 00-overview 7.2.20
/// v1.1): fake sync server, network, blob store, auth backend and local
/// store, `FakeLocalWrite`, `TestDevice` and `SyncTestHarness`.
///
/// Import from `test/` only (contract 7.1 rule 2). Pure Dart and web-safe,
/// like `sync_engine.dart`. It never imports `package:fake_async`,
/// `package:test`, `package:test_api`, `package:matcher` or
/// `package:flutter_test`: tests inject virtual time into the harness, and
/// convergence checks throw instead of using matchers.
/// `test/no_dart_io_test.dart` checks this.
///
/// Exports the 4.11 helpers (07-sync 4.0 table). `syncScenario` lives in
/// `test/scenarios/support/sync_scenario.dart` and is not exported.
library;

export 'src/testing/fake_auth_backend.dart';
export 'src/testing/fake_blob_store.dart';
export 'src/testing/fake_local_store.dart';
export 'src/testing/fake_network.dart';
export 'src/testing/fake_sync_backend.dart';
export 'src/testing/fake_sync_server.dart';
export 'src/testing/sync_test_harness.dart';
export 'src/testing/test_device.dart';
