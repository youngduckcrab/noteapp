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
/// Foundation step B7 (00-overview 7.6): empty frame. The exports are added
/// during concurrent development (07-sync 8).
library;
