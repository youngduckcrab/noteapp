// Picks the golden comparator setup for the platform (03-ink 9.2).
export 'golden_tolerance_native.dart'
    if (dart.library.js_interop) 'golden_tolerance_browser.dart';
