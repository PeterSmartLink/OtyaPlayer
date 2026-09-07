from pathlib import Path

path = Path('lib/features/player/presentation/video_player_screen.dart')
text = path.read_text()

old_import = "import '../../together/presentation/nearby_together_live_surface.dart';\n"
new_import = old_import + "import '../../together/presentation/together_ambient_overlay.dart';\n"
if "together_ambient_overlay.dart" not in text:
    if old_import not in text:
        raise SystemExit('Together live-surface import anchor not found')
    text = text.replace(old_import, new_import, 1)

anchor = '''          if (_isLocked)
            VideoPlayerLockOverlay(
'''
insert = '''          if (!_isLocked)
            TogetherAmbientOverlay(
              controlsVisible: _controlsVisible,
              onOpenConversation: () => unawaited(_showActiveTogetherRoom()),
            ),
          if (_isLocked)
            VideoPlayerLockOverlay(
'''
if 'TogetherAmbientOverlay(' not in text:
    if anchor not in text:
        raise SystemExit('video overlay insertion anchor not found')
    text = text.replace(anchor, insert, 1)

path.write_text(text)
print('Integrated Together ambient live-message layer into the video compositor.')
