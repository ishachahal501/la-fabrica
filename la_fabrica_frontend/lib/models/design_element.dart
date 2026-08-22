import 'package:flutter/material.dart';

enum ElementType { text, shape, image }
enum ShapeType { circle, square, rectangle, line }

class DesignElement {
  DesignElement({
    required this.id,
    required this.type,
    this.shapeType = ShapeType.rectangle,
    this.x = 100.0,
    this.y = 100.0,
    this.width = 120.0,
    this.height = 120.0,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.color = Colors.black,
    this.content = 'LA FÁBRICA',
    this.fontFamily = 'Sans',
    this.fontWeight = FontWeight.w900,
    this.textAlign = TextAlign.center,
    this.fontSize = 24.0,
    this.imageData,
    this.strokeWidth = 2.0,
  });

  final String id;
  ElementType type;
  ShapeType shapeType;
  double x;
  double y;
  double width;
  double height;
  double scale;
  double rotation; // in degrees (-180 to 180)
  Color color;
  String content;
  String fontFamily;
  FontWeight fontWeight;
  TextAlign textAlign;
  double fontSize;
  String? imageData; // base64 Data URI
  double strokeWidth;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'shapeType': shapeType.name,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'scale': scale,
      'rotation': rotation,
      'color': '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}',
      'content': content,
      'fontFamily': fontFamily,
      'fontWeight': FontWeight.values.indexOf(fontWeight),
      'textAlign': TextAlign.values.indexOf(textAlign),
      'fontSize': fontSize,
      if (imageData != null) 'imageData': imageData,
      'strokeWidth': strokeWidth,
    };
  }

  factory DesignElement.fromJson(Map<String, dynamic> json) {
    Color parsedColor = Colors.black;
    if (json['color'] != null) {
      String hex = json['color'].toString().replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      final val = int.tryParse(hex, radix: 16);
      if (val != null) parsedColor = Color(val);
    }

    FontWeight parsedWeight = FontWeight.w900;
    if (json['fontWeight'] != null) {
      final idx = json['fontWeight'] is int
          ? json['fontWeight']
          : int.tryParse(json['fontWeight'].toString()) ?? 8;
      if (idx >= 0 && idx < FontWeight.values.length) {
        parsedWeight = FontWeight.values[idx];
      }
    }

    TextAlign parsedAlign = TextAlign.center;
    if (json['textAlign'] != null) {
      final idx = json['textAlign'] is int
          ? json['textAlign']
          : int.tryParse(json['textAlign'].toString()) ?? 2;
      if (idx >= 0 && idx < TextAlign.values.length) {
        parsedAlign = TextAlign.values[idx];
      }
    }

    return DesignElement(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: ElementType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ElementType.text,
      ),
      shapeType: ShapeType.values.firstWhere(
        (e) => e.name == json['shapeType'],
        orElse: () => ShapeType.rectangle,
      ),
      x: (json['x'] as num?)?.toDouble() ?? 100.0,
      y: (json['y'] as num?)?.toDouble() ?? 100.0,
      width: (json['width'] as num?)?.toDouble() ?? 120.0,
      height: (json['height'] as num?)?.toDouble() ?? 120.0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      color: parsedColor,
      content: json['content']?.toString() ?? 'LA FÁBRICA',
      fontFamily: json['fontFamily']?.toString() ?? 'Sans',
      fontWeight: parsedWeight,
      textAlign: parsedAlign,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 24.0,
      imageData: json['imageData']?.toString(),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
    );
  }

  DesignElement clone() {
    return DesignElement.fromJson(toJson());
  }
}
