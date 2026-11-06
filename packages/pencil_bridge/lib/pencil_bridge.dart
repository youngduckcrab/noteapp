/// Apple Pencil double tap, squeeze, hover and barrel roll events.
///
/// Web-safe: no `dart:io`. Owned by INFRA (docs/plans/m5-7/01-infra.md 4.4,
/// contract 00-overview 7.2.13). The only entry point; it exports exactly
/// the contract names.
library;

export 'src/pencil_bridge_impl.dart' show PencilBridge;
export 'src/pencil_events.dart'
    show
        PencilEvent,
        PencilTap,
        PencilSqueeze,
        PencilHover,
        PencilRoll,
        PencilCapabilities;
