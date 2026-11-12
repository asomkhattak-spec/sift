import 'package:flutter/material.dart';

import '../../core/models/library_models.dart';
import '../../core/models/search_models.dart';
import '../../core/services/library_service.dart';
import '../../core/services/sift_scope.dart';
import '../../core/theme/sift_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/navigation.dart';
import '../../core/utils/text_utils.dart';
import '../../widgets/sift_ui.dart';

enum _LibraryTab { saved, notes, history }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => LibraryScreenState();
}

class LibraryScreenState extends State<LibraryScreen> {
  late final SiftServices _services;
  late final LibraryService _library;
  _LibraryTab _tab = _LibraryTab.saved;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _services = SiftScope.readServicesOf(context);
    _library = _services.library;
    _library.addListener(_changed);
  }

  @override
  void dispose() {
    _library.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _openUrl(String url, {String title = ''}) async {
    await openSiftUrl(context, url, title: title);
  }

  Future<void> _compose([Note? note]) async {
    final title = TextEditingController(text: note?.title ?? '');
    final body = TextEditingController(text: note?.body ?? '');
    final url = TextEditingController(text: note?.url ?? '');
    final result = await showSiftSheet<_NoteDraft>(
      context,
      builder: (_) => _NoteSheet(
        title: title,
        body: body,
        url: url,
        editing: note != null,
      ),
    );
    if (result != null) {
      if (note == null) {
        await _library.addNote(
          title: result.title,
          body: result.body,
          url: result.url,
        );
      } else {
        await _library.updateNote(
          note.copyWith(
            title: result.title,
            body: result.body,
            url: result.url,
            updatedAt: DateTime.now(),
          ),
        );
      }
      if (mounted) {
        showSiftToast(context, note == null ? 'Note added.' : 'Note updated.');
      }
    }
    title.dispose();
    body.dispose();
    url.dispose();
  }

  Future<bool> _confirmClear(String title, String body) async {
    final confirmed = await showSiftSheet<bool>(
      context,
      builder: (_) => _ConfirmSheet(title: title, body: body),
    );
    return confirmed ?? false;
  }

  Future<void> _clearSaved() async {
    final confirmed = await _confirmClear(
      'Clear saved pages?',
      'Sift will forget every page in this list. Your local index is not affected.',
    );
    if (confirmed) await _library.clearSaved();
  }

  Future<void> _clearNotes() async {
    final confirmed = await _confirmClear(
      'Clear all notes?',
      'Every note on this phone will be removed. This cannot be undone.',
    );
    if (confirmed) await _library.clearNotes();
  }

  Future<void> _clearHistory() async {
    final confirmed = await showSiftSheet<bool>(
      context,
      builder: (_) => const _ConfirmSheet(
        title: 'Clear search history?',
        body: 'Recent queries and opened pages will be removed from this phone.',
      ),
    );
    if (confirmed == true) await _library.clearHistory();
  }

  Future<void> _savedActions(SavedPage page) async {
    await showSiftSheet<void>(
      context,
      builder: (sheetContext) => _SavedActions(
        page: page,
        onOpen: () {
          Navigator.of(sheetContext).pop();
          _openUrl(page.url, title: page.title);
        },
        onRead: () async {
          Navigator.of(sheetContext).pop();
          await _library.markSavedRead(page.id, read: !page.read);
        },
        onRemove: () async {
          Navigator.of(sheetContext).pop();
          await _library.deleteSaved(page.id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final saved = _library.saved;
    final notes = _library.notes;
    final history = _library.history;
    final query = _filter.trim().toLowerCase();
    final filteredSaved = query.isEmpty
        ? saved
        : saved
            .where((page) =>
                page.title.toLowerCase().contains(query) ||
                page.url.toLowerCase().contains(query) ||
                page.snippet.toLowerCase().contains(query))
            .toList();
    final filteredNotes = query.isEmpty
        ? notes
        : notes
            .where((note) =>
                note.title.toLowerCase().contains(query) ||
                note.body.toLowerCase().contains(query))
            .toList();
    final filteredHistory = query.isEmpty
        ? history
        : history
            .where((entry) =>
                entry.query.toLowerCase().contains(query) ||
                (entry.title ?? '').toLowerCase().contains(query))
            .toList();

    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            SiftSpace.page,
            20,
            SiftSpace.page,
            36,
          ),
          children: [
            SiftPageTitle(
              kicker: 'YOUR READING DESK',
              title: 'Library',
              subtitle:
                  'Saved pages, notes, and recent activity. Everything here lives '
                  'on this phone; pages you save are never uploaded.',
              actions: [
                if (_tab == _LibraryTab.notes)
                  SiftIconButton(
                    icon: Icons.note_add_outlined,
                    tooltip: 'New note',
                    onPressed: _compose,
                  ),
                if (_tab == _LibraryTab.saved)
                  SiftIconButton(
                    icon: Icons.delete_sweep_outlined,
                    tooltip: 'Clear saved pages',
                    onPressed: saved.isEmpty ? null : _clearSaved,
                  ),
                if (_tab == _LibraryTab.notes)
                  SiftIconButton(
                    icon: Icons.delete_sweep_outlined,
                    tooltip: 'Clear notes',
                    onPressed: notes.isEmpty ? null : _clearNotes,
                  ),
                if (_tab == _LibraryTab.history)
                  SiftIconButton(
                    icon: Icons.delete_sweep_outlined,
                    tooltip: 'Clear history',
                    onPressed: history.isEmpty ? null : _clearHistory,
                  ),
              ],
              bottom: 17,
            ),
            TextField(
              onChanged: (value) => setState(() => _filter = value),
              decoration: const InputDecoration(
                hintText: 'Filter this desk',
                prefixIcon: Icon(Icons.filter_alt_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                SiftFilterTab(
                  label: 'Saved',
                  count: saved.length,
                  selected: _tab == _LibraryTab.saved,
                  onTap: () => setState(() => _tab = _LibraryTab.saved),
                ),
                SiftFilterTab(
                  label: 'Notes',
                  count: notes.length,
                  selected: _tab == _LibraryTab.notes,
                  onTap: () => setState(() => _tab = _LibraryTab.notes),
                ),
                SiftFilterTab(
                  label: 'History',
                  count: _services.settings.rememberActivity ? history.length : null,
                  selected: _tab == _LibraryTab.history,
                  onTap: () => setState(() => _tab = _LibraryTab.history),
                ),
              ],
            ),
            const SiftRule(),
            const SizedBox(height: 16),
            if (_tab == _LibraryTab.saved) ...[
              if (filteredSaved.isEmpty)
                SiftEmpty(
                  icon: Icons.bookmark_border_rounded,
                  title: saved.isEmpty ? 'Nothing saved yet' : 'No matches',
                  body: saved.isEmpty
                      ? 'Use the bookmark on any result or in the reader to keep a '
                          'page here. Saved pages survive a restart.'
                      : 'Try a shorter filter, or clear it to see the whole desk.',
                )
              else
                for (var i = 0; i < filteredSaved.length; i++) ...[
                  _SavedRow(
                    page: filteredSaved[i],
                    onTap: () {
                      _library.markSavedRead(filteredSaved[i].id);
                      _openUrl(
                        filteredSaved[i].url,
                        title: filteredSaved[i].title,
                      );
                    },
                    onMenu: () => _savedActions(filteredSaved[i]),
                  ),
                  if (i != filteredSaved.length - 1) const SiftRule(),
                ],
            ],
            if (_tab == _LibraryTab.notes) ...[
              if (filteredNotes.isEmpty)
                SiftEmpty(
                  icon: Icons.edit_note_outlined,
                  title: notes.isEmpty ? 'A quiet place to think' : 'No matches',
                  body: notes.isEmpty
                      ? 'Notes stay on this phone and can be indexed into My Search '
                          'so your own words are searchable too.'
                      : 'Try a shorter filter, or clear it to see every note.',
                  action: notes.isEmpty
                      ? SiftButton(
                          label: 'Write a note',
                          icon: Icons.add_rounded,
                          compact: true,
                          onPressed: _compose,
                        )
                      : null,
                )
              else
                for (var i = 0; i < filteredNotes.length; i++) ...[
                  _NoteRow(
                    note: filteredNotes[i],
                    onTap: () => _compose(filteredNotes[i]),
                    onOpenLink: filteredNotes[i].url == null
                        ? null
                        : () => _openUrl(
                              filteredNotes[i].url!,
                              title: filteredNotes[i].title,
                            ),
                    onDelete: () => _library.deleteNote(filteredNotes[i].id),
                  ),
                  if (i != filteredNotes.length - 1) const SiftRule(),
                ],
            ],
            if (_tab == _LibraryTab.history) ...[
              if (!_services.settings.rememberActivity)
                SiftEmpty(
                  icon: Icons.visibility_off_outlined,
                  title: 'History is off',
                  body:
                      'Sift is not recording queries or visits. This is the default. '
                      'If you want a local record, enable remembered activity in Privacy.',
                )
              else if (filteredHistory.isEmpty)
                const SiftEmpty(
                  icon: Icons.history_rounded,
                  title: 'No recent activity',
                  body:
                      'Queries and pages you open will appear here. Clearing the '
                      'library removes them from this phone.',
                )
              else
                for (var i = 0; i < filteredHistory.length; i++) ...[
                  _HistoryRow(
                    entry: filteredHistory[i],
                    onQuery: () => startSiftSearch(context, filteredHistory[i].query),
                    onOpen: filteredHistory[i].openedUrl == null
                        ? null
                        : () => _openUrl(
                              filteredHistory[i].openedUrl!,
                              title: filteredHistory[i].title ?? '',
                            ),
                    onRemove: () =>
                        _library.removeHistoryEntry(filteredHistory[i].id),
                  ),
                  if (i != filteredHistory.length - 1) const SiftRule(),
                ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.page,
    required this.onTap,
    required this.onMenu,
  });

  final SavedPage page;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(
                page.read ? Icons.bookmark : Icons.bookmark_border,
                size: 16,
                color: page.read ? p.faint : p.moss,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: page.read ? p.muted : p.ink,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${domainOf(page.url)}  ·  saved ${relativeDate(page.savedAt)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: p.faint,
                          fontSize: 8.5,
                        ),
                  ),
                ],
              ),
            ),
            SiftIconButton(
              icon: Icons.more_horiz_rounded,
              tooltip: 'Saved page actions',
              onPressed: onMenu,
              size: 17,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    required this.onTap,
    required this.onOpenLink,
    required this.onDelete,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback? onOpenLink;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 38,
              color: p.clay.withOpacity(0.6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (note.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      truncateText(note.body, 160),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: p.muted,
                            height: 1.55,
                          ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        relativeDate(note.updatedAt).toUpperCase(),
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: p.faint,
                                  fontSize: 8,
                                ),
                      ),
                      if (onOpenLink != null) ...[
                        const SizedBox(width: 12),
                        SiftTextAction(
                          label: 'Open source',
                          icon: null,
                          onTap: onOpenLink,
                        ),
                      ],
                      const Spacer(),
                      SiftIconButton(
                        icon: Icons.close_rounded,
                        tooltip: 'Delete note',
                        onPressed: onDelete,
                        size: 13,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.onQuery,
    required this.onOpen,
    required this.onRemove,
  });

  final HistoryEntry entry;
  final VoidCallback onQuery;
  final VoidCallback? onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 14, color: p.faint),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: onOpen ?? onQuery,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title == null || entry.title!.isEmpty
                        ? entry.query
                        : entry.title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.query}  ·  ${relativeDate(entry.at)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: p.faint,
                          fontSize: 8.5,
                        ),
                  ),
                ],
              ),
            ),
          ),
          if (onOpen != null)
            SiftIconButton(
              icon: Icons.open_in_new_rounded,
              tooltip: 'Open page',
              onPressed: onOpen,
              size: 14,
            ),
          SiftIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Remove from history',
            onPressed: onRemove,
            size: 13,
          ),
        ],
      ),
    );
  }
}

class _SavedActions extends StatelessWidget {
  const _SavedActions({
    required this.page,
    required this.onOpen,
    required this.onRead,
    required this.onRemove,
  });

  final SavedPage page;
  final VoidCallback onOpen;
  final VoidCallback onRead;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SiftSheetTitle(
            title: 'Saved page',
            subtitle: 'This menu only changes what is stored on this phone.',
          ),
          _ActionTile(
            icon: Icons.open_in_new_rounded,
            label: 'Open page',
            onTap: onOpen,
          ),
          _ActionTile(
            icon: page.read
                ? Icons.mark_email_unread_outlined
                : Icons.mark_email_read_outlined,
            label: page.read ? 'Mark unread' : 'Mark read',
            onTap: onRead,
          ),
          _ActionTile(
            icon: Icons.link_rounded,
            label: 'Copy address',
            onTap: () {
              Navigator.of(context).pop();
              copyText(context, page.url, 'Address copied.');
            },
          ),
          const SiftRule(),
          _ActionTile(
            icon: Icons.bookmark_remove_outlined,
            label: 'Remove from saved',
            color: p.danger,
            onTap: onRemove,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SiftSpace.page, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color ?? p.muted),
            const SizedBox(width: 13),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: color ?? p.inkSoft,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteDraft {
  const _NoteDraft(this.title, this.body, this.url);

  final String title;
  final String body;
  final String? url;
}

class _NoteSheet extends StatelessWidget {
  const _NoteSheet({
    required this.title,
    required this.body,
    required this.url,
    required this.editing,
  });

  final TextEditingController title;
  final TextEditingController body;
  final TextEditingController url;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        SiftSpace.page,
        0,
        SiftSpace.page,
        MediaQuery.paddingOf(context).bottom + 22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SiftSheetTitle(
            title: editing ? 'Edit note' : 'New note',
            subtitle:
                'A note is plain text, stored locally. You can attach one source address.',
          ),
          TextField(
            controller: title,
            autofocus: !editing,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: body,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(hintText: 'Write it down'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'Source address (optional)',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Nothing is synced. Removing the app removes these notes unless you '
            'have exported them.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.faint,
                  height: 1.5,
                  fontSize: 11,
                ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SiftButton(
                  label: 'Cancel',
                  tone: SiftButtonTone.line,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SiftButton(
                  label: editing ? 'Save changes' : 'Save note',
                  icon: Icons.check_rounded,
                  onPressed: () {
                    final address = url.text.trim();
                    Navigator.of(context).pop(
                      _NoteDraft(
                        title.text.trim().isEmpty
                            ? 'Untitled note'
                            : title.text.trim(),
                        body.text.trim(),
                        address.isEmpty ? null : address,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SiftSpace.page,
        0,
        SiftSpace.page,
        MediaQuery.paddingOf(context).bottom + 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SiftSheetTitle(title: title, subtitle: body),
          Row(
            children: [
              Expanded(
                child: SiftButton(
                  label: 'Keep it',
                  tone: SiftButtonTone.line,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SiftButton(
                  label: 'Clear',
                  tone: SiftButtonTone.clay,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
