part of 'chat_screen.dart';

// ---------------- Widgets ----------------

class _ScenePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ScenePill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: '选择场景提示词',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: cs.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.expand_more, size: 18, color: cs.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguagePill extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _LanguagePill({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = enabled ? cs.primaryContainer : cs.surfaceContainerHighest;
    final fg = enabled ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    return Tooltip(
      message: '调整翻译语言',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: enabled ? cs.primary : cs.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.language, size: 16, color: fg),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: fg,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.edit_outlined, size: 13, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconPill extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconPill({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _RoutingToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool enabled;
  final bool interactive;
  final VoidCallback? onTap;

  const _RoutingToggle({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    this.interactive = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = enabled && interactive;
    final bg = active ? cs.primaryContainer : cs.surfaceContainerHighest;
    final fg = active ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    return Tooltip(
      message: !interactive
          ? '$tooltip 已由 Audio direct 暂停'
          : '$tooltip ${enabled ? "开启" : "关闭"}',
      child: InkWell(
        onTap: interactive ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: active ? cs.primary : cs.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeToggleButton extends StatelessWidget {
  final VoiceMode mode;
  final VoidCallback onTap;

  const _ModeToggleButton({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isContinuous = mode == VoiceMode.continuous;
    return Tooltip(
      message: isContinuous ? '连续监听模式，点击切换为按住说话' : '按住说话模式，点击切换为连续监听',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Icon(
            isContinuous ? Icons.all_inclusive : Icons.touch_app_outlined,
            color: cs.onSurfaceVariant,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// Segmented filter shown only in continuous mode: picks half- vs full-duplex.
class _DuplexFilter extends StatelessWidget {
  final bool fullDuplex;
  final ValueChanged<bool> onChanged;

  const _DuplexFilter({required this.fullDuplex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(
          value: false,
          icon: Icon(Icons.compare_arrows, size: 16),
          label: Text('Half-duplex'),
        ),
        ButtonSegment(
          value: true,
          icon: Icon(Icons.swap_horiz, size: 16),
          label: Text('Full-duplex'),
        ),
      ],
      selected: {fullDuplex},
      showSelectedIcon: false,
      onSelectionChanged: (set) => onChanged(set.first),
    );
  }
}

/// Vertical drag distance (logical pixels, upward) at which a hold-to-talk
/// press becomes "armed to cancel". Once armed, releasing discards the
/// recording instead of sending it.
const double _kMicCancelThreshold = 60.0;

class _MicBar extends StatefulWidget {
  final bool listening;
  final bool enabled;
  final bool continuous;
  final double level;
  final AnimationController pulse;
  final bool showGear;
  final VoidCallback? onGearTap;
  final VoidCallback? onPressStart;
  final VoidCallback? onPressEnd;
  final VoidCallback? onCancel;
  final ValueChanged<bool>? onCancelArmedChanged;
  final VoidCallback? onTap;

  const _MicBar({
    required this.listening,
    required this.enabled,
    required this.continuous,
    required this.level,
    required this.pulse,
    required this.showGear,
    this.onGearTap,
    this.onPressStart,
    this.onPressEnd,
    this.onCancel,
    this.onCancelArmedChanged,
    this.onTap,
  });

  @override
  State<_MicBar> createState() => _MicBarState();
}

class _MicBarState extends State<_MicBar> {
  Offset? _downGlobal;
  bool _armed = false;
  bool _pressed = false;

  void _setArmed(bool v) {
    if (_armed == v) return;
    _armed = v;
    widget.onCancelArmedChanged?.call(v);
  }

  void _resetPress() {
    _downGlobal = null;
    _pressed = false;
    _setArmed(false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = !widget.enabled;
    final base = _armed
        ? Colors.red.shade700
        : (widget.listening ? Colors.redAccent : cs.primary);
    final label = _armed
        ? '松开取消'
        : (widget.listening
              ? (widget.continuous ? '监听中，点击停止' : '松开发送')
              : (widget.continuous ? '点击开始' : '按住说话'));
    final icon = _armed
        ? Icons.delete_outline
        : (widget.listening ? Icons.graphic_eq : Icons.mic);

    final bar = AnimatedBuilder(
      animation: widget.pulse,
      builder: (_, _) {
        final glow = widget.listening
            ? (0.25 + widget.pulse.value * 0.25)
            : 0.18;
        return Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: disabled
                  ? [Colors.grey.shade400, Colors.grey.shade500]
                  : [base, base.withValues(alpha: 0.78)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: base.withValues(alpha: glow),
                blurRadius: widget.listening ? 22 : 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.showGear) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: widget.onGearTap,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.tune,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );

    if (disabled) return bar;

    if (widget.continuous) {
      // Continuous mode: a single tap toggles listening; no swipe-cancel.
      return GestureDetector(onTap: widget.onTap, child: bar);
    }

    // Push-to-talk mode: use a Listener so we own the pointer regardless of
    // gesture-arena competition with ancestor scrollables. Track Y delta to
    // detect a cancel-arming swipe upward.
    return Listener(
      onPointerDown: (e) {
        _downGlobal = e.position;
        _pressed = true;
        _setArmed(false);
        widget.onPressStart?.call();
      },
      onPointerMove: (e) {
        if (!_pressed || _downGlobal == null) return;
        final dy = _downGlobal!.dy - e.position.dy; // upward = positive
        _setArmed(dy >= _kMicCancelThreshold);
        if (_armed) setState(() {}); // refresh label/colour live
      },
      onPointerUp: (_) {
        if (!_pressed) return;
        final wasArmed = _armed;
        _resetPress();
        if (wasArmed) {
          widget.onCancel?.call();
        } else {
          widget.onPressEnd?.call();
        }
      },
      onPointerCancel: (_) {
        if (!_pressed) return;
        _resetPress();
        widget.onPressEnd?.call();
      },
      child: bar,
    );
  }
}

class _LevelMeter extends StatelessWidget {
  final double level; // 0..10
  final double threshold; // 0..10
  final bool speaking;

  const _LevelMeter({
    required this.level,
    required this.threshold,
    required this.speaking,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        final barW = (level / 10).clamp(0.0, 1.0) * w;
        final tX = (threshold / 10).clamp(0.0, 1.0) * w;
        return SizedBox(
          height: 10,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              Container(
                width: barW,
                decoration: BoxDecoration(
                  color: speaking ? cs.primary : cs.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              Positioned(
                left: tX - 1,
                top: -2,
                bottom: -2,
                child: Container(width: 2, color: cs.error),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String sceneName;

  const _EmptyState({required this.sceneName});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mic_none,
              size: 64,
              color: cs.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              '当前场景：$sceneName',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '按住麦克风开始说话，松开后发送。',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
