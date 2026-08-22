import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff6f5f1),
      body: SafeArea(
        child: Column(
          children: [
            // Top Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Row(
                children: [
                  const Row(
                    children: [
                      Text(
                        'LA',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          letterSpacing: -1,
                          color: Color(0xff171817),
                        ),
                      ),
                      SizedBox(width: 5),
                      Text(
                        'FÁBRICA',
                        style: TextStyle(
                          fontWeight: FontWeight.w300,
                          fontSize: 24,
                          letterSpacing: -1,
                          color: Color(0xff171817),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xff171817).withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'PRODUCTION & DESIGN STUDIO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: Color(0xff171817),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xffe2e0d8)),

            // Hero Section
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        const Text(
                          'LA FÁBRICA ARCHIVE',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w800,
                            color: Color(0xff74756f),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Apparel Studio & Inventory Portal',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 46,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.5,
                            color: Color(0xff171817),
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Select your portal to enter design studio or inventory management.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xff6e706b),
                          ),
                        ),
                        const SizedBox(height: 54),

                        // Two Large Cards Grid
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth > 720;
                            return Flex(
                              direction: isWide ? Axis.horizontal : Axis.vertical,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Card 1 - Designer
                                Expanded(
                                  flex: isWide ? 1 : 0,
                                  child: _PortalCard(
                                    tag: 'STUDIO ACCESS',
                                    title: 'DESIGNER',
                                    description:
                                        'Create, manage and customize your apparel designs in the live atelier editor.',
                                    buttonText: 'Enter as Designer  →',
                                    accentColor: const Color(0xffd9ee57),
                                    onTap: () => Navigator.pushNamed(context, '/designer/login'),
                                  ),
                                ),
                                SizedBox(
                                  width: isWide ? 32 : 0,
                                  height: isWide ? 0 : 32,
                                ),
                                // Card 2 - Inventory
                                Expanded(
                                  flex: isWide ? 1 : 0,
                                  child: _PortalCard(
                                    tag: 'MANAGEMENT ACCESS',
                                    title: 'INVENTORY',
                                    description:
                                        'Manage stock, pricing and inventory for your apparel designs.',
                                    buttonText: 'Enter Inventory  →',
                                    accentColor: const Color(0xff171817),
                                    isDark: true,
                                    onTap: () => Navigator.pushNamed(context, '/inventory/login'),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Footer
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Text(
                '© LA FÁBRICA — APPAREL OS',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xffa2a39b),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalCard extends StatefulWidget {
  const _PortalCard({
    required this.tag,
    required this.title,
    required this.description,
    required this.buttonText,
    required this.accentColor,
    required this.onTap,
    this.isDark = false,
  });

  final String tag;
  final String title;
  final String description;
  final String buttonText;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isDark;

  @override
  State<_PortalCard> createState() => _PortalCardState();
}

class _PortalCardState extends State<_PortalCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cardBg = widget.isDark ? const Color(0xff171817) : Colors.white;
    final textColor = widget.isDark ? Colors.white : const Color(0xff171817);
    final descColor = widget.isDark ? const Color(0xffb5b7b0) : const Color(0xff6e706b);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.translationValues(0, _hovered ? -6 : 0, 0),
        padding: const EdgeInsets.all(44),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _hovered
                ? (widget.isDark ? const Color(0xffd9ee57) : const Color(0xff171817))
                : const Color(0xffe2e0d8),
            width: _hovered ? 2 : 1,
          ),
          boxShadow: [
            if (_hovered)
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.tag,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                    color: widget.isDark ? const Color(0xffd9ee57) : const Color(0xff74756f),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.description,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: descColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  foregroundColor: widget.accentColor.computeLuminance() > 0.4
                      ? Colors.black
                      : Colors.white,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  elevation: 0,
                ),
                onPressed: widget.onTap,
                child: Text(
                  widget.buttonText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
