import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../core/api.dart';
import 'dialogs.dart';
import 'ui.dart';

/// Downloads protected documents through the API client before rendering locally.
class DocumentPreviewPage extends StatefulWidget {
  const DocumentPreviewPage({
    super.key,
    required this.url,
    required this.title,
  });
  final String url, title;
  @override
  State<DocumentPreviewPage> createState() => _DocumentPreviewPageState();
}

class _DocumentPreviewPageState extends State<DocumentPreviewPage> {
  Uint8List? bytes;
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await api.bytes(widget.url);
      if (mounted) {
        setState(() {
          bytes = result;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = errorText(e);
          loading = false;
        });
      }
    }
  }

  bool get pdf =>
      bytes != null &&
      bytes!.length >= 5 &&
      String.fromCharCodes(bytes!.take(5)) == '%PDF-';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'Open original',
          onPressed: () => openLink(context, api.uri(widget.url).toString()),
          icon: const Icon(Icons.open_in_new_outlined),
        ),
        if (bytes != null)
          IconButton(
            tooltip: 'Share file',
            onPressed: () => shareBytes(
              context,
              bytes!,
              pdf ? 'document.pdf' : 'document.png',
              pdf ? 'application/pdf' : 'image/png',
            ),
            icon: const Icon(Icons.ios_share_outlined),
          ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? ErrorState(message: error!, onRetry: _load)
        : pdf
        ? PdfViewer.data(bytes!, sourceName: widget.url)
        : InteractiveViewer(
            minScale: .5,
            maxScale: 5,
            child: Center(
              child: Image.memory(
                bytes!,
                errorBuilder: (_, _, _) => const EmptyState(
                  icon: Icons.insert_drive_file_outlined,
                  title: 'Preview unavailable',
                  message: 'Use Open original to view this file.',
                ),
              ),
            ),
          ),
  );
}
