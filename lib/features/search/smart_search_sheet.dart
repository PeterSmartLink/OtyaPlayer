import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/app_colors.dart';
import '../../core/models/media_item.dart';
import '../../core/models/playlist.dart';
import '../my_space/presentation/providers/my_space_provider.dart';
import '../player/presentation/mini_player.dart';
import '../player/presentation/queue_screen.dart';
import '../playlists/playlist_screen.dart';
import '../settings/settings_provider.dart';

class SmartSearchSheet extends ConsumerStatefulWidget {
  const SmartSearchSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: AppColors.cardOf(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => const FractionallySizedBox(
          heightFactor: .92,
          child: SmartSearchSheet(),
        ),
      );

  @override
  ConsumerState<SmartSearchSheet> createState() => _SmartSearchSheetState();
}

class _HelpHit {
  const _HelpHit(this.title, this.answer, this.keywords);
  final String title;
  final String answer;
  final List<String> keywords;
}

class _GroupHit {
  const _GroupHit({required this.type, required this.name, required this.items});
  final String type;
  final String name;
  final List<MediaItem> items;
}

class _SmartSearchSheetState extends ConsumerState<SmartSearchSheet> {
  static const _historyKey = 'otya_search_history';
  static const _historyLimit = 8;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  String _query = '';
  List<String> _recentSearches = const [];

  static const _help = <_HelpHit>[
    _HelpHit(
      'Add subtitles',
      'Open a video and use the CC control. Otya can select embedded subtitle tracks when they are available.',
      ['subtitle', 'subtitles', 'caption', 'captions', 'cc'],
    ),
    _HelpHit(
      'Media is missing',
      'Open Otya Settings and review Android media permissions, then refresh Video or Music. Local scanning never requires an account.',
      ['missing', 'scan', 'media', 'library', 'permission'],
    ),
    _HelpHit(
      'Send files',
      'Open Me → Send. Keep both devices on the same Wi-Fi or hotspot, then scan the sender QR code or open its local link.',
      ['transfer', 'send', 'receive', 'nearby', 'qr', 'computer'],
    ),
    _HelpHit(
      'Convert video to audio',
      'Open Me → Tools and choose Convert video to audio. Otya extracts the existing audio track on this device without uploading the file.',
      ['convert', 'converter', 'extract audio', 'm4a'],
    ),
    _HelpHit(
      'Private media',
      'Open Me → Private. Protected media stays in Otya app-private storage until you restore it.',
      ['private', 'vault', 'lock', 'hide media'],
    ),
    _HelpHit(
      'Downloads',
      'Playable files in Android Download/Downloads folders automatically belong to Video or Music after scanning. Me → Files → Downloads shows that subset.',
      ['download', 'downloads', 'downloaded'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_focusNode.requestFocus);
    unawaited(_loadSearchHistory());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _q => _query.trim().toLowerCase();

  Future<void> _loadSearchHistory() async {
    if (!ref.read(settingsProvider).searchHistory) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList(_historyKey) ?? const <String>[];
      final cleaned = history
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .take(_historyLimit)
          .toList(growable: false);
      if (mounted) setState(() => _recentSearches = cleaned);
    } catch (_) {}
  }

  Future<void> _rememberQuery(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty || !ref.read(settingsProvider).searchHistory) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final previous = prefs.getStringList(_historyKey) ?? const <String>[];
      final queryKey = query.toLowerCase();
      final updated = <String>[
        query,
        ...previous.where((entry) => entry.trim().toLowerCase() != queryKey),
      ].take(_historyLimit).toList(growable: false);
      await prefs.setStringList(_historyKey, updated);
      if (mounted) setState(() => _recentSearches = updated);
    } catch (_) {}
  }

  Future<void> _clearSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
    } catch (_) {}
    if (mounted) setState(() => _recentSearches = const []);
  }

  void _selectRecentSearch(String query) {
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _queryChanged(query);
    _focusNode.requestFocus();
  }

  List<MediaItem> _mediaMatches(List<MediaItem> items) {
    final q = _q;
    if (q.isEmpty) return const [];
    return items.where((item) {
      final file =
          item.filePath.replaceAll('\\', '/').split('/').last.toLowerCase();
      return item.title.toLowerCase().contains(q) ||
          (item.artist?.toLowerCase().contains(q) ?? false) ||
          (item.album?.toLowerCase().contains(q) ?? false) ||
          file.contains(q);
    }).take(24).toList(growable: false);
  }

  List<_GroupHit> _groupMatches(List<MediaItem> items) {
    final q = _q;
    if (q.isEmpty) return const [];
    final hits = <_GroupHit>[];

    void addGroups(
      String type,
      Iterable<MediaItem> source,
      String Function(MediaItem) key,
    ) {
      final grouped = <String, List<MediaItem>>{};
      for (final item in source) {
        final name = key(item).trim();
        if (name.isEmpty || name == '<unknown>') continue;
        grouped.putIfAbsent(name, () => <MediaItem>[]).add(item);
      }
      for (final entry in grouped.entries) {
        if (entry.key.toLowerCase().contains(q)) {
          hits.add(_GroupHit(type: type, name: entry.key, items: entry.value));
        }
      }
    }

    addGroups(
      'Album',
      items.where((item) => !item.isVideo),
      (item) => item.album ?? '',
    );
    addGroups(
      'Artist',
      items.where((item) => !item.isVideo),
      (item) => item.artist ?? '',
    );
    addGroups('Folder', items, (item) {
      final parts = item.filePath.replaceAll('\\', '/').split('/');
      return parts.length >= 2 ? parts[parts.length - 2] : 'Device';
    });

    hits.sort((a, b) {
      final aStarts = a.name.toLowerCase().startsWith(q) ? 0 : 1;
      final bStarts = b.name.toLowerCase().startsWith(q) ? 0 : 1;
      final priority = aStarts.compareTo(bStarts);
      return priority != 0
          ? priority
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return hits.take(12).toList(growable: false);
  }

  List<Playlist> _playlistMatches(List<Playlist> playlists) {
    final q = _q;
    if (q.isEmpty) return const [];
    return playlists
        .where((playlist) => playlist.name.toLowerCase().contains(q))
        .take(8)
        .toList(growable: false);
  }

  List<_HelpHit> _helpMatches() {
    final q = _q;
    if (q.isEmpty) return const [];
    return _help.where((entry) {
      if (entry.title.toLowerCase().contains(q)) return true;
      return entry.keywords
          .any((keyword) => q.contains(keyword) || keyword.contains(q));
    }).take(5).toList(growable: false);
  }

  void _queryChanged(String value) {
    setState(() => _query = value);
  }

  void _closeThen(VoidCallback action) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) action();
    });
  }

  void _rememberAndClose(VoidCallback action) {
    unawaited(_rememberQuery(_query));
    _closeThen(action);
  }

  void _openMedia(MediaItem item, List<MediaItem> library) {
    final queue = library
        .where((candidate) => candidate.isVideo == item.isVideo)
        .toList();
    final index = queue.indexWhere((candidate) => candidate.id == item.id);
    ref
        .read(queueProvider.notifier)
        .setQueue(queue, startIndex: index < 0 ? 0 : index);
    if (!item.isVideo) ref.read(miniPlayerItemProvider.notifier).state = item;
    _rememberAndClose(
      () => context.push(
        item.isVideo ? '/player/video' : '/player/audio',
        extra: item,
      ),
    );
  }

  void _openGroup(_GroupHit hit) {
    final type = hit.type;
    if (type == 'Album') {
      _rememberAndClose(
        () => context.push(
          '/music/album',
          extra: {'name': hit.name, 'items': hit.items},
        ),
      );
    } else if (type == 'Artist') {
      _rememberAndClose(
        () => context.push(
          '/music/artist',
          extra: {'name': hit.name, 'items': hit.items},
        ),
      );
    } else {
      final hasVideo = hit.items.any((item) => item.isVideo);
      final hasAudio = hit.items.any((item) => !item.isVideo);
      if (hasVideo && !hasAudio) {
        _rememberAndClose(
          () => context.push(
            '/video/folder',
            extra: {'name': hit.name, 'items': hit.items},
          ),
        );
      } else if (hasAudio && !hasVideo) {
        _rememberAndClose(
          () => context.push(
            '/music/folder',
            extra: {'name': hit.name, 'items': hit.items},
          ),
        );
      } else {
        final path = hit.items.first.filePath.replaceAll('\\', '/');
        final slash = path.lastIndexOf('/');
        _rememberAndClose(
          () => context.push(
            '/tools/folder-detail',
            extra: {
              'folderName': hit.name,
              'fullPath': slash > 0 ? path.substring(0, slash) : '/',
              'items': hit.items,
            },
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final library =
        ref.watch(mediaLibraryProvider).valueOrNull ?? const <MediaItem>[];
    final playlists = ref.watch(playlistsProvider);
    final historyEnabled =
        ref.watch(settingsProvider.select((s) => s.searchHistory));
    final media = _mediaMatches(library);
    final groups = _groupMatches(library);
    final playlistHits = _playlistMatches(playlists);
    final help = _helpMatches();
    final hasQuery = _q.isNotEmpty;
    final noResults = hasQuery &&
        media.isEmpty &&
        groups.isEmpty &&
        playlistHits.isEmpty &&
        help.isEmpty;

    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.borderOf(context),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => unawaited(_rememberQuery(_query)),
            onChanged: _queryChanged,
            decoration: InputDecoration(
              hintText: 'Search Otya',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: Theme.of(context).scaffoldBackgroundColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: !hasQuery
              ? _SearchStart(
                  recentSearches:
                      historyEnabled ? _recentSearches : const <String>[],
                  onSelectRecent: _selectRecentSearch,
                  onClearRecent: _clearSearchHistory,
                )
              : ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 30),
                  children: [
                    if (groups.isNotEmpty) ...[
                      _SectionLabel(
                        'Albums, artists & folders',
                        '${groups.length}',
                      ),
                      ...groups.map(
                        (hit) => ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.cardOf(context),
                            child: Icon(
                              hit.type == 'Album'
                                  ? Icons.album_rounded
                                  : hit.type == 'Artist'
                                      ? Icons.person_rounded
                                      : Icons.folder_rounded,
                              color: AppColors.accent,
                            ),
                          ),
                          title: Text(
                            hit.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${hit.type} · ${hit.items.length} item${hit.items.length == 1 ? '' : 's'}',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _openGroup(hit),
                        ),
                      ),
                    ],
                    if (playlistHits.isNotEmpty) ...[
                      _SectionLabel('Playlists', '${playlistHits.length}'),
                      ...playlistHits.map(
                        (playlist) => ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: const CircleAvatar(
                            child: Icon(Icons.queue_music_rounded),
                          ),
                          title: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${playlist.mediaIds.length} saved item${playlist.mediaIds.length == 1 ? '' : 's'}',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _rememberAndClose(
                            () => context.push('/playlist/${playlist.id}'),
                          ),
                        ),
                      ),
                    ],
                    if (media.isNotEmpty) ...[
                      _SectionLabel('On this phone', '${media.length}'),
                      ...media.map(
                        (item) => ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.cardOf(context),
                            child: Icon(
                              item.isVideo
                                  ? Icons.movie_outlined
                                  : Icons.music_note_rounded,
                              color: AppColors.accent,
                            ),
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            item.isVideo
                                ? '${item.formattedDuration} · ${item.formattedSize}'
                                : (item.artist?.trim().isNotEmpty == true
                                    ? item.artist!.trim()
                                    : item.formattedDuration),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.play_arrow_rounded),
                          onTap: () => _openMedia(item, library),
                        ),
                      ),
                    ],
                    if (help.isNotEmpty) ...[
                      _SectionLabel('Otya help', '${help.length}'),
                      ...help.map(
                        (entry) => Container(
                          margin: const EdgeInsets.only(bottom: 9),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            border:
                                Border.all(color: AppColors.borderOf(context)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                entry.answer,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (noResults) ...[
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.cardOf(context),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.borderOf(context)),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              color: AppColors.textSecondary,
                            ),
                            SizedBox(height: 9),
                            Text(
                              'No local matches',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Try another file name, artist, album, folder, playlist or Otya help topic.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.45,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _SearchStart extends StatelessWidget {
  const _SearchStart({
    required this.recentSearches,
    required this.onSelectRecent,
    required this.onClearRecent,
  });

  final List<String> recentSearches;
  final ValueChanged<String> onSelectRecent;
  final VoidCallback onClearRecent;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(28, 44, 28, 28),
        children: [
          const Icon(
            Icons.manage_search_rounded,
            size: 48,
            color: AppColors.accent,
          ),
          const SizedBox(height: 14),
          const Text(
            'Search Otya',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          const Text(
            'Search local songs, videos, albums, artists, folders, playlists and Otya help on this device. Search stays local and does not contact an online provider.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          if (recentSearches.isNotEmpty) ...[
            const SizedBox(height: 30),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'RECENT SEARCHES',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .6,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onClearRecent,
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: recentSearches
                  .map(
                    (query) => ActionChip(
                      avatar: const Icon(Icons.history_rounded, size: 17),
                      label: Text(query, overflow: TextOverflow.ellipsis),
                      onPressed: () => onSelectRecent(query),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title, this.detail);
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 13, 2, 7),
        child: Row(
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
            ),
            if (detail.isNotEmpty) ...[
              const Spacer(),
              Text(
                detail,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      );
}
