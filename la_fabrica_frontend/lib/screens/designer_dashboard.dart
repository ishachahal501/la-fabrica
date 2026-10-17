import 'dart:convert';
import 'package:flutter/material.dart';

import '../models/design_project.dart';
import '../services/api_service.dart';
import '../widgets/apparel_mockup.dart';
import 'design_editor.dart';

class DesignerDashboard extends StatefulWidget {
  const DesignerDashboard({super.key});

  @override
  State<DesignerDashboard> createState() => _DesignerDashboardState();
}

class _DesignerDashboardState extends State<DesignerDashboard> {
  final ApiService _apiService = ApiService();
  String _userName = 'Designer';
  bool _isLoading = false;

  final List<DesignProject> _projects = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final name = await _apiService.getUserName();
    if (mounted && name != null && name.isNotEmpty) {
      setState(() => _userName = name);
    }
    await _fetchDesigns();
  }

  Future<void> _fetchDesigns() async {
    setState(() => _isLoading = true);
    final remoteDesigns = await _apiService.getDesigns();
    if (mounted) {
      final List<DesignProject> fetched = remoteDesigns.map((d) {
        final typeStr = d['apparelType'] ?? d['template'] ?? 'tshirt';
        final type = ApparelType.values.firstWhere(
          (e) => e.name == typeStr,
          orElse: () => ApparelType.tshirt,
        );
        
        Color apparelColor = const Color(0xff222523);
        final rawData = d['designData']?.toString();
        if (rawData != null && rawData.isNotEmpty && rawData != '{}') {
          try {
            final Map<String, dynamic> parsed = jsonDecode(rawData);
            if (parsed['apparelColor'] != null) {
              String hex = parsed['apparelColor'].toString().replaceAll('#', '');
              if (hex.length == 6) hex = 'FF$hex';
              final val = int.tryParse(hex, radix: 16);
              if (val != null) apparelColor = Color(val);
            }
          } catch (_) {}
        }

        return DesignProject(
          id: d['_id']?.toString(),
          name: d['name'] ?? 'Untitled Design',
          type: type,
          color: apparelColor,
          designData: rawData,
          edited: 'Saved in cloud',
        );
      }).toList();
      setState(() {
        _projects.clear();
        _projects.addAll(fetched);
        _isLoading = false;
      });
    }
  }

  void _openEditor(DesignProject project) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DesignEditor(project: project)));
    if (mounted) {
      _fetchDesigns();
    }
  }

  Future<void> _createProject() async {
    final project = await showDialog<DesignProject>(context: context, builder: (_) => const _CreateProjectDialog());
    if (project == null || !mounted) return;

    // Create via API
    final res = await _apiService.createDesign(
      name: project.name,
      apparelType: project.type.name,
      initialStock: project.initialStock,
      unitPrice: project.unitPrice,
    );

    final createdId = res['design']?['_id']?.toString();
    final newProject = DesignProject(
      id: createdId,
      name: project.name,
      type: project.type,
      color: project.color,
      initialStock: project.initialStock,
      unitPrice: project.unitPrice,
      edited: 'Just created',
    );

    setState(() => _projects.insert(0, newProject));
    _openEditor(newProject);
  }

  Future<void> _logout() async {
    await _apiService.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final initials = _userName.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(34, 22, 34, 20),
              child: Row(
                children: [
                  InkWell(
                    onTap: _logout,
                    child: const _Brand(),
                  ),
                  const SizedBox(width: 50),
                  TextButton(
                    onPressed: () {},
                    child: const Text(
                      'DESIGNS',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w900,
                        color: Color(0xff171817),
                        decoration: TextDecoration.underline,
                        decorationThickness: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/designer/inventory');
                    },
                    child: const Text(
                      'Inventory',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w700,
                        color: Color(0xff74756f),
                      ),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 230,
                    height: 42,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search your designs',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 22),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xffd9ee57),
                    child: Text(
                      initials.isEmpty ? 'DS' : initials,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(_userName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.logout, size: 18),
                    tooltip: 'Logout',
                    onPressed: _logout,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(34, 52, 34, 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1360),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('MY DESIGNS', style: TextStyle(fontSize: 13, letterSpacing: 2.2, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      const Text('Your design archive.', style: TextStyle(fontSize: 44, letterSpacing: -1.8, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      const Text('A considered collection of work in progress and ready-to-produce pieces.', style: TextStyle(color: Color(0xff6e706b), fontSize: 15)),
                      const SizedBox(height: 42),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.all(40.0),
                          child: Center(child: CircularProgressIndicator(color: Colors.black)),
                        )
                      else if (_projects.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xffe2e0d8)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: const Color(0xfff6f5f1),
                                  borderRadius: BorderRadius.circular(32),
                                ),
                                child: const Icon(
                                  Icons.checkroom_rounded,
                                  size: 32,
                                  color: Color(0xff171817),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'NO DESIGNS IN YOUR ARCHIVE',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: Color(0xff74756f),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Start crafting your garment collection.',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: Color(0xff171817),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Create a design for T-Shirts, Hoodies, Sweatshirts, Tank Tops, or Polo Shirts.\nEvery design automatically provisions matching warehouse inventory.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xff6e706b),
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 28),
                              ElevatedButton.icon(
                                onPressed: _createProject,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('CREATE FIRST DESIGN', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xff171817),
                                  foregroundColor: const Color(0xffd9ee57),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        LayoutBuilder(
                          builder: (_, constraints) {
                            final columns = constraints.maxWidth > 1100 ? 4 : constraints.maxWidth > 700 ? 3 : 2;
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: 18, mainAxisSpacing: 18, childAspectRatio: .73),
                              itemCount: _projects.length + 1,
                              itemBuilder: (_, index) => index == _projects.length ? _NewDesignCard(onTap: _createProject) : _DesignCard(project: _projects[index], onTap: () => _openEditor(_projects[index])),
                            );
                          },
                        ),
                    ],
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

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => const Row(children: [Text('LA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 23, letterSpacing: -1)), SizedBox(width: 4), Text('FÁBRICA', style: TextStyle(fontWeight: FontWeight.w300, fontSize: 23, letterSpacing: -1))]);
}

class _DesignCard extends StatelessWidget {
  const _DesignCard({required this.project, required this.onTap});
  final DesignProject project;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xffebeae5),
              child: ApparelMockup(
                type: project.type,
                color: project.color,
                child: Center(
                  child: Text(
                    project.name.split(' ').first.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: project.color.computeLuminance() > .5 ? Colors.black : Colors.white,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Text(project.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text('${project.type.label}  ·  ${project.edited}', style: const TextStyle(fontSize: 12, color: Color(0xff787a75))),
        ],
      ),
    );
  }
}

class _NewDesignCard extends StatelessWidget { const _NewDesignCard({required this.onTap}); final VoidCallback onTap; @override Widget build(BuildContext context) => InkWell(onTap: onTap, child: Container(decoration: BoxDecoration(border: Border.all(color: const Color(0xffa5a69f), width: 1.2), color: const Color(0xffefeee9)), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add, size: 46), SizedBox(height: 17), Text('New design', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), SizedBox(height: 6), Text('Start with a blank piece', style: TextStyle(fontSize: 12, color: Color(0xff74756f)))]))); }

class _CreateProjectDialog extends StatefulWidget { const _CreateProjectDialog(); @override State<_CreateProjectDialog> createState() => _CreateProjectDialogState(); }
class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final _name = TextEditingController();
  final _stock = TextEditingController(text: '50');
  final _price = TextEditingController(text: '700');
  ApparelType _selected = ApparelType.tshirt;

  @override
  void dispose() {
    _name.dispose();
    _stock.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('NEW PROJECT', style: TextStyle(fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Make something distinct.', style: TextStyle(fontSize: 31, fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 28),
              const Text('PROJECT NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.3)),
              const SizedBox(height: 8),
              TextField(controller: _name, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Midnight Collection', border: OutlineInputBorder(borderRadius: BorderRadius.zero))),
              const SizedBox(height: 24),
              const Text('CHOOSE YOUR APPAREL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.3)),
              const SizedBox(height: 12),
              Wrap(spacing: 9, runSpacing: 9, children: ApparelType.values.map((type) => ChoiceChip(label: Text(type.label), selected: _selected == type, onSelected: (_) => setState(() => _selected = type), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)), selectedColor: const Color(0xffd9ee57))).toList()),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('INITIAL STOCK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.3)),
                        const SizedBox(height: 8),
                        TextField(controller: _stock, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.zero), isDense: true)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('UNIT PRICE (₹)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.3)),
                        const SizedBox(height: 8),
                        TextField(controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.zero), isDense: true)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 34),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
                    onPressed: () {
                      final nameStr = _name.text.trim().isEmpty ? 'Untitled Project' : _name.text.trim();
                      final stockVal = int.tryParse(_stock.text.trim()) ?? 50;
                      final priceVal = double.tryParse(_price.text.trim()) ?? 700.0;
                      Navigator.pop(
                        context,
                        DesignProject(
                          name: nameStr,
                          type: _selected,
                          color: const Color(0xff292b28),
                          initialStock: stockVal,
                          unitPrice: priceVal,
                        ),
                      );
                    },
                    child: const Text('Create design  →'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
