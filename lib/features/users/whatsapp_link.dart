import 'package:flutter/material.dart';

import '../../widgets/dialogs.dart';

/// WhatsApp chat link. A 10-digit number is treated as an Indian mobile.
String? whatsappUrl(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  var phone = digits;
  if (phone.length == 10) {
    phone = '91$phone';
  } else if (phone.length == 11 && phone.startsWith('0')) {
    phone = '91${phone.substring(1)}';
  }
  if (phone.length < 8 || phone.length > 15) return null;
  return 'https://wa.me/$phone';
}

class WhatsAppButton extends StatelessWidget {
  const WhatsAppButton(this.number, {super.key});
  final String number;

  @override
  Widget build(BuildContext context) {
    final url = whatsappUrl(number);
    if (url == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Open in WhatsApp',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: () => openLink(context, url),
      icon: const WhatsAppMark(),
    );
  }
}

class WhatsAppMark extends StatelessWidget {
  const WhatsAppMark({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _WhatsAppPainter()),
    );
  }
}

class _WhatsAppPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final green = Paint()..color = const Color(0xFF25D366);
    canvas.drawCircle(size.center(Offset.zero), size.width / 2, green);
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s);
    final bubble = Path()
      ..moveTo(12, 4.4)
      ..cubicTo(7.6, 4.4, 4.1, 7.7, 4.1, 11.8)
      ..cubicTo(4.1, 13.5, 4.7, 15.1, 5.7, 16.3)
      ..lineTo(4.8, 19.8)
      ..lineTo(8.5, 18.7)
      ..cubicTo(9.6, 19.2, 10.8, 19.4, 12, 19.4)
      ..cubicTo(16.4, 19.4, 19.9, 16.1, 19.9, 12)
      ..cubicTo(19.9, 7.8, 16.4, 4.4, 12, 4.4)
      ..close();
    canvas.drawPath(bubble, Paint()..color = Colors.white);
    final phone = Paint()
      ..color = const Color(0xFF25D366)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(9.2, 9.1)
        ..cubicTo(9.2, 9.1, 8.3, 10.1, 8.8, 11.1)
        ..cubicTo(9.5, 12.5, 11.3, 14.2, 12.7, 14.8)
        ..cubicTo(13.7, 15.2, 14.6, 14.3, 14.6, 14.3)
        ..moveTo(13.6, 13.3)
        ..lineTo(14.8, 14.5)
        ..cubicTo(15.5, 15.2, 15.2, 16.2, 14.3, 16.6)
        ..cubicTo(12.6, 17.4, 10.2, 15.6, 9.1, 13.4)
        ..cubicTo(8.2, 11.6, 8.4, 10.2, 9.2, 9.1),
      phone,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
