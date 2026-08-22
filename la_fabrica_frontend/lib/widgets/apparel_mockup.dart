import 'package:flutter/material.dart';
import '../models/design_project.dart';

class ApparelMockup extends StatelessWidget {
  const ApparelMockup({
    super.key,
    required this.type,
    required this.color,
    this.child,
    this.large = false,
    this.showPrintAreaBorder = false,
  });

  final ApparelType type;
  final Color color;
  final Widget? child;
  final bool large;
  final bool showPrintAreaBorder;

  @override
  Widget build(BuildContext context) {
    final double width = large ? 480.0 : 180.0;
    final double height = large ? 540.0 : 202.5;

    // Printable area sizing relative to mockup
    final double printWidth = large ? 260.0 : 90.0;
    final double printHeight = large ? 300.0 : 100.0;
    final double printTop = large ? 130.0 : 45.0;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          CustomPaint(
            size: Size(width, height),
            painter: _ApparelVectorPainter(type: type, color: color),
          ),
          Positioned(
            top: printTop,
            child: Container(
              width: printWidth,
              height: printHeight,
              decoration: showPrintAreaBorder
                  ? BoxDecoration(
                      border: Border.all(
                        color: const Color(0x44d9ee57),
                        width: 1.5,
                      ),
                    )
                  : null,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApparelVectorPainter extends CustomPainter {
  _ApparelVectorPainter({required this.type, required this.color});

  final ApparelType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Paint fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final Paint outlinePaint = Paint()
      ..color = const Color(0xff181a18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.008
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Paint detailPaint = Paint()
      ..color = color.computeLuminance() > 0.5
          ? const Color(0x33000000)
          : const Color(0x33ffffff)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.005;

    final Paint shadowPaint = Paint()
      ..color = const Color(0x18000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final Path path = Path();
    final Path detailPath = Path();

    switch (type) {
      case ApparelType.tshirt:
        _drawTShirt(w, h, path, detailPath);
        break;
      case ApparelType.hoodie:
        _drawHoodie(w, h, path, detailPath);
        break;
      case ApparelType.sweatshirt:
        _drawSweatshirt(w, h, path, detailPath);
        break;
      case ApparelType.tank:
        _drawTank(w, h, path, detailPath);
        break;
      case ApparelType.polo:
        _drawPolo(w, h, path, detailPath);
        break;
    }

    // Draw soft shadow
    canvas.drawPath(path.shift(const Offset(0, 6)), shadowPaint);

    // Draw main body fill & outline
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, outlinePaint);

    // Draw seams/details
    canvas.drawPath(detailPath, detailPaint);
  }

  void _drawTShirt(double w, double h, Path p, Path d) {
    // Neck curve
    p.moveTo(w * 0.38, h * 0.08);
    p.quadraticBezierTo(w * 0.5, h * 0.16, w * 0.62, h * 0.08);
    // Right shoulder
    p.lineTo(w * 0.82, h * 0.14);
    // Right sleeve outer
    p.lineTo(w * 0.96, h * 0.32);
    // Right sleeve cuff
    p.lineTo(w * 0.82, h * 0.40);
    // Right armpit curve
    p.quadraticBezierTo(w * 0.76, h * 0.33, w * 0.74, h * 0.36);
    // Right side body
    p.lineTo(w * 0.74, h * 0.90);
    // Bottom hem
    p.quadraticBezierTo(w * 0.5, h * 0.92, w * 0.26, h * 0.90);
    // Left side body
    p.lineTo(w * 0.26, h * 0.36);
    // Left armpit curve
    p.quadraticBezierTo(w * 0.24, h * 0.33, w * 0.18, h * 0.40);
    // Left sleeve cuff
    p.lineTo(w * 0.04, h * 0.32);
    // Left sleeve outer
    p.lineTo(w * 0.18, h * 0.14);
    // Left shoulder
    p.close();

    // Collar detail
    d.moveTo(w * 0.38, h * 0.08);
    d.quadraticBezierTo(w * 0.5, h * 0.19, w * 0.62, h * 0.08);
    // Sleeve hem seams
    d.moveTo(w * 0.06, h * 0.34);
    d.lineTo(w * 0.18, h * 0.39);
    d.moveTo(w * 0.94, h * 0.34);
    d.lineTo(w * 0.82, h * 0.39);
  }

  void _drawHoodie(double w, double h, Path p, Path d) {
    // Hood top
    p.moveTo(w * 0.32, h * 0.10);
    p.cubicTo(w * 0.35, h * 0.01, w * 0.65, h * 0.01, w * 0.68, h * 0.10);
    // Right shoulder
    p.lineTo(w * 0.84, h * 0.16);
    // Right long sleeve outer
    p.lineTo(w * 0.95, h * 0.62);
    // Right cuff
    p.lineTo(w * 0.82, h * 0.64);
    // Right sleeve inner to body
    p.lineTo(w * 0.74, h * 0.38);
    p.lineTo(w * 0.74, h * 0.88);
    // Bottom rib hem
    p.lineTo(w * 0.26, h * 0.88);
    // Left side body
    p.lineTo(w * 0.26, h * 0.38);
    // Left sleeve inner
    p.lineTo(w * 0.18, h * 0.64);
    // Left cuff
    p.lineTo(w * 0.05, h * 0.62);
    // Left long sleeve outer
    p.lineTo(w * 0.16, h * 0.16);
    p.close();

    // Hood opening curve
    d.moveTo(w * 0.36, h * 0.10);
    d.quadraticBezierTo(w * 0.5, h * 0.22, w * 0.64, h * 0.10);
    // Kangaroo Pouch Pocket
    d.moveTo(w * 0.32, h * 0.62);
    d.lineTo(w * 0.38, h * 0.54);
    d.lineTo(w * 0.62, h * 0.54);
    d.lineTo(w * 0.68, h * 0.62);
    d.lineTo(w * 0.68, h * 0.86);
    d.lineTo(w * 0.32, h * 0.86);
    d.close();
  }

  void _drawSweatshirt(double w, double h, Path p, Path d) {
    // Rib collar curve
    p.moveTo(w * 0.36, h * 0.09);
    p.quadraticBezierTo(w * 0.5, h * 0.16, w * 0.64, h * 0.09);
    // Right shoulder
    p.lineTo(w * 0.84, h * 0.15);
    // Right long sleeve outer
    p.lineTo(w * 0.95, h * 0.60);
    // Right cuff
    p.lineTo(w * 0.83, h * 0.62);
    // Right inner armpit
    p.lineTo(w * 0.74, h * 0.38);
    p.lineTo(w * 0.74, h * 0.88);
    // Bottom waistband
    p.lineTo(w * 0.26, h * 0.88);
    p.lineTo(w * 0.26, h * 0.38);
    // Left inner armpit
    p.lineTo(w * 0.17, h * 0.62);
    // Left cuff
    p.lineTo(w * 0.05, h * 0.60);
    // Left long sleeve outer
    p.lineTo(w * 0.16, h * 0.15);
    p.close();

    // Ribbed collar detail
    d.moveTo(w * 0.36, h * 0.09);
    d.quadraticBezierTo(w * 0.5, h * 0.18, w * 0.64, h * 0.09);
    // V-stitch triangle at collar
    d.moveTo(w * 0.45, h * 0.15);
    d.lineTo(w * 0.50, h * 0.20);
    d.lineTo(w * 0.55, h * 0.15);
  }

  void _drawTank(double w, double h, Path p, Path d) {
    // Deep scoop neckline
    p.moveTo(w * 0.34, h * 0.08);
    p.quadraticBezierTo(w * 0.5, h * 0.24, w * 0.66, h * 0.08);
    // Right shoulder strap
    p.lineTo(w * 0.74, h * 0.08);
    // Right deep armhole curve
    p.quadraticBezierTo(w * 0.68, h * 0.28, w * 0.74, h * 0.40);
    // Right body side
    p.lineTo(w * 0.74, h * 0.90);
    // Curved hem
    p.quadraticBezierTo(w * 0.5, h * 0.93, w * 0.26, h * 0.90);
    // Left body side
    p.lineTo(w * 0.26, h * 0.40);
    // Left deep armhole curve
    p.quadraticBezierTo(w * 0.32, h * 0.28, w * 0.26, h * 0.08);
    p.close();

    // Neck trim detail
    d.moveTo(w * 0.34, h * 0.08);
    d.quadraticBezierTo(w * 0.5, h * 0.25, w * 0.66, h * 0.08);
  }

  void _drawPolo(double w, double h, Path p, Path d) {
    // Folded collar left wing
    p.moveTo(w * 0.36, h * 0.07);
    p.lineTo(w * 0.44, h * 0.17);
    p.lineTo(w * 0.50, h * 0.12);
    p.lineTo(w * 0.56, h * 0.17);
    p.lineTo(w * 0.64, h * 0.07);
    // Right shoulder
    p.lineTo(w * 0.82, h * 0.13);
    // Right sleeve
    p.lineTo(w * 0.94, h * 0.32);
    p.lineTo(w * 0.82, h * 0.39);
    p.lineTo(w * 0.74, h * 0.35);
    // Right side body
    p.lineTo(w * 0.74, h * 0.90);
    // Bottom hem
    p.lineTo(w * 0.26, h * 0.90);
    // Left side body
    p.lineTo(w * 0.26, h * 0.35);
    p.lineTo(w * 0.18, h * 0.39);
    p.lineTo(w * 0.06, h * 0.32);
    p.lineTo(w * 0.18, h * 0.13);
    p.close();

    // Placket line & 2 buttons
    d.moveTo(w * 0.50, h * 0.12);
    d.lineTo(w * 0.50, h * 0.30);
    // Button dots
    d.addOval(Rect.fromCircle(center: Offset(w * 0.50, h * 0.18), radius: w * 0.012));
    d.addOval(Rect.fromCircle(center: Offset(w * 0.50, h * 0.24), radius: w * 0.012));
  }

  @override
  bool shouldRepaint(covariant _ApparelVectorPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}
