import 'package:flutter/material.dart';
enum ApparelType { tshirt, hoodie, sweatshirt, tank, polo }
extension ApparelInfo on ApparelType {
  String get label => switch (this) { ApparelType.tshirt => 'T-Shirt', ApparelType.hoodie => 'Hoodie', ApparelType.sweatshirt => 'Sweatshirt', ApparelType.tank => 'Tank Top', ApparelType.polo => 'Polo Shirt' };
  IconData get icon => switch (this) { ApparelType.tshirt => Icons.checkroom_rounded, ApparelType.hoodie => Icons.dry_cleaning_rounded, ApparelType.sweatshirt => Icons.layers_outlined, ApparelType.tank => Icons.accessibility_new_rounded, ApparelType.polo => Icons.person_outline_rounded };
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
  });

  final String? id;
  final String name;
  final ApparelType type;
  Color color;
  final String edited;
  final int initialStock;
  final double unitPrice;
  final String? designData;
}
