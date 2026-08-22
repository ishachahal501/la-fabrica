import 'package:flutter/material.dart';
import '../services/api_service.dart';

class DesignerInventoryScreen extends StatefulWidget {
  const DesignerInventoryScreen({super.key});

  @override
  State<DesignerInventoryScreen> createState() => _DesignerInventoryScreenState();
}

class _DesignerInventoryScreenState extends State<DesignerInventoryScreen> {
  final ApiService _apiService = ApiService();
  String _userName = 'Designer';
  List<dynamic> _inventory = [];
  bool _isLoading = true;
  String _searchQuery = '';

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
    await _fetchInventory();
  }

  Future<void> _fetchInventory() async {
    setState(() => _isLoading = true);
    final items = await _apiService.getInventory();
    if (mounted) {
      setState(() {
        _inventory = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateStock(String id, String action, int quantity) async {
    await _apiService.updateInventoryItem(id, action: action, quantity: quantity);
    await _fetchInventory();
  }

  Future<void> _editPriceDialog(dynamic item) async {
    final controller = TextEditingController(text: item['unitPrice'].toString());
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Price — ${item['productName']}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Price Per Unit (₹)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _apiService.updateInventoryItem(item['_id'], unitPrice: result);
      await _fetchInventory();
    }
  }

  Future<void> _logout() async {
    await _apiService.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _inventory.where((item) {
      final name = (item['productName'] ?? '').toString().toLowerCase();
      final type = (item['apparelType'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || type.contains(q);
    }).toList();

    double totalValue = 0;
    int totalStock = 0;
    for (var item in _inventory) {
      final stock = (item['stockQuantity'] as num?)?.toInt() ?? 0;
      final price = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
      totalStock += stock;
      totalValue += (stock * price);
    }

    final initials = _userName.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xfff6f5f1),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(34, 22, 34, 20),
              child: Row(
                children: [
                  InkWell(
                    onTap: _logout,
                    child: const Row(
                      children: [
                        Text('LA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 23, letterSpacing: -1)),
                        SizedBox(width: 4),
                        Text('FÁBRICA', style: TextStyle(fontWeight: FontWeight.w300, fontSize: 23, letterSpacing: -1)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 50),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/designer'),
                    child: const Text(
                      'Designs',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w700,
                        color: Color(0xff74756f),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  TextButton(
                    onPressed: () {},
                    child: const Text(
                      'INVENTORY',
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
                  const Spacer(),
                  SizedBox(
                    width: 230,
                    height: 42,
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Search inventory',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                        isDense: true,
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

            // Content Area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(34, 40, 34, 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1360),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('MY INVENTORY', style: TextStyle(fontSize: 13, letterSpacing: 2.2, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 8),
                              const Text('Apparel Stock & Valuation', style: TextStyle(fontSize: 36, letterSpacing: -1.5, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 8),
                              const Text('Inventory levels and pricing reserved exclusively for your designs.', style: TextStyle(color: Color(0xff6e706b), fontSize: 15)),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _fetchInventory,
                            tooltip: 'Refresh Inventory',
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Metrics Cards
                      Row(
                        children: [
                          _MetricCard(title: 'TOTAL DESIGNS', value: '${_inventory.length}', subtitle: 'Linked Products'),
                          const SizedBox(width: 20),
                          _MetricCard(title: 'TOTAL UNITS', value: '$totalStock', subtitle: 'Items in Stock'),
                          const SizedBox(width: 20),
                          _MetricCard(title: 'VALUATION', value: '₹${totalValue.toStringAsFixed(0)}', subtitle: 'Total Inventory Value', isHighlight: true),
                        ],
                      ),
                      const SizedBox(height: 40),

                      // Inventory Table
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.all(60),
                          child: Center(child: CircularProgressIndicator(color: Colors.black)),
                        )
                      else if (filtered.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(60),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xffe2e0d8)),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xffa2a39b)),
                              SizedBox(height: 16),
                              Text('No inventory records found.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              SizedBox(height: 6),
                              Text('Create a design from your Designer Dashboard to generate inventory items.', style: TextStyle(color: Color(0xff74756f))),
                            ],
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xffe2e0d8)),
                          ),
                          child: Table(
                            columnWidths: const {
                              0: FlexColumnWidth(2.5),
                              1: FlexColumnWidth(1.5),
                              2: FlexColumnWidth(2.0),
                              3: FlexColumnWidth(1.5),
                              4: FlexColumnWidth(1.8),
                              5: FlexColumnWidth(1.4),
                            },
                            children: [
                              // Table Header
                              TableRow(
                                decoration: const BoxDecoration(
                                  color: Color(0xfff7f7f3),
                                  border: Border(bottom: BorderSide(color: Color(0xffe2e0d8))),
                                ),
                                children: [
                                  _th('DESIGN NAME'),
                                  _th('APPAREL TYPE'),
                                  _th('STOCK QUANTITY'),
                                  _th('PRICE PER UNIT'),
                                  _th('TOTAL VALUE'),
                                  _th('STATUS'),
                                ],
                              ),
                              // Table Rows
                              for (var item in filtered) ...[
                                TableRow(
                                  decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Color(0xfff0efe9))),
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: const Color(0xff171817),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Icon(Icons.checkroom, color: Colors.white, size: 20),
                                          ),
                                          const SizedBox(width: 14),
                                          Text(
                                            item['productName'] ?? 'Design',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                      child: Text(
                                        (item['apparelType'] ?? 'T-Shirt').toUpperCase(),
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xff6e706b)),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                      child: Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.remove_circle_outline, size: 20),
                                            onPressed: () => _updateStock(item['_id'], 'reduce', 5),
                                            tooltip: 'Reduce stock (-5)',
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            child: Text(
                                              '${item['stockQuantity']}',
                                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add_circle_outline, size: 20),
                                            onPressed: () => _updateStock(item['_id'], 'add', 5),
                                            tooltip: 'Add stock (+5)',
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                      child: InkWell(
                                        onTap: () => _editPriceDialog(item),
                                        child: Row(
                                          children: [
                                            Text(
                                              '₹${item['unitPrice']}',
                                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                            ),
                                            const SizedBox(width: 6),
                                            const Icon(Icons.edit_outlined, size: 14, color: Colors.grey),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                      child: Text(
                                        '₹${((item['stockQuantity'] as num) * (item['unitPrice'] as num)).toStringAsFixed(0)}',
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xff171817)),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                      child: _StatusChip(stock: item['stockQuantity'] as int),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
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

  Widget _th(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Text(
        title,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Color(0xff74756f)),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    this.isHighlight = false,
  });

  final String title;
  final String value;
  final String subtitle;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isHighlight ? const Color(0xff171817) : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isHighlight ? const Color(0xff171817) : const Color(0xffe2e0d8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: isHighlight ? const Color(0xffd9ee57) : const Color(0xff74756f),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: isHighlight ? Colors.white : const Color(0xff171817),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isHighlight ? const Color(0xffb5b7b0) : const Color(0xff74756f),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.stock});
  final int stock;

  @override
  Widget build(BuildContext context) {
    final isOut = stock <= 0;
    final isLow = stock > 0 && stock < 10;
    final color = isOut ? const Color(0xffc81e1e) : (isLow ? const Color(0xffd97706) : const Color(0xff059669));
    final bg = isOut ? const Color(0xfffdf2f2) : (isLow ? const Color(0xfffffbeb) : const Color(0xffecfdf5));
    final text = isOut ? 'Out of Stock' : (isLow ? 'Low Stock' : 'In Stock');

    return UnconstrainedBox(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
        ),
      ),
    );
  }
}
