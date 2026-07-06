import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/image_pick_service.dart';
import 'confirm_dialog.dart';

class MachinePhoto extends StatefulWidget {
  final ApiClient api;
  final String machineId;
  final bool hasImage;
  final String? role;
  final VoidCallback onChanged;
  final ImagePickService? picker;

  const MachinePhoto({
    super.key,
    required this.api,
    required this.machineId,
    required this.hasImage,
    required this.role,
    required this.onChanged,
    this.picker,
  });

  @override
  State<MachinePhoto> createState() => _MachinePhotoState();
}

class _MachinePhotoState extends State<MachinePhoto> {
  static final Map<String, Uint8List> _cache = {};
  static const int _maxCacheEntries = 20;
  late final ImagePickService _picker = widget.picker ?? ImagePickService();
  bool _busy = false;

  bool get _isAdmin => widget.role == 'admin';

  Future<Uint8List> _loadImage() async {
    final cached = _cache[widget.machineId];
    if (cached != null) return cached;
    final bytes = await widget.api.getMachineImage(widget.machineId);
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[widget.machineId] = bytes;
    return bytes;
  }

  void _invalidate() => _cache.remove(widget.machineId);

  Future<void> _upload({required bool fromCamera}) async {
    setState(() => _busy = true);
    try {
      final picked = await _picker.pick(fromCamera: fromCamera);
      if (picked == null) return;
      await widget.api.setMachineImage(widget.machineId, picked.bytes, picked.mime);
      _invalidate();
      widget.onChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar la foto')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startUpload() async {
    // Mobile: choose camera or gallery. Web/desktop: both route to the file
    // picker (image_picker ignores the source there).
    final choice = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Hacer foto'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (!mounted) return;
    await _upload(fromCamera: choice);
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Quitar foto',
      message: '¿Quitar la foto de esta máquina?',
      confirmLabel: 'Quitar',
      cancelLabel: 'Cancelar',
    );
    if (!ok) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.deleteMachineImage(widget.machineId);
      _invalidate();
      widget.onChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo quitar la foto')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openFullscreen(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(child: Image.memory(bytes)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 160,
            width: double.infinity,
            child: widget.hasImage ? _thumbnail() : _placeholder(),
          ),
        ),
        if (_isAdmin) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.photo_camera),
                label: Text(widget.hasImage ? 'Cambiar foto' : 'Añadir foto'),
                onPressed: _busy ? null : _startUpload,
              ),
              if (widget.hasImage)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Quitar foto'),
                  onPressed: _busy ? null : _delete,
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _placeholder() => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.photo_camera_back_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.outline,
        ),
      );

  Widget _thumbnail() => FutureBuilder<Uint8List>(
        future: _loadImage(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return _placeholder();
          }
          final bytes = snap.data!;
          return GestureDetector(
            onTap: () => _openFullscreen(bytes),
            child: Image.memory(bytes, fit: BoxFit.cover),
          );
        },
      );
}
