import 'package:flutter/material.dart';
import '../services/api_service.dart';

class InventoryDashboardScreen extends StatefulWidget {
  const InventoryDashboardScreen({super.key});

  @override
  State<InventoryDashboardScreen> createState() => _InventoryDashboardScreenState();
}

class _InventoryDashboardScreenState extends State<InventoryDashboardScreen> {
  final ApiService _apiService = ApiService();
  String _userName = 'Inventory Manager';
  List<dynamic> _inventory = [];
  Map<String, dynamic> _summary = {};
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
    await _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final items = await _apiService.getInventory();
    final summary = await _apiService.getInventorySummary();
    if (mounted) {
      setState(() {
        _inventory = items;
        _summary = summary;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateStock(String id, String action, int quantity) async {
    await _apiService.updateInventoryItem(id, action: action, quantity: quantity);
    await _fetchData();
  }

  Future<void> _editPriceDialog(dynamic item) async {
    final controller = TextEditingController(text: item['unitPrice'].toString());
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update Price — ${item['productName']}'),
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
      await _fetchData();
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

    double totalVal = (_summary['totalInventoryValue'] as num?)?.toDouble() ?? 0.0;
    int availStock = (_summary['availableStock'] as num?)?.toInt() ?? 0;
    int lowStock = (_summary['lowStockItems'] as num?)?.toInt() ?? 0;
    int totalProds = (_summary['totalProducts'] as num?)?.toInt() ?? _inventory.length;

    final initials = _userName.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xfff6f5f1),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with LA FABRICA Logo ONLY (Strictly isolated — NO Designer links!)
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
                  const SizedBox(width: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xff171817),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Text(
                      'INVENTORY PORTAL',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 240,
                    height: 42,
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Filter stock items',
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
                    backgroundColor: const Color(0xff171817),
                    child: Text(
                      initials.isEmpty ? 'IV' : initials,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
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
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('MANAGEMENT OVERVIEW', style: TextStyle(fontSize: 13, letterSpacing: 2.2, fontWeight: FontWeight.w800)),
                              SizedBox(height: 8),
                              Text('Inventory & Stock Control', style: TextStyle(fontSize: 36, letterSpacing: -1.5, fontWeight: FontWeight.w900)),
                              SizedBox(height: 8),
                              Text('Manage product quantities, update unit pricing, and track apparel valuation.', style: TextStyle(color: Color(0xff6e706b), fontSize: 15)),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _fetchData,
                            tooltip: 'Refresh Inventory',
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Metrics Grid
                      Row(
                        children: [
                          _MetricBox(title: 'TOTAL PRODUCTS', value: '$totalProds', subtitle: 'Managed Items'),
                          const SizedBox(width: 16),
                          _MetricBox(title: 'AVAILABLE STOCK', value: '$availStock', subtitle: 'Units in Warehouse'),
                          const SizedBox(width: 16),
                          _MetricBox(title: 'LOW STOCK ALERT', value: '$lowStock', subtitle: 'Items under 10 units', isWarning: lowStock > 0),
                          const SizedBox(width: 16),
                          _MetricBox(title: 'TOTAL VALUATION', value: '₹${totalVal.toStringAsFixed(0)}', subtitle: 'Valuation = Stock × Price', isAccent: true),
                        ],
                      ),
                      const SizedBox(height: 40),

                      // Table View
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
                              Text('No inventory records assigned.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              SizedBox(height: 6),
                              Text('Assigned designer has not published any apparel designs yet.', style: TextStyle(color: Color(0xff74756f))),
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
                                  _th('APPAREL DESIGN'),
                                  _th('CATEGORY'),
                                  _th('STOCK CONTROL'),
                                  _th('UNIT PRICE'),
                                  _th('TOTAL VALUATION'),
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
                                            child: const Icon(Icons.inventory_2, color: Colors.white, size: 20),
                                          ),
                                          const SizedBox(width: 14),
                                          Text(
                                            item['productName'] ?? 'Product',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                      child: Text(
                                        (item['apparelType'] ?? 'Apparel').toUpperCase(),
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
                                            tooltip: 'Deduct 5 stock',
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
                                            tooltip: 'Add 5 stock',
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
                                      child: _StatusBadge(stock: item['stockQuantity'] as int),
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

class _MetricBox extends StatelessWidget {
  const _MetricBox({
    required this.title,
    required this.value,
    required this.subtitle,
    this.isAccent = false,
    this.isWarning = false,
  });

  final String title;
  final String value;
  final String subtitle;
  final bool isAccent;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final bg = isAccent
        ? const Color(0xff171817)
        : (isWarning ? const Color(0xfffffbeb) : Colors.white);
    final borderColor = isAccent
        ? const Color(0xff171817)
        : (isWarning ? const Color(0xfffcd34d) : const Color(0xffe2e0d8));

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor),
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
                color: isAccent
                    ? const Color(0xffd9ee57)
                    : (isWarning ? const Color(0xffb45309) : const Color(0xff74756f)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: isAccent ? Colors.white : const Color(0xff171817),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isAccent ? const Color(0xffb5b7b0) : const Color(0xff74756f),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.stock});
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
