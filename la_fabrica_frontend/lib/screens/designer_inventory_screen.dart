import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Map<String, dynamic> _summary = {};
  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'low', 'critical', 'healthy'

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
    final summary = await _apiService.getInventorySummary();
    if (mounted) {
      setState(() {
        _inventory = items;
        _summary = summary;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateStock(String id, String action, int quantity, {String? note}) async {
    await _apiService.updateInventoryItem(id, action: action, quantity: quantity, note: note);
    await _fetchInventory();
  }

  Future<void> _quickReplenish(dynamic item, int recommendedQty) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Replenish ${item['productName']}'),
        content: Text(
          'Confirm one-click restock of +$recommendedQty units for ${item['productName']}? Stock will be updated immediately in production catalog.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff171817),
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Restock +$recommendedQty Units'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _updateStock(
        item['_id'],
        'add',
        recommendedQty,
        note: 'Intelligent Replenishment Command +$recommendedQty units',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Replenished +$recommendedQty units for ${item['productName']}'),
            backgroundColor: const Color(0xff181a18),
          ),
        );
      }
    }
  }

  Future<void> _showMovementHistory(dynamic item) async {
    final List<dynamic> changes = item['recentChanges'] ?? [];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Row(
          children: [
            const Icon(Icons.history, size: 20, color: Color(0xff181a18)),
            const SizedBox(width: 8),
            Text(
              'Stock Movement Audit · ${item['productName']}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: changes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No stock adjustments recorded yet.',
                        style: TextStyle(color: Colors.black54)),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: changes.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (ctx, index) {
                    final c = changes[index];
                    final action = c['action']?.toString() ?? 'set';
                    final qty = c['quantity'] ?? 0;
                    final prev = c['previousStock'] ?? 0;
                    final next = c['newStock'] ?? 0;
                    final note = c['note']?.toString() ?? '';
                    final isAdd = action == 'add';

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: isAdd ? const Color(0xffecfdf5) : const Color(0xfffdf2f2),
                        child: Icon(
                          isAdd ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 14,
                          color: isAdd ? const Color(0xff059669) : const Color(0xffc81e1e),
                        ),
                      ),
                      title: Text(
                        '$action: ${isAdd ? "+$qty" : "-$qty"} units ($prev → $next)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: note.isNotEmpty
                          ? Text(note, style: const TextStyle(fontSize: 11, color: Colors.black54))
                          : null,
                      trailing: Text(
                        c['timestamp'] != null
                            ? DateTime.tryParse(c['timestamp'].toString())?.toLocal().toString().substring(0, 16) ?? ''
                            : '',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
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

  Future<void> _showInviteStaffDialog() async {
    final emailController = TextEditingController();
    String? generatedCode;
    bool isGenerating = false;
    String? statusMessage;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.person_add_alt_1, size: 22),
                SizedBox(width: 10),
                Text('Invite Inventory Manager', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Generate an authorized invitation code to grant an inventory manager access to your stock and pricing.',
                    style: TextStyle(fontSize: 13, color: Color(0xff6e706b)),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Invited Staff Email (Optional)',
                      hintText: 'staff@example.com',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (statusMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xffe8f5e9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xffc8e6c9)),
                      ),
                      child: Text(
                        statusMessage!,
                        style: const TextStyle(color: Color(0xff2e7d32), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (generatedCode != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xfff5f5f5),
                        border: Border.all(color: const Color(0xffe0e0e0)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('INVITATION CODE', style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold, color: Color(0xff757575))),
                              const SizedBox(height: 4),
                              SelectableText(
                                generatedCode!,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            tooltip: 'Copy Code',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: generatedCode!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Invitation code copied to clipboard!')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Share this code with your staff member to enter during registration.', style: TextStyle(fontSize: 12, color: Color(0xff757575))),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff171817),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                onPressed: isGenerating
                    ? null
                    : () async {
                        setDialogState(() => isGenerating = true);
                        final res = await _apiService.createInvitation(
                          invitedEmail: emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                        );
                        setDialogState(() {
                          isGenerating = false;
                          if (res['code'] != null) {
                            generatedCode = res['code'];
                            statusMessage = 'Code active for 7 days!';
                          } else {
                            statusMessage = res['message'] ?? 'Failed to generate code';
                          }
                        });
                      },
                child: isGenerating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Generate Code'),
              ),
            ],
          );
        },
      ),
    );
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
      final matchesSearch = name.contains(q) || type.contains(q);

      final stock = (item['stockQuantity'] as num?)?.toInt() ?? 0;
      final threshold = (item['lowStockThreshold'] as num?)?.toInt() ?? 15;

      bool matchesFilter = true;
      if (_statusFilter == 'low') {
        matchesFilter = stock > 0 && stock < threshold;
      } else if (_statusFilter == 'critical') {
        matchesFilter = stock <= 0;
      } else if (_statusFilter == 'healthy') {
        matchesFilter = stock >= threshold;
      }

      return matchesSearch && matchesFilter;
    }).toList();

    double totalValue = (_summary['totalInventoryValue'] as num?)?.toDouble() ?? 0.0;
    int totalStock = (_summary['availableStock'] as num?)?.toInt() ?? 0;
    int lowStockCount = (_summary['lowStockItems'] as num?)?.toInt() ?? 0;
    int criticalCount = (_summary['criticalStockItems'] as num?)?.toInt() ?? 0;
    int healthScore = (_summary['stockHealthScore'] as num?)?.toInt() ?? 100;
    String healthStatus = _summary['healthStatus']?.toString() ?? 'OPTIMAL';
    List<dynamic> replenishmentList = _summary['replenishmentList'] ?? [];

    if (totalValue == 0 && _inventory.isNotEmpty) {
      for (var item in _inventory) {
        final stock = (item['stockQuantity'] as num?)?.toInt() ?? 0;
        final price = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
        totalStock += stock;
        totalValue += (stock * price);
        if (stock < 15 && stock > 0) lowStockCount++;
        if (stock <= 0) criticalCount++;
      }
    }

    final initials = _userName.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xfff6f5f1),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(34, 20, 34, 18),
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
                  const SizedBox(width: 48),
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

            // Main Content Area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(34, 32, 34, 40),
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
                              const Text('COMMERCIAL INVENTORY',
                                  style: TextStyle(fontSize: 12, letterSpacing: 2.2, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              const Text('Stock Health & Valuation Engine',
                                  style: TextStyle(fontSize: 34, letterSpacing: -1.2, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 6),
                              const Text('Intelligent low-stock detection, commercial valuation, and replenish alerts.',
                                  style: TextStyle(color: Color(0xff6e706b), fontSize: 14)),
                            ],
                          ),
                          Row(
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xff171817),
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                ),
                                icon: const Icon(Icons.person_add_alt_1, size: 16),
                                label: const Text('INVITE STAFF',
                                    style: TextStyle(letterSpacing: 1, fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: _showInviteStaffDialog,
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                onPressed: _fetchInventory,
                                tooltip: 'Refresh Stock Health',
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // FEATURE 3: INTELLIGENT STOCK HEALTH BANNER
                      _StockHealthBanner(
                        healthScore: healthScore,
                        healthStatus: healthStatus,
                        lowStockCount: lowStockCount,
                        criticalCount: criticalCount,
                        totalItems: _inventory.length,
                      ),
                      const SizedBox(height: 24),

                      // METRIC CARDS
                      Row(
                        children: [
                          _MetricCard(
                            title: 'TOTAL PRODUCTS',
                            value: '${_inventory.length}',
                            subtitle: 'Active Styles',
                          ),
                          const SizedBox(width: 16),
                          _MetricCard(
                            title: 'UNITS IN STOCK',
                            value: '$totalStock',
                            subtitle: 'Available Stock',
                          ),
                          const SizedBox(width: 16),
                          _MetricCard(
                            title: 'LOW STOCK WARNINGS',
                            value: '$lowStockCount',
                            subtitle: 'Below Reorder Point',
                            badgeColor: lowStockCount > 0 ? const Color(0xffd97706) : null,
                          ),
                          const SizedBox(width: 16),
                          _MetricCard(
                            title: 'CATALOG VALUATION',
                            value: '₹${totalValue.toStringAsFixed(0)}',
                            subtitle: 'Commercial Value',
                            isHighlight: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // FEATURE 3: REPLENISHMENT COMMAND CENTER DRAWER
                      if (replenishmentList.isNotEmpty) ...[
                        _ReplenishmentSection(
                          replenishmentList: replenishmentList,
                          onReplenish: _quickReplenish,
                        ),
                        const SizedBox(height: 32),
                      ],

                      // FILTER CHIPS & SEARCH HEADER
                      Row(
                        children: [
                          const Text(
                            'FILTER BY STOCK STATUS:',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                          ),
                          const SizedBox(width: 14),
                          _filterChip('all', 'All Products (${_inventory.length})'),
                          const SizedBox(width: 8),
                          _filterChip('low', 'Low Stock ($lowStockCount)'),
                          const SizedBox(width: 8),
                          _filterChip('critical', 'Out of Stock ($criticalCount)'),
                          const SizedBox(width: 8),
                          _filterChip('healthy', 'Healthy Buffer'),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // INVENTORY DATA TABLE WITH VISUAL PROGRESS & ACTIONS
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
                              Text('No inventory records matching your filter.',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              SizedBox(height: 6),
                              Text('Adjust your search query or status filter to see other items.',
                                  style: TextStyle(color: Color(0xff74756f))),
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
                              0: FlexColumnWidth(2.6),
                              1: FlexColumnWidth(1.4),
                              2: FlexColumnWidth(2.4),
                              3: FlexColumnWidth(1.6),
                              4: FlexColumnWidth(1.8),
                              5: FlexColumnWidth(1.4),
                              6: FlexColumnWidth(1.2),
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
                                  _th('SILHOUETTE'),
                                  _th('STOCK & BUFFER'),
                                  _th('UNIT PRICE'),
                                  _th('TOTAL VALUE'),
                                  _th('HEALTH'),
                                  _th('AUDIT'),
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
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              item['productName'] ?? 'Design',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                      child: Text(
                                        (item['apparelLabel'] ?? item['apparelType'] ?? 'T-Shirt').toUpperCase(),
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xff6e706b)),
                                      ),
                                    ),
                                    // Stock buffer & stepper
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.remove_circle_outline, size: 18),
                                                onPressed: () => _updateStock(item['_id'], 'reduce', 5),
                                                tooltip: 'Reduce stock (-5)',
                                              ),
                                              Text(
                                                '${item['stockQuantity']}',
                                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.add_circle_outline, size: 18),
                                                onPressed: () => _updateStock(item['_id'], 'add', 5),
                                                tooltip: 'Add stock (+5)',
                                              ),
                                            ],
                                          ),
                                          // Mini visual stock meter
                                          _MiniStockProgress(
                                            stock: (item['stockQuantity'] as num?)?.toInt() ?? 0,
                                            threshold: (item['lowStockThreshold'] as num?)?.toInt() ?? 15,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                      child: InkWell(
                                        onTap: () => _editPriceDialog(item),
                                        child: Row(
                                          children: [
                                            Text(
                                              '₹${item['unitPrice']}',
                                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                            ),
                                            const SizedBox(width: 4),
                                            const Icon(Icons.edit_outlined, size: 13, color: Colors.grey),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                      child: Text(
                                        '₹${((item['stockQuantity'] as num) * (item['unitPrice'] as num)).toStringAsFixed(0)}',
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xff171817)),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                      child: _StatusChip(
                                        stock: (item['stockQuantity'] as num?)?.toInt() ?? 0,
                                        threshold: (item['lowStockThreshold'] as num?)?.toInt() ?? 15,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                      child: IconButton(
                                        icon: const Icon(Icons.history, size: 18, color: Color(0xff74756f)),
                                        tooltip: 'Movement History',
                                        onPressed: () => _showMovementHistory(item),
                                      ),
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

  Widget _filterChip(String key, String label) {
    final sel = _statusFilter == key;
    return ChoiceChip(
      selected: sel,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
        color: sel ? Colors.black : Colors.black87,
      ),
      selectedColor: const Color(0xffd9ee57),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(2),
        side: BorderSide(color: sel ? const Color(0xffd9ee57) : Colors.black12),
      ),
      onSelected: (_) => setState(() => _statusFilter = key),
    );
  }

  Widget _th(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Text(
        title,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Color(0xff74756f)),
      ),
    );
  }
}

// ---------------------------------------------------------
// FEATURE 3: STOCK HEALTH BANNER WIDGET
// ---------------------------------------------------------
class _StockHealthBanner extends StatelessWidget {
  const _StockHealthBanner({
    required this.healthScore,
    required this.healthStatus,
    required this.lowStockCount,
    required this.criticalCount,
    required this.totalItems,
  });

  final int healthScore;
  final String healthStatus;
  final int lowStockCount;
  final int criticalCount;
  final int totalItems;

  @override
  Widget build(BuildContext context) {
    final isOptimal = healthStatus == 'OPTIMAL';
    final isCritical = healthStatus == 'CRITICAL';
    final Color accentColor = isOptimal
        ? const Color(0xff059669)
        : (isCritical ? const Color(0xffc81e1e) : const Color(0xffd97706));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xffe2e0d8)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOptimal ? Icons.verified_outlined : (isCritical ? Icons.error_outline : Icons.warning_amber),
              color: accentColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'STOCK HEALTH INDEX · $healthScore%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        healthStatus,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accentColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isOptimal
                      ? 'All active catalog items are adequately stocked above the recommended replenishment buffers.'
                      : (isCritical
                          ? 'Immediate action required: $criticalCount items are completely out of stock with potential lost revenue.'
                          : 'Attention needed: $lowStockCount apparel items have dropped below safety buffer thresholds.'),
                  style: const TextStyle(fontSize: 13, color: Color(0xff6e706b)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Health score progress bar
          SizedBox(
            width: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$healthScore% Healthy',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: healthScore / 100,
                    minHeight: 8,
                    backgroundColor: const Color(0xffecece7),
                    valueColor: AlwaysStoppedAnimation(accentColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// FEATURE 3: REPLENISHMENT CAROUSEL / SECTION
// ---------------------------------------------------------
class _ReplenishmentSection extends StatelessWidget {
  const _ReplenishmentSection({
    required this.replenishmentList,
    required this.onReplenish,
  });

  final List<dynamic> replenishmentList;
  final Function(dynamic item, int qty) onReplenish;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xff171817),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt, color: Color(0xffd9ee57), size: 18),
              SizedBox(width: 8),
              Text(
                'INTELLIGENT REPLENISHMENT QUEUE',
                style: TextStyle(
                  color: Color(0xffd9ee57),
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.5,
                ),
              ),
              Spacer(),
              Text('Items needing immediate production restock',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: replenishmentList.map((item) {
              final stock = item['stockQuantity'] ?? 0;
              final rec = item['recommendedRestock'] ?? 25;
              final isCritical = item['urgency'] == 'CRITICAL';

              return Container(
                width: 290,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xff222422),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: isCritical ? const Color(0xffe95b4d) : const Color(0xff444744),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item['productName'] ?? 'Item',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isCritical
                                ? const Color(0x33e95b4d)
                                : const Color(0x33d97706),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            isCritical ? 'OUT OF STOCK' : 'LOW ($stock left)',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isCritical
                                  ? const Color(0xffe95b4d)
                                  : const Color(0xfff39c12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Suggest: +$rec units',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xffd9ee57),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          ),
                          onPressed: () => onReplenish(item, rec as int),
                          child: const Text('Restock',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// MINI STOCK PROGRESS BAR
// ---------------------------------------------------------
class _MiniStockProgress extends StatelessWidget {
  const _MiniStockProgress({required this.stock, required this.threshold});
  final int stock;
  final int threshold;

  @override
  Widget build(BuildContext context) {
    final double target = (threshold * 2).toDouble();
    final double progress = (stock / target).clamp(0.0, 1.0);
    final isOut = stock <= 0;
    final isLow = stock > 0 && stock < threshold;
    final color = isOut ? const Color(0xffc81e1e) : (isLow ? const Color(0xffd97706) : const Color(0xff059669));

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 4,
          backgroundColor: const Color(0xfff0efe9),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// METRIC CARD
// ---------------------------------------------------------
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    this.isHighlight = false,
    this.badgeColor,
  });

  final String title;
  final String value;
  final String subtitle;
  final bool isHighlight;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: isHighlight ? const Color(0xff171817) : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isHighlight ? const Color(0xff171817) : const Color(0xffe2e0d8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: isHighlight ? const Color(0xffd9ee57) : const Color(0xff74756f),
                  ),
                ),
                if (badgeColor != null)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: isHighlight ? Colors.white : const Color(0xff171817),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isHighlight ? const Color(0xffb5b7b0) : const Color(0xff74756f),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// STATUS CHIP
// ---------------------------------------------------------
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.stock, required this.threshold});
  final int stock;
  final int threshold;

  @override
  Widget build(BuildContext context) {
    final isOut = stock <= 0;
    final isLow = stock > 0 && stock < threshold;
    final color = isOut ? const Color(0xffc81e1e) : (isLow ? const Color(0xffd97706) : const Color(0xff059669));
    final bg = isOut ? const Color(0xfffdf2f2) : (isLow ? const Color(0xfffffbeb) : const Color(0xffecfdf5));
    final text = isOut ? 'Critical (0)' : (isLow ? 'Low Stock' : 'Healthy');

    return UnconstrainedBox(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
        ),
      ),
    );
  }
}
