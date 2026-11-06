// lib/src/testing_vm_factory.dart — (v2.1, m5-7/06-pdf 4.3.2, 6.18) the dart:io half of the
// VM test helpers: testing_vm_native.dart on the VM (a temp directory, file writes),
// testing_vm_stub.dart elsewhere (does nothing — the fakes are VM only). testing.dart only.
export 'testing_vm_stub.dart' if (dart.library.io) 'testing_vm_native.dart';
