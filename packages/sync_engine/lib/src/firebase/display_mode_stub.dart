// Non-web platforms: never a standalone web app.

/// Whether the page runs as a web app added to the home screen
/// (`navigator.standalone` or `display-mode: standalone`).
bool isStandaloneDisplayMode() => false;
