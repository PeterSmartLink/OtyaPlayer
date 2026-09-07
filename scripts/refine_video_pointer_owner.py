from pathlib import Path

player_path = Path('lib/features/player/presentation/video_player_screen.dart')
text = player_path.read_text()

needle = '''  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isLocked) {
        setState(() => _controlsVisible = false);
      }
    });
  }
'''
replacement = needle + '''
  void _toggleControlsVisibility() {
    _hideTimer?.cancel();
    if (!mounted || _isLocked) return;
    if (_controlsVisible) {
      setState(() => _controlsVisible = false);
      return;
    }
    _resetHideTimer();
  }
'''
if needle not in text:
    raise SystemExit('reset-hide-timer block not found')
text = text.replace(needle, replacement, 1)
text = text.replace('            onTap: _resetHideTimer,\n            onSeek:', '            onTap: _toggleControlsVisibility,\n            onSeek:', 1)

old = '''              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _resetHideTimer,
                  child: VideoPlayerControlsOverlay(
'''
new = '''              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: VideoPlayerControlsOverlay(
'''
if old not in text:
    raise SystemExit('visible controls full-screen gesture wrapper not found')
text = text.replace(old, new, 1)
# Remove the two closing levels that belonged only to the deleted GestureDetector.
old_tail = '''                    onPip: _enterPip,
                  ),
                ),
              ),
            ),
'''
new_tail = '''                    onPip: _enterPip,
                  ),
              ),
            ),
'''
if old_tail not in text:
    raise SystemExit('controls wrapper tail not found')
text = text.replace(old_tail, new_tail, 1)

if 'onTap: _toggleControlsVisibility' not in text:
    raise SystemExit('video tap did not move to gesture owner')
player_path.write_text(text)

contract_path = Path('test/system_truth_contract_test.dart')
contract = contract_path.read_text()
contract = contract.replace("expect(player, contains('onTap: _resetHideTimer'));", "expect(player, contains('onTap: _toggleControlsVisibility'));", 1)
contract = contract.replace(
    "    expect(gestures, contains('onTap: widget.onTap'));\n",
    "    expect(gestures, contains('onTap: widget.onTap'));\n    expect(player, contains('void _toggleControlsVisibility()'));\n    expect(player, isNot(contains('behavior: HitTestBehavior.translucent,\\n                  onTap: _resetHideTimer')));\n",
    1,
)
contract_path.write_text(contract)

print('final video pointer ownership pass applied')
