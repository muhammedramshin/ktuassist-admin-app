import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../theme/app_theme.dart';

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

void toast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: error ? context.tones.danger : Brand.yellow,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

/// Runs [task], shows [success] on completion or the API error message.
/// Returns true on success.
Future<bool> runAction(BuildContext context, Future<dynamic> Function() task, {String? success}) async {
  try {
    await task();
    if (context.mounted && success != null) toast(context, success);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, errorText(e), error: true);
    return false;
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        destructive ? Icons.delete_outline_rounded : Icons.help_outline_rounded,
        color: destructive ? context.tones.danger : context.colors.onSurface,
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: message == null ? null : Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: context.tones.danger, foregroundColor: Colors.white)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? message,
  String label = '',
  String? hint,
  String initial = '',
  bool required = true,
  int minLength = 1,
  int maxLines = 3,
  String confirmLabel = 'Save',
  bool destructive = false,
  TextInputType? keyboard,
}) {
  final controller = TextEditingController(text: initial);
  String? error;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null) ...[Text(message), const SizedBox(height: 14)],
              TextField(
                controller: controller,
                autofocus: true,
                minLines: maxLines > 1 ? 2 : 1,
                maxLines: maxLines,
                keyboardType: keyboard,
                decoration: InputDecoration(labelText: label.isEmpty ? null : label, hintText: hint, errorText: error),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: context.tones.danger, foregroundColor: Colors.white)
                : null,
            onPressed: () {
              final value = controller.text.trim();
              if (required && value.length < minLength) {
                setState(() => error = minLength > 1 ? 'Enter at least $minLength characters' : 'Required');
                return;
              }
              Navigator.pop(context, value);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}

class SheetOption<T> {
  const SheetOption(this.value, this.label, {this.icon, this.subtitle, this.destructive = false});
  final T value;
  final String label;
  final IconData? icon;
  final String? subtitle;
  final bool destructive;
}

Future<T?> pickOption<T>(BuildContext context, {String? title, required List<SheetOption<T>> options}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Text(title, style: context.text.titleLarge),
                ),
              ...options.map(
                (o) => ListTile(
                  leading: o.icon == null
                      ? null
                      : Icon(o.icon, color: o.destructive ? context.tones.danger : null),
                  title: Text(o.label, style: o.destructive ? TextStyle(color: context.tones.danger) : null),
                  subtitle: o.subtitle == null ? null : Text(o.subtitle!),
                  onTap: () => Navigator.pop(context, o.value),
                ),
              ),
            ],
          ),
        ),
      ),
    );

Future<void> openLink(BuildContext context, String? url) async {
  if (url == null || url.trim().isEmpty) return;
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) toast(context, 'Could not open the link.', error: true);
  }
}

Future<void> copyText(BuildContext context, String text, [String message = 'Copied to clipboard']) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, message);
}

Future<void> shareBytes(BuildContext context, Uint8List bytes, String fileName, String mime) async {
  try {
    await SharePlus.instance.share(
      ShareParams(files: [XFile.fromData(bytes, mimeType: mime, name: fileName)], fileNameOverrides: [fileName]),
    );
  } catch (e) {
    if (context.mounted) toast(context, 'Could not share the file.', error: true);
  }
}

Future<void> shareCsv(BuildContext context, String csv, String fileName) =>
    shareBytes(context, Uint8List.fromList(utf8.encode(csv)), fileName, 'text/csv');

/// Full-screen image preview with pinch to zoom.
Future<void> showImagePreview(BuildContext context, {String? url, Uint8List? bytes, String? title, VoidCallback? onShare}) =>
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: bytes != null
                      ? Image.memory(bytes)
                      : Image.network(
                          url!,
                          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
                        ),
                ),
              ),
            ),
            SafeArea(
              child: Row(
                children: [
                  IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(title ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  if (onShare != null)
                    IconButton(color: Colors.white, icon: const Icon(Icons.ios_share_rounded), onPressed: onShare),
                ],
              ),
            ),
          ],
        ),
      ),
    );
