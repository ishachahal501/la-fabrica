import 'package:flutter/material.dart';
enum ApparelType { tshirt, hoodie, sweatshirt, tank, polo }
extension ApparelInfo on ApparelType {
  String get label => switch (this) { ApparelType.tshirt => 'T-Shirt', ApparelType.hoodie => 'Hoodie', ApparelType.sweatshirt => 'Sweatshirt', ApparelType.tank => 'Tank Top', ApparelType.polo => 'Polo Shirt' };
  IconData get icon => switch (this) { ApparelType.tshirt => Icons.checkroom_rounded, ApparelType.hoodie => Icons.dry_cleaning_rounded, ApparelType.sweatshirt => Icons.layers_outlined, ApparelType.tank => Icons.accessibility_new_rounded, ApparelType.polo => Icons.person_outline_rounded };
}
class GarmentColorway {
  GarmentColorway({
    required this.id,
    required this.name,
    required this.color,
    this.isPrimary = false,
  });

  final String id;
  String name;
  Color color;
  bool isPrimary;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}',
    'isPrimary': isPrimary,
  };

  factory GarmentColorway.fromJson(Map<String, dynamic> json) {
    Color parsedColor = const Color(0xff181a18);
    if (json['color'] != null) {
      String hex = json['color'].toString().replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      final val = int.tryParse(hex, radix: 16);
      if (val != null) parsedColor = Color(val);
    }
    return GarmentColorway(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? 'Colorway',
      color: parsedColor,
      isPrimary: json['isPrimary'] == true,
    );
  }

  GarmentColorway clone() => GarmentColorway(
    id: id,
    name: name,
    color: color,
    isPrimary: isPrimary,
  );

  static List<GarmentColorway> defaultPresets() => [
    GarmentColorway(id: 'c_black', name: 'Onyx Black', color: const Color(0xff181a18), isPrimary: true),
    GarmentColorway(id: 'c_cream', name: 'Vintage Cream', color: const Color(0xfff3f0e6)),
    GarmentColorway(id: 'c_navy', name: 'Deep Navy', color: const Color(0xff1c2538)),
    GarmentColorway(id: 'c_heather', name: 'Heather Grey', color: const Color(0xff94979e)),
    GarmentColorway(id: 'c_forest', name: 'Forest Green', color: const Color(0xff1e3328)),
    GarmentColorway(id: 'c_terracotta', name: 'Terracotta', color: const Color(0xff8c4333)),
  ];
}

class DesignProject {
  DesignProject({
    this.id,
    required this.name,
    required this.type,
    required this.color,
    this.edited = 'Edited just now',
    this.initialStock = 50,
    this.unitPrice = 700,
    this.designData,
    this.colorways,
  });

  final String? id;
  final String name;
  final ApparelType type;
  Color color;
  final String edited;
  final int initialStock;
  final double unitPrice;
  final String? designData;
  List<GarmentColorway>? colorways;
}
