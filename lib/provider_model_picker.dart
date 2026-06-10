import 'package:flutter/material.dart';

import 'catalog.dart';
import 'settings.dart';

class ProviderModelPicker extends StatelessWidget {
  final AppSettings settings;
  final Capability cap;
  final String? providerId;
  final String modelId;
  final bool allowOff;
  final bool enabled;
  final ValueChanged<String?> onProvider;
  final ValueChanged<String> onModel;
  final String providerLabel;
  final String modelLabel;
  final Iterable<ProviderSpec> Function(AppSettings settings)? providersBuilder;
  final bool Function(ModelSpec model)? modelFilter;

  const ProviderModelPicker({
    super.key,
    required this.settings,
    required this.cap,
    required this.providerId,
    required this.modelId,
    required this.allowOff,
    required this.onProvider,
    required this.onModel,
    this.enabled = true,
    this.providerLabel = 'Provider',
    this.modelLabel = 'Model',
    this.providersBuilder,
    this.modelFilter,
  });

  @override
  Widget build(BuildContext context) {
    final providers =
        (providersBuilder?.call(settings) ?? settings.providersFor(cap))
            .toList();
    final selected = settings.findProvider(providerId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: providerId,
          isExpanded: true,
          decoration: InputDecoration(labelText: providerLabel, isDense: true),
          items: [
            if (allowOff)
              const DropdownMenuItem<String?>(value: null, child: Text('关闭')),
            for (final provider in providers)
              DropdownMenuItem<String?>(
                value: provider.id,
                enabled: settings.hasCredentials(provider.id),
                child: _ProviderOption(
                  name: provider.name,
                  missingCredentials: !settings.hasCredentials(provider.id),
                ),
              ),
          ],
          onChanged: enabled ? onProvider : null,
        ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          _ModelDropdown(
            label: modelLabel,
            enabled: enabled && settings.hasCredentials(selected.id),
            models: selected
                .modelsFor(cap)
                .where(modelFilter ?? (_) => true)
                .toList(),
            modelId: modelId,
            onModel: onModel,
          ),
          if (!settings.hasCredentials(selected.id))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '缺少 ${selected.name} 凭证，请到 Settings 的 Providers 区域填写后再使用。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class ImageModelRoutePicker extends StatelessWidget {
  final AppSettings settings;
  final VoidCallback? onChanged;

  const ImageModelRoutePicker({
    super.key,
    required this.settings,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final imageProviders = settings.imageProviders().toList();
    final overrideOn = settings.imageProviderId != null;
    final canSend = settings.imageInputAvailable;
    final effectiveProvider = settings.findProvider(
      settings.effectiveImageProviderId,
    );
    final effectiveModel = effectiveProvider?.findModel(
      settings.effectiveImageModelId,
    );
    final routeLabel =
        '${effectiveProvider?.name ?? settings.effectiveImageProviderId ?? "未设置"} · ${effectiveModel?.label ?? settings.effectiveImageModelId}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('指定单独的图片模型'),
          subtitle: Text(
            overrideOn
                ? '图片翻译不跟随 Chat 模型。'
                : '关闭：跟随当前 Chat 模型 (${settings.chatModelId.isEmpty ? "未设置" : settings.chatModelId})',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          value: overrideOn,
          onChanged: imageProviders.isEmpty && !overrideOn
              ? null
              : (v) async {
                  if (v) {
                    if (imageProviders.isEmpty) return;
                    await settings.setImageProvider(imageProviders.first.id);
                  } else {
                    await settings.setImageProvider(null);
                  }
                  onChanged?.call();
                },
        ),
        if (overrideOn) ...[
          ProviderModelPicker(
            settings: settings,
            cap: Capability.chat,
            providerId: settings.imageProviderId,
            modelId: settings.imageModelId,
            allowOff: false,
            providerLabel: '图片 Provider',
            modelLabel: '图片 Model',
            providersBuilder: (_) => settings.imageProviders(),
            modelFilter: (model) => model.acceptsImage(),
            onProvider: (id) async {
              if (id == null) return;
              await settings.setImageProvider(id);
              onChanged?.call();
            },
            onModel: (id) async {
              await settings.setImageModel(id);
              onChanged?.call();
            },
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                canSend ? Icons.check_circle_outline : Icons.info_outline,
                size: 16,
                color: canSend ? cs.primary : cs.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  canSend
                      ? '当前使用 $routeLabel'
                      : (overrideOn
                            ? '请选择一个支持图片输入的模型。'
                            : '当前 Chat 模型不支持图片输入；开启单独图片模型后选择支持视觉的模型。'),
                  style: TextStyle(
                    color: canSend ? cs.onSurfaceVariant : cs.error,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProviderOption extends StatelessWidget {
  final String name;
  final bool missingCredentials;

  const _ProviderOption({required this.name, required this.missingCredentials});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: missingCredentials
                  ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                  : null,
            ),
          ),
        ),
        if (missingCredentials) ...[
          const SizedBox(width: 8),
          Text(
            'no API key',
            style: TextStyle(
              color: cs.error,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _ModelDropdown extends StatelessWidget {
  final String label;
  final bool enabled;
  final List<ModelSpec> models;
  final String modelId;
  final ValueChanged<String> onModel;

  const _ModelDropdown({
    required this.label,
    required this.enabled,
    required this.models,
    required this.modelId,
    required this.onModel,
  });

  @override
  Widget build(BuildContext context) {
    final value = models.any((model) => model.id == modelId)
        ? modelId
        : (models.isEmpty ? null : models.first.id);
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: models
          .map(
            (model) => DropdownMenuItem(
              value: model.id,
              child: Text(model.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: enabled
          ? (value) {
              if (value != null) onModel(value);
            }
          : null,
    );
  }
}
