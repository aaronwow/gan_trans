import 'package:flutter/material.dart';
import 'scenes.dart';
import 'settings.dart';

class ScenesScreen extends StatefulWidget {
  final AppSettings settings;
  const ScenesScreen({super.key, required this.settings});

  @override
  State<ScenesScreen> createState() => _ScenesScreenState();
}

class _ScenesScreenState extends State<ScenesScreen> {
  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Scenes')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Scene'),
        onPressed: () => _editScene(null),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: s.scenes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final scene = s.scenes[i];
          final active = scene.id == s.activeSceneId;
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade300,
                width: active ? 2 : 1,
              ),
            ),
            child: ListTile(
              title: Text(scene.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                scene.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              leading: Icon(active ? Icons.check_circle : Icons.chat_bubble_outline,
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editScene(scene),
                  ),
                  if (s.scenes.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await s.removeScene(scene.id);
                        setState(() {});
                      },
                    ),
                ],
              ),
              onTap: () async {
                await s.setActiveScene(scene.id);
                if (mounted) Navigator.pop(context);
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _editScene(Scene? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final promptCtrl = TextEditingController(text: existing?.prompt ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New Scene' : 'Edit Scene'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: promptCtrl,
                maxLines: 6,
                minLines: 3,
                decoration: const InputDecoration(
                  labelText: 'System prompt',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (result != true) return;
    final name = nameCtrl.text.trim();
    final prompt = promptCtrl.text.trim();
    if (name.isEmpty || prompt.isEmpty) return;
    if (existing == null) {
      await widget.settings.addScene(Scene(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        prompt: prompt,
      ));
    } else {
      existing.name = name;
      existing.prompt = prompt;
      await widget.settings.updateScene(existing);
    }
    setState(() {});
  }
}
