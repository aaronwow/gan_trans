part of 'chat_screen.dart';

// ---------------- Widgets ----------------

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.expand_more, size: 18, color: cs.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}

class _IconPill extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconPill({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
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
      message: isContinuous
          ? 'Continuous mode — tap to switch to push-to-talk'
          : 'Push-to-talk — tap to switch to continuous',
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

class _MicBar extends StatelessWidget {
  final bool listening;
  final bool enabled;
  final bool continuous;
  final double level;
  final AnimationController pulse;
  final bool showGear;
  final VoidCallback? onGearTap;
  final VoidCallback? onPressStart;
  final VoidCallback? onPressEnd;
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
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = listening ? Colors.redAccent : cs.primary;
    final disabled = !enabled;
    final label = listening
        ? (continuous ? 'Listening — tap to stop' : 'Release to send')
        : (continuous ? 'Tap to start' : 'Hold to talk');
    final icon = listening ? Icons.graphic_eq : Icons.mic;

    final bar = AnimatedBuilder(
      animation: pulse,
      builder: (_, _) {
        final glow = listening ? (0.25 + pulse.value * 0.25) : 0.18;
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
                blurRadius: listening ? 22 : 14,
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
              if (showGear) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onGearTap,
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

    return GestureDetector(
      onTapDown: disabled || continuous ? null : (_) => onPressStart?.call(),
      onTapUp: disabled || continuous ? null : (_) => onPressEnd?.call(),
      onTapCancel: disabled || continuous ? null : () => onPressEnd?.call(),
      onTap: disabled || !continuous ? null : onTap,
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

/// Two-step provider -> model picker used in the config sheet. Filters
/// providers by [cap] and renders an "Off" option iff [allowOff].
class _ProviderModelPicker extends StatelessWidget {
  final Capability cap;
  final String? providerId;
  final String modelId;
  final bool allowOff;
  final ValueChanged<String?> onProvider;
  final ValueChanged<String> onModel;

  const _ProviderModelPicker({
    required this.cap,
    required this.providerId,
    required this.modelId,
    required this.allowOff,
    required this.onProvider,
    required this.onModel,
  });

  @override
  Widget build(BuildContext context) {
    final providers = providersFor(cap).toList();
    final selected = findProvider(providerId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: providerId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Provider',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            if (allowOff)
              const DropdownMenuItem<String?>(value: null, child: Text('Off')),
            for (final p in providers)
              DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
          ],
          onChanged: onProvider,
        ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          Builder(
            builder: (_) {
              final models = selected.modelsFor(cap).toList();
              final value = models.any((m) => m.id == modelId)
                  ? modelId
                  : (models.isEmpty ? null : models.first.id);
              return DropdownButtonFormField<String>(
                initialValue: value,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Model',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: models
                    .map(
                      (m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(m.label, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) onModel(v);
                },
              );
            },
          ),
        ],
      ],
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
              'Scene: $sceneName',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Hold the mic to talk, release to send.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
