// lib/src/ui/content/content_pane.dart — 05-library 6.1:
// Column[top bar (64), storage warning banner (L18), Expanded(ContentBody)].
// The selection bar replaces the top bar in L14.
import 'package:material_ui/material_ui.dart';

import '../../model/section.dart';
import '../top_bar/library_top_bar.dart';
import 'content_body.dart';

class ContentPane extends StatelessWidget {
  const ContentPane({super.key, required this.section});

  final LibrarySection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LibraryTopBar(section: section),
        const Divider(height: 1),
        Expanded(child: ContentBody(section: section)),
      ],
    );
  }
}
