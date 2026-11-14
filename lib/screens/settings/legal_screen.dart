import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/sift_theme.dart';
import '../../widgets/sift_ui.dart';

/// Reads one of the bundled, plain-language legal documents. The files are
/// deliberately Markdown, not a web page, so they remain readable offline.
class LegalScreen extends StatelessWidget {
  const LegalScreen.asset({
    required this.title,
    required this.asset,
    super.key,
  });

  final String title;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: SiftIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19),
        ),
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(asset),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 1.4),
              ),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return SiftEmpty(
              icon: Icons.description_outlined,
              title: 'Document unavailable',
              body:
                  'The bundled text could not be read. Reinstall the app or report this.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              SiftSpace.page,
              8,
              SiftSpace.page,
              44,
            ),
            children: [
              Text(
                'Last updated with this release. This is the complete text.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: p.faint,
                      fontSize: 11.5,
                    ),
              ),
              const SizedBox(height: 18),
              ..._markdownBlocks(context, snapshot.data!),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _markdownBlocks(BuildContext context, String source) {
    final p = context.sift;
    final blocks = <Widget>[];
    final lines = source.split('\n');
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        blocks.add(const SizedBox(height: 10));
        continue;
      }
      if (line.startsWith('### ')) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 5),
            child: Text(
              line.substring(4),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: p.mossDeep,
                  ),
            ),
          ),
        );
        continue;
      }
      if (line.startsWith('## ')) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 6),
            child: Text(
              line.substring(3),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 20,
                  ),
            ),
          ),
        );
        continue;
      }
      if (line.startsWith('# ')) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 12),
            child: Text(
              line.substring(2),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 31,
                  ),
            ),
          ),
        );
        continue;
      }
      if (line.startsWith('- ') || line.startsWith('* ')) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 9),
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      color: p.clay,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    line.substring(2),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: p.inkSoft,
                          height: 1.65,
                        ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }
      blocks.add(
        Text(
          line,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: p.inkSoft,
                height: 1.7,
              ),
        ),
      );
    }
    return blocks;
  }
}
