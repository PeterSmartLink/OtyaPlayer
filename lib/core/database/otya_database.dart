// lib/core/database/otya_database.dart
//
// Central Hive database for OTYA Player.
// Wraps every Hive.openBox() in try/catch — if a box is corrupted,
// it is deleted and re-created so the app never crashes on startup.


import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/media_item.dart';
import '../models/playlist.dart';
import '../models/vault_item.dart';
import 'duration_adapter.dart';
import 'hive_boxes.dart';

class OtyaDatabase {
  OtyaDatabase._();
  static final OtyaDatabase instance = OtyaDatabase._();

  // ── Box references ─────────────────────────────────────────────────────────

  Box<MediaItem>? _historyBox;
  Box<MediaItem>? _libraryBox;
  Box<Playlist>?  _playlistsBox;
  Box<int>?       _seekBox;       // mediaId → position in milliseconds
  Box<dynamic>?   _shelfBox;      // generic shelf cache
  Box<String>?    _lyricsBox;     // mediaId -> cached lyrics text
  Box<VaultItem>? _vaultBox;
  Box<bool>?      _favoritesBox;  // mediaId → isFavorite

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Opens all Hive boxes. Each box is wrapped in try/catch so a corrupted
  /// box is deleted and re-created rather than crashing the app.
  Future<void> init() async {
    await Hive.initFlutter();

    // Register adapters (idempotent — Hive ignores duplicate registrations).
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(MediaItemAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(PlaylistAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(VaultItemAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(DurationAdapter());

    _historyBox   = await _openBox<MediaItem>(HiveBoxes.history);
    _libraryBox   = await _openBox<MediaItem>(HiveBoxes.libraryCache);
    _playlistsBox = await _openBox<Playlist>(HiveBoxes.playlists);
    _seekBox      = await _openBox<int>(HiveBoxes.seekPositions);
    _shelfBox     = await _openBox<dynamic>(HiveBoxes.shelfCache);
    _vaultBox     = await _openBox<VaultItem>(HiveBoxes.vault);
    _lyricsBox    = await _openBox<String>(HiveBoxes.lyrics);
    _favoritesBox = await _openBox<bool>(HiveBoxes.favorites);

    await _migrateLegacyLibrarySeeds();

    debugPrint('[OtyaDB] All boxes opened.');
  }

  /// Opens a single Hive box, deleting and re-creating it if corrupted.
  Future<Box<T>> _openBox<T>(String name) async {
    try {
      return await Hive.openBox<T>(name);
    } catch (e, st) {
      debugPrint('[OtyaDB] Box "$name" corrupted ($e) — deleting and re-creating.');
      debugPrintStack(stackTrace: st);
      try {
        await Hive.deleteBoxFromDisk(name);
        return await Hive.openBox<T>(name);
      } catch (e2, st2) {
        debugPrint('[OtyaDB] Re-create of "$name" also failed: $e2');
        debugPrintStack(stackTrace: st2);
        rethrow;
      }
    }
  }

  /// Deletes all boxes from disk and re-initialises. Used as a last-resort
  /// recovery when [init] itself fails.
  Future<void> deleteAndReinit() async {
    try {
      await Hive.close();
      for (final name in [
        HiveBoxes.history,
        HiveBoxes.libraryCache,
        HiveBoxes.playlists,
        HiveBoxes.seekPositions,
        HiveBoxes.shelfCache,
        HiveBoxes.vault,
        HiveBoxes.favorites,
        HiveBoxes.lyrics,
      ]) {
        try {
          await Hive.deleteBoxFromDisk(name);
        } catch (_) {}
      }
    } catch (_) {}
    await init();
  }

  /// Moves the old cold-start entries out of playback history. Older builds
  /// used `seed_*` keys in the history box, which could make unplayed files
  /// appear in Recently Played. Genuine `play_*` entries remain untouched.
  Future<void> _migrateLegacyLibrarySeeds() async {
    final history = _historyBox;
    final library = _libraryBox;
    if (history == null || library == null) return;
    try {
      final seedKeys = history.keys
          .where((key) => key is String && key.startsWith('seed_'))
          .toList(growable: false);
      if (seedKeys.isEmpty) return;

      final migrated = <String, MediaItem>{};
      for (final key in seedKeys) {
        final item = history.get(key);
        if (item != null) migrated[item.id] = item;
      }
      if (migrated.isNotEmpty) await library.putAll(migrated);
      await history.deleteAll(seedKeys);
    } catch (e) {
      debugPrint('[OtyaDB] library-cache migration error: $e');
    }
  }

  // ── Playback history ───────────────────────────────────────────────────────

  /// Records a play event. Keeps the most recent 500 items.
  Future<void> recordPlay(MediaItem item) async {
    final box = _historyBox;
    if (box == null || !box.isOpen) return;
    try {
      // Remove existing entry for this item (dedup by id).
      final existing = box.values.where((i) => i.id == item.id).toList();
      for (final e in existing) {
        await e.delete();
      }
      // Add to front by using a timestamp key.
      await box.put('play_${DateTime.now().microsecondsSinceEpoch}', item);
      // Trim to 500 entries.
      if (box.length > 500) {
        final keys = box.keys.toList();
        for (var i = 0; i < box.length - 500; i++) {
          await box.delete(keys[i]);
        }
      }
    } catch (e) {
      debugPrint('[OtyaDB] recordPlay error: $e');
    }
  }

  /// Returns the most recently played items, newest first.
  List<MediaItem> getRecentlyPlayed({int limit = 50}) {
    final box = _historyBox;
    if (box == null || !box.isOpen) return [];
    try {
      final items = box.values.toList().reversed.toList();
      return items.take(limit).toList();
    } catch (e) {
      debugPrint('[OtyaDB] getRecentlyPlayed error: $e');
      return [];
    }
  }

  /// Returns the full playback history (newest first).
  List<MediaItem> getPlaybackHistory({int limit = 200}) =>
      getRecentlyPlayed(limit: limit);

  /// Clears all playback history.
  Future<void> clearPlaybackHistory() async {
    final box = _historyBox;
    if (box == null || !box.isOpen) return;
    try {
      await box.clear();
    } catch (e) {
      debugPrint('[OtyaDB] clearPlaybackHistory error: $e');
    }
  }

  // ── Recently added ─────────────────────────────────────────────────────────

  /// Returns items from [allItems] added within the last [days] days.
  List<MediaItem> getRecentlyAddedItems(
    List<MediaItem> allItems, {
    int days = 7,
  }) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return allItems
        .where((i) => i.addedAt.isAfter(cutoff))
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  // ── Playlists ──────────────────────────────────────────────────────────────

  List<Playlist> getAllPlaylists() {
    final box = _playlistsBox;
    if (box == null || !box.isOpen) return [];
    try {
      return box.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('[OtyaDB] getAllPlaylists error: $e');
      return [];
    }
  }

  Playlist? getPlaylist(String id) {
    final box = _playlistsBox;
    if (box == null || !box.isOpen) return null;
    try {
      return box.get(id);
    } catch (e) {
      debugPrint('[OtyaDB] getPlaylist error: $e');
      return null;
    }
  }

  Future<void> savePlaylist(Playlist playlist) async {
    final box = _playlistsBox;
    if (box == null || !box.isOpen) return;
    try {
      await box.put(playlist.id, playlist);
    } catch (e) {
      debugPrint('[OtyaDB] savePlaylist error: $e');
    }
  }

  Future<void> deletePlaylist(String id) async {
    final box = _playlistsBox;
    if (box == null || !box.isOpen) return;
    try {
      await box.delete(id);
    } catch (e) {
      debugPrint('[OtyaDB] deletePlaylist error: $e');
    }
  }

  Future<void> addToPlaylist(String playlistId, MediaItem item) async {
    final playlist = getPlaylist(playlistId);
    if (playlist == null) return;
    if (!playlist.mediaIds.contains(item.id)) {
      playlist.mediaIds = [...playlist.mediaIds, item.id];
      playlist.updatedAt = DateTime.now();
      await savePlaylist(playlist);
    }
  }

  // ── Seek positions ─────────────────────────────────────────────────────────

  Future<void> saveSeekPosition(String mediaId, Duration position) async {
    final box = _seekBox;
    if (box == null || !box.isOpen) return;
    try {
      await box.put(mediaId, position.inMilliseconds);
    } catch (e) {
      debugPrint('[OtyaDB] saveSeekPosition error: $e');
    }
  }

  Duration? getSeekPosition(String mediaId) {
    final box = _seekBox;
    if (box == null || !box.isOpen) return null;
    try {
      final ms = box.get(mediaId);
      return ms != null ? Duration(milliseconds: ms) : null;
    } catch (e) {
      debugPrint('[OtyaDB] getSeekPosition error: $e');
      return null;
    }
  }

  Future<void> clearAllSeekPositions() async {
    final box = _seekBox;
    if (box == null || !box.isOpen) return;
    try {
      await box.clear();
    } catch (e) {
      debugPrint('[OtyaDB] clearAllSeekPositions error: $e');
    }
  }

  // ── Vault ──────────────────────────────────────────────────────────────────

  Future<void> addToVault(VaultItem item) async {
    final box = _vaultBox;
    if (box == null || !box.isOpen) return;
    try {
      await box.put(item.mediaId, item);
    } catch (e) {
      debugPrint('[OtyaDB] addToVault error: $e');
    }
  }

  Future<void> removeFromVault(String mediaId) async {
    final box = _vaultBox;
    if (box == null || !box.isOpen) return;
    try {
      await box.delete(mediaId);
    } catch (e) {
      debugPrint('[OtyaDB] removeFromVault error: $e');
    }
  }

  VaultItem? getVaultItem(String mediaId) {
    final box = _vaultBox;
    if (box == null || !box.isOpen) return null;
    try {
      return box.get(mediaId);
    } catch (e) {
      debugPrint('[OtyaDB] getVaultItem error: $e');
      return null;
    }
  }

  bool isInVault(String mediaId) {
    final box = _vaultBox;
    if (box == null || !box.isOpen) return false;
    try {
      return box.containsKey(mediaId);
    } catch (e) {
      debugPrint('[OtyaDB] isInVault error: $e');
      return false;
    }
  }

  List<VaultItem> getAllVaultItems() {
    final box = _vaultBox;
    if (box == null || !box.isOpen) return [];
    try {
      return box.values.toList();
    } catch (e) {
      debugPrint('[OtyaDB] getAllVaultItems error: $e');
      return [];
    }
  }

  // ── Favorites ──────────────────────────────────────────────────────────────

  Future<void> setFavoriteFlag(String mediaId, bool isFavorite) async {
    final box = _favoritesBox;
    if (box == null || !box.isOpen) return;
    try {
      if (isFavorite) {
        await box.put(mediaId, true);
      } else {
        await box.delete(mediaId);
      }
    } catch (e) {
      debugPrint('[OtyaDB] setFavoriteFlag error: $e');
    }
  }

  bool getFavoriteFlag(String mediaId) {
    final box = _favoritesBox;
    if (box == null || !box.isOpen) return false;
    try {
      return box.get(mediaId) ?? false;
    } catch (e) {
      debugPrint('[OtyaDB] getFavoriteFlag error: $e');
      return false;
    }
  }

  List<MediaItem> getFavoriteItems(List<MediaItem> allItems) {
    final box = _favoritesBox;
    if (box == null || !box.isOpen) return [];
    try {
      final favoriteIds = box.keys.toSet();
      return allItems.where((i) => favoriteIds.contains(i.id)).toList();
    } catch (e) {
      debugPrint('[OtyaDB] getFavoriteItems error: $e');
      return [];
    }
  }

  // ── Shelf cache ────────────────────────────────────────────────────────────

  /// Caches a list of media IDs for a named shelf (e.g. 'cinema', 'street').
  Future<void> cacheShelf(String shelfName, List<String> ids) async {
    final box = _shelfBox;
    if (box == null || !box.isOpen) return;
    try {
      await box.put('shelf_$shelfName', ids);
    } catch (e) {
      debugPrint('[OtyaDB] cacheShelf error: $e');
    }
  }

  /// Returns the cached list of media IDs for a named shelf.
  List<String> getShelfCache(String shelfName) {
    final box = _shelfBox;
    if (box == null || !box.isOpen) return [];
    try {
      final raw = box.get('shelf_$shelfName');
      if (raw is List) return raw.cast<String>();
      return [];
    } catch (e) {
      debugPrint('[OtyaDB] getShelfCache error: $e');
      return [];
    }
  }

  /// Returns the last successful media scan for an immediate cold-start UI.
  /// Playback history is intentionally stored in a separate box.
  List<MediaItem> getLibrarySnapshot() {
    final box = _libraryBox;
    if (box == null || !box.isOpen) return [];
    try {
      return box.values.toList(growable: false);
    } catch (e) {
      debugPrint('[OtyaDB] getLibrarySnapshot error: $e');
      return [];
    }
  }

  /// Replaces the cold-start snapshot without clearing first, so an
  /// interrupted write cannot temporarily erase the last usable library.
  Future<void> replaceLibrarySnapshot(List<MediaItem> items) async {
    final box = _libraryBox;
    if (box == null || !box.isOpen) return;
    try {
      final next = <String, MediaItem>{for (final item in items) item.id: item};
      await box.putAll(next);
      final staleKeys = box.keys
          .where((key) => key is! String || !next.containsKey(key))
          .toList(growable: false);
      if (staleKeys.isNotEmpty) await box.deleteAll(staleKeys);
    } catch (e) {
      debugPrint('[OtyaDB] replaceLibrarySnapshot error: $e');
    }
  }

  // ── Lyrics cache ───────────────────────────────────────────────────────────

  Future<void> cacheLyrics(String mediaId, String lyrics) async {
    final box = _lyricsBox;
    if (box == null || !box.isOpen) return;
    try {
      await box.put(mediaId, lyrics);
    } catch (e) {
      debugPrint('[OtyaDB] cacheLyrics error: $e');
    }
  }

  String? getCachedLyrics(String mediaId) {
    final box = _lyricsBox;
    if (box == null || !box.isOpen) return null;
    try {
      return box.get(mediaId);
    } catch (e) {
      debugPrint('[OtyaDB] getCachedLyrics error: $e');
      return null;
    }
  }
}
