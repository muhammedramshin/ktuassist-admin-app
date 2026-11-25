import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/json.dart';
import '../core/storage.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

class UploadResult {
  const UploadResult({required this.link, this.id, required this.name});
  final String link;
  final dynamic id;
  final String name;
}

enum _Mode { file, drive, url }

/// Upload sheet shared by every form.
/// * [register] = true stores the file through `POST addfile` (needed when the
///   API expects a file id, e.g. materials) and enables Google Drive links.
/// * [register] = false just returns a URL and allows pasting one.
Future<UploadResult?> showUploader(
  BuildContext context, {
  bool register = true,
  bool imagesOnly = false,
  String folder = 'books',
}) => showModalBottomSheet<UploadResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _UploaderSheet(register: register, imagesOnly: imagesOnly, folder: folder),
);

class _UploaderSheet extends StatefulWidget {
  const _UploaderSheet({required this.register, required this.imagesOnly, required this.folder});
  final bool register;
  final bool imagesOnly;
  final String folder;
  @override
  State<_UploaderSheet> createState() => _UploaderSheetState();
}

class _UploaderSheetState extends State<_UploaderSheet> {
  _Mode mode = _Mode.file;
  String? fileName;
  Uint8List? bytes;
  final title = TextEditingController();
  final link = TextEditingController();
  final driveName = TextEditingController();
  String driveType = 'Documents';
  bool busy = false;
  String? error;

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(type: widget.imagesOnly ? FileType.image : FileType.any);
    if (file == null) return;
    final data = await file.readAsBytes();
    setState(() {
      fileName = file.name;
      bytes = data;
      title.text = file.name;
      error = null;
    });
  }

  Future<void> _submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = switch (mode) {
        _Mode.file => await _uploadFile(),
        _Mode.drive => await _registerDrive(),
        _Mode.url => _pasted(),
      };
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      setState(() => error = errorText(e, 'Upload failed. Check storage permissions and try again.'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<UploadResult> _uploadFile() async {
    if (bytes == null) throw const FormatException('Choose a file first.');
    final name = title.text.trim().isEmpty ? fileName! : title.text.trim();
    final url = await CloudStorage.upload(
      '${widget.folder}/$name-${DateTime.now().millisecondsSinceEpoch}',
      bytes!,
      contentType: CloudStorage.mimeOf(fileName!),
    );
    if (!widget.register) return UploadResult(link: url, name: name);
    final res = await api.post('addfile', {
      'name': name,
      'link': url,
      'type': CloudStorage.categoryOf(fileName!),
      'location': 'firebase',
      'is_moved': 0,
      'is_verified': 0,
    });
    final file = asMap(unwrap(res));
    return UploadResult(link: str(file['link'], url), id: file['id'], name: name);
  }

  Future<UploadResult> _registerDrive() async {
    final match = RegExp(r'https://drive\.google\.com/file/d/([^/]+)/').firstMatch(link.text.trim());
    if (match == null) throw const FormatException('Invalid Google Drive link. It should look like https://drive.google.com/file/d/ID/view');
    if (driveName.text.trim().isEmpty) throw const FormatException('Enter a file name.');
    final res = await api.post('addfile', {
      'name': driveName.text.trim(),
      'link': link.text.trim(),
      'type': driveType,
      'location': 'gdrive',
      'is_moved': 0,
      'gdid': match.group(1),
      'is_verified': 0,
    });
    final file = asMap(unwrap(res));
    return UploadResult(link: link.text.trim(), id: file['id'], name: driveName.text.trim());
  }

  UploadResult _pasted() {
    final url = link.text.trim();
    if (!url.startsWith('http')) throw const FormatException('Enter a valid https:// URL.');
    return UploadResult(link: url, name: url.split('/').last);
  }

  @override
  Widget build(BuildContext context) {
    final modes = [
      const ButtonSegment(value: _Mode.file, icon: Icon(Icons.upload_rounded), label: Text('Upload')),
      if (widget.register)
        const ButtonSegment(value: _Mode.drive, icon: Icon(Icons.add_to_drive_rounded), label: Text('Drive link'))
      else
        const ButtonSegment(value: _Mode.url, icon: Icon(Icons.link_rounded), label: Text('Paste URL')),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.imagesOnly ? 'Add image' : 'Add file', style: context.text.titleLarge),
          const SizedBox(height: 16),
          SegmentedButton<_Mode>(
            segments: modes,
            selected: {mode},
            onSelectionChanged: (s) => setState(() {
              mode = s.first;
              error = null;
            }),
          ),
          const SizedBox(height: 16),
          if (mode == _Mode.file) ...[
            Panel(
              onTap: busy ? null : _pick,
              color: context.colors.surfaceContainerLow,
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Icon(fileName == null ? Icons.cloud_upload_outlined : Icons.insert_drive_file_rounded, size: 34),
                  const SizedBox(height: 8),
                  Text(fileName ?? 'Tap to choose a file', style: context.text.titleSmall, textAlign: TextAlign.center),
                  if (bytes != null)
                    Text('${(bytes!.length / 1024).toStringAsFixed(1)} KB', style: context.text.bodySmall),
                ],
              ),
            ),
            if (bytes != null && CloudStorage.mimeOf(fileName!).startsWith('image/'))
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(bytes!, height: 140, fit: BoxFit.cover),
              ),
            if (fileName != null) ...[
              const SizedBox(height: 12),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'File title')),
            ],
          ],
          if (mode == _Mode.drive) ...[
            TextField(controller: link, decoration: const InputDecoration(labelText: 'Google Drive link', hintText: 'https://drive.google.com/file/d/…/view')),
            const SizedBox(height: 12),
            TextField(controller: driveName, decoration: const InputDecoration(labelText: 'File name')),
            const SizedBox(height: 12),
            DropdownButtonFormField(
              initialValue: driveType,
              decoration: const InputDecoration(labelText: 'File type'),
              items: const ['Documents', 'Images', 'Videos'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => driveType = v ?? driveType),
            ),
          ],
          if (mode == _Mode.url)
            TextField(controller: link, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Image or file URL', hintText: 'https://')),
          if (error != null) ...[const SizedBox(height: 12), Banner2(error!, tone: Tone.danger)],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : _submit,
            icon: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded),
            label: Text(busy ? 'Uploading…' : 'Use this file'),
          ),
        ],
      ),
    );
  }
}
