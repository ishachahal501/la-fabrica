import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/design_element.dart';
import '../models/design_project.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import '../utils/image_helper.dart';
import '../widgets/apparel_mockup.dart';

class DesignEditor extends StatefulWidget {
  const DesignEditor({super.key, required this.project});
  final DesignProject project;

  @override
  State<DesignEditor> createState() => _DesignEditorState();
}

class _DesignEditorState extends State<DesignEditor> {
  final ApiService _apiService = ApiService();
  final GlobalKey _canvasKey = GlobalKey();

  List<DesignElement> _elements = [];
  String? _selectedElementId;
  ApparelType _apparelType = ApparelType.tshirt;
  Color _apparelColor = const Color(0xff1a1a1a);

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _isDirty = false;
  String _activeTab = 'text'; // 'text', 'image', 'elements', 'color', 'layers'

  // Undo / Redo stacks
  final List<_EditorHistoryState> _undoStack = [];
  final List<_EditorHistoryState> _redoStack = [];

  @override
  void initState() {
    super.initState();
    _apparelType = widget.project.type;
    _apparelColor = widget.project.color;
    _loadDesignState();
  }

  Future<void> _loadDesignState() async {
    setState(() => _isLoading = true);

    String? jsonStr = widget.project.designData;

    // Fetch from backend if design has an ID but local designData is missing/empty
    if ((jsonStr == null || jsonStr.trim().isEmpty || jsonStr == '{}') &&
        widget.project.id != null) {
      final remote = await _apiService.getDesignById(widget.project.id!);
      if (remote != null && remote['designData'] != null) {
        jsonStr = remote['designData'].toString();
      }
    }

    if (jsonStr != null && jsonStr.trim().isNotEmpty && jsonStr != '{}') {
      try {
        final Map<String, dynamic> data = jsonDecode(jsonStr);

        if (data['apparelType'] != null) {
          final typeStr = data['apparelType'].toString();
          _apparelType = ApparelType.values.firstWhere(
            (e) => e.name == typeStr,
            orElse: () => widget.project.type,
          );
        }

        if (data['apparelColor'] != null) {
          String hex = data['apparelColor'].toString().replaceAll('#', '');
          if (hex.length == 6) hex = 'FF$hex';
          final val = int.tryParse(hex, radix: 16);
          if (val != null) _apparelColor = Color(val);
        }

        if (data['elements'] is List) {
          _elements = (data['elements'] as List)
              .map((e) => DesignElement.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (e) {
        print('Error parsing designData: $e');
      }
    }

    // Default initial text element if design is blank
    if (_elements.isEmpty) {
      _elements = [
        DesignElement(
          id: 'def_text_1',
          type: ElementType.text,
          content: widget.project.name.toUpperCase(),
          x: 40.0,
          y: 110.0,
          fontSize: 22.0,
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ];
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isDirty = false;
      });
    }
  }

  void _pushHistory() {
    _undoStack.add(_EditorHistoryState(
      apparelColor: _apparelColor,
      apparelType: _apparelType,
      elements: _elements.map((e) => e.clone()).toList(),
    ));
    if (_undoStack.length > 30) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    setState(() => _isDirty = true);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final current = _EditorHistoryState(
      apparelColor: _apparelColor,
      apparelType: _apparelType,
      elements: _elements.map((e) => e.clone()).toList(),
    );
    _redoStack.add(current);

    final prev = _undoStack.removeLast();
    setState(() {
      _apparelColor = prev.apparelColor;
      _apparelType = prev.apparelType;
      _elements = prev.elements.map((e) => e.clone()).toList();
      _isDirty = true;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final current = _EditorHistoryState(
      apparelColor: _apparelColor,
      apparelType: _apparelType,
      elements: _elements.map((e) => e.clone()).toList(),
    );
    _undoStack.add(current);

    final next = _redoStack.removeLast();
    setState(() {
      _apparelColor = next.apparelColor;
      _apparelType = next.apparelType;
      _elements = next.elements.map((e) => e.clone()).toList();
      _isDirty = true;
    });
  }

  DesignElement? get _selectedElement {
    if (_selectedElementId == null) return null;
    try {
      return _elements.firstWhere((e) => e.id == _selectedElementId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveDesign() async {
    if (widget.project.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Design saved locally.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final String hexColor =
        '#${_apparelColor.toARGB32().toRadixString(16).padLeft(8, '0')}';
    final Map<String, dynamic> dataMap = {
      'apparelType': _apparelType.name,
      'apparelColor': hexColor,
      'elements': _elements.map((e) => e.toJson()).toList(),
    };
    final String designDataJson = jsonEncode(dataMap);

    final res = await _apiService.updateDesign(
      widget.project.id!,
      name: widget.project.name,
      apparelType: _apparelType.name,
      designData: designDataJson,
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
        if (res['_id'] != null || res['name'] != null) {
          _isDirty = false;
        }
      });

      if (res['_id'] != null || res['name'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved ✓  Design persisted to MongoDB'),
            backgroundColor: Color(0xff181a18),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Failed to save design'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _exportDesign() async {
    setState(() => _isExporting = true);
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final boundary =
          _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Canvas render object not available.');
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('Failed to generate PNG bytes.');
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final String filename =
          '${widget.project.name.toLowerCase().replaceAll(' ', '_')}_design.png';

      if (kIsWeb) {
        FilePickerHelper.downloadPngWeb(pngBytes, filename);
      }

      if (mounted) {
        setState(() => _isExporting = false);
        _showExportModal(pngBytes);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: ${e.toString()}')),
        );
      }
    }
  }

  void _showExportModal(Uint8List bytes) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xff181a18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Color(0xffd9ee57)),
                  SizedBox(width: 10),
                  Text(
                    'EXPORT COMPLETE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 260,
                decoration: BoxDecoration(
                  color: const Color(0xff2a2c2a),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close', style: TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xffd9ee57),
                      foregroundColor: Colors.black,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    onPressed: () {
                      FilePickerHelper.downloadPngWeb(
                        bytes,
                        '${widget.project.name.replaceAll(' ', '_')}_design.png',
                      );
                      Navigator.pop(ctx);
                    },
                    child: const Text('Download PNG'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addElement(ElementType type, {ShapeType shape = ShapeType.rectangle, String? content, String? imageData}) {
    _pushHistory();
    final String id = 'elem_${DateTime.now().millisecondsSinceEpoch}';
    final newElem = DesignElement(
      id: id,
      type: type,
      shapeType: shape,
      content: content ?? (type == ElementType.text ? 'LA FÁBRICA' : ''),
      imageData: imageData,
      x: 50.0 + (_elements.length * 10),
      y: 80.0 + (_elements.length * 10),
      color: type == ElementType.text ? Colors.white : const Color(0xffd9ee57),
    );
    setState(() {
      _elements.add(newElem);
      _selectedElementId = id;
    });
  }

  Future<void> _uploadImage() async {
    try {
      final bytes = await FilePickerHelper.pickImageBytes();
      if (bytes == null) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Processing and compressing image...')),
      );

      final String dataUri = await ImageHelper.processAndCompressImage(bytes);
      _addElement(ElementType.image, imageData: dataUri);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _deleteElement(String id) {
    _pushHistory();
    setState(() {
      _elements.removeWhere((e) => e.id == id);
      if (_selectedElementId == id) _selectedElementId = null;
    });
  }

  void _moveLayer(String id, bool forward) {
    final idx = _elements.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    if (forward && idx < _elements.length - 1) {
      _pushHistory();
      setState(() {
        final elem = _elements.removeAt(idx);
        _elements.insert(idx + 1, elem);
      });
    } else if (!forward && idx > 0) {
      _pushHistory();
      setState(() {
        final elem = _elements.removeAt(idx);
        _elements.insert(idx - 1, elem);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffecece7),
      body: SafeArea(
        child: Column(
          children: [
            _EditorTopBar(
              name: widget.project.name,
              isDirty: _isDirty,
              canUndo: _undoStack.isNotEmpty,
              canRedo: _redoStack.isNotEmpty,
              isSaving: _isSaving,
              isExporting: _isExporting,
              onBack: () async {
                if (_isDirty) {
                  final leave = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Unsaved Changes'),
                      content: const Text(
                        'You have unsaved changes in your design. Leave without saving?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Stay'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Leave'),
                        ),
                      ],
                    ),
                  );
                  if (leave == true && mounted) Navigator.pop(context);
                } else {
                  Navigator.pop(context);
                }
              },
              onUndo: _undo,
              onRedo: _redo,
              onSave: _saveDesign,
              onExport: _exportDesign,
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    )
                  : Row(
                      children: [
                        // LEFT TOOLS NAVIGATION
                        _ToolsSidebar(
                          activeTab: _activeTab,
                          onTabChanged: (tab) => setState(() => _activeTab = tab),
                        ),
                        // LEFT TOOL DRAWER
                        _ToolDrawer(
                          activeTab: _activeTab,
                          apparelColor: _apparelColor,
                          elements: _elements,
                          selectedId: _selectedElementId,
                          onAddText: (txt) => _addElement(ElementType.text, content: txt),
                          onAddShape: (shape) => _addElement(ElementType.shape, shape: shape),
                          onUploadImage: _uploadImage,
                          onSelectColor: (c) {
                            _pushHistory();
                            setState(() => _apparelColor = c);
                          },
                          onSelectElement: (id) => setState(() => _selectedElementId = id),
                          onMoveLayer: _moveLayer,
                          onDeleteElement: _deleteElement,
                        ),
                        // CENTER APPAREL CANVAS
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedElementId = null),
                            child: Container(
                              color: const Color(0xffe2e1db),
                              child: Center(
                                child: RepaintBoundary(
                                  key: _canvasKey,
                                  child: Container(
                                    width: 540,
                                    height: 600,
                                    color: const Color(0xfff5f4ef),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        const Positioned(
                                          top: 16,
                                          child: Text(
                                            'FRONT · CANVAS 100%',
                                            style: TextStyle(
                                              fontSize: 10,
                                              letterSpacing: 1.5,
                                              color: Color(0xff777871),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        ApparelMockup(
                                          type: _apparelType,
                                          color: _apparelColor,
                                          large: true,
                                          showPrintAreaBorder: true,
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: _elements.map((elem) {
                                              final isSel =
                                                  elem.id == _selectedElementId;
                                              return _InteractiveElement(
                                                key: ValueKey(elem.id),
                                                element: elem,
                                                isSelected: isSel,
                                                onSelect: () => setState(() =>
                                                    _selectedElementId = elem.id),
                                                onUpdate: () {
                                                  _pushHistory();
                                                  setState(() {});
                                                },
                                                onDelete: () =>
                                                    _deleteElement(elem.id),
                                                onForward: () =>
                                                    _moveLayer(elem.id, true),
                                                onBackward: () =>
                                                    _moveLayer(elem.id, false),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                        const Positioned(
                                          bottom: 16,
                                          child: Text(
                                            'CLICK ELEMENT TO EDIT · DRAG TO MOVE',
                                            style: TextStyle(
                                              fontSize: 10,
                                              letterSpacing: 1.3,
                                              color: Color(0xff777871),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // RIGHT PROPERTIES INSPECTOR
                        _PropertiesPanel(
                          selectedElement: _selectedElement,
                          apparelType: _apparelType,
                          apparelColor: _apparelColor,
                          onApparelTypeChanged: (type) {
                            _pushHistory();
                            setState(() => _apparelType = type);
                          },
                          onApparelColorChanged: (c) {
                            _pushHistory();
                            setState(() => _apparelColor = c);
                          },
                          onElementChanged: () {
                            _pushHistory();
                            setState(() {});
                          },
                          onDelete: () {
                            if (_selectedElementId != null) {
                              _deleteElement(_selectedElementId!);
                            }
                          },
                          onMoveForward: () {
                            if (_selectedElementId != null) {
                              _moveLayer(_selectedElementId!, true);
                            }
                          },
                          onMoveBackward: () {
                            if (_selectedElementId != null) {
                              _moveLayer(_selectedElementId!, false);
                            }
                          },
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorHistoryState {
  _EditorHistoryState({
    required this.apparelColor,
    required this.apparelType,
    required this.elements,
  });
  final Color apparelColor;
  final ApparelType apparelType;
  final List<DesignElement> elements;
}

class _EditorTopBar extends StatelessWidget {
  const _EditorTopBar({
    required this.name,
    required this.isDirty,
    required this.canUndo,
    required this.canRedo,
    required this.isSaving,
    required this.isExporting,
    required this.onBack,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
    required this.onExport,
  });

  final String name;
  final bool isDirty;
  final bool canUndo;
  final bool canRedo;
  final bool isSaving;
  final bool isExporting;
  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onSave;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: const Color(0xff181a18),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: 'Back to Dashboard',
          ),
          const SizedBox(width: 12),
          const Text(
            'LA FÁBRICA',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              fontSize: 16,
            ),
          ),
          Container(
            height: 20,
            width: 1,
            color: Colors.white24,
            margin: const EdgeInsets.symmetric(horizontal: 18),
          ),
          Text(
            name,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(width: 14),
          // Saved / Unsaved status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isDirty ? const Color(0x33e95b4d) : const Color(0x33d9ee57),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              isDirty ? 'Unsaved changes' : 'Saved ✓',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isDirty ? const Color(0xffe95b4d) : const Color(0xffd9ee57),
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: canUndo ? onUndo : null,
            icon: Icon(
              Icons.undo_outlined,
              color: canUndo ? Colors.white : Colors.white30,
              size: 20,
            ),
            tooltip: 'Undo',
          ),
          IconButton(
            onPressed: canRedo ? onRedo : null,
            icon: Icon(
              Icons.redo_outlined,
              color: canRedo ? Colors.white : Colors.white30,
              size: 20,
            ),
            tooltip: 'Redo',
          ),
          const SizedBox(width: 18),
          OutlinedButton(
            onPressed: isSaving ? null : onSave,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save Design'),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: isExporting ? null : onExport,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffd9ee57),
              foregroundColor: Colors.black,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: isExporting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Text('Export'),
          ),
        ],
      ),
    );
  }
}

class _ToolsSidebar extends StatelessWidget {
  const _ToolsSidebar({required this.activeTab, required this.onTabChanged});
  final String activeTab;
  final ValueChanged<String> onTabChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      color: const Color(0xff1f211f),
      child: Column(
        children: [
          const SizedBox(height: 16),
          _item('text', Icons.title, 'Text'),
          _item('image', Icons.image_outlined, 'Image'),
          _item('elements', Icons.category_outlined, 'Shapes'),
          _item('color', Icons.palette_outlined, 'Color'),
          _item('layers', Icons.layers_outlined, 'Layers'),
        ],
      ),
    );
  }

  Widget _item(String tab, IconData icon, String label) {
    final bool selected = activeTab == tab;
    return InkWell(
      onTap: () => onTabChanged(tab),
      child: Container(
        height: 64,
        width: double.infinity,
        color: selected ? const Color(0xffd9ee57) : Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? Colors.black : Colors.white70,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.black : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolDrawer extends StatelessWidget {
  const _ToolDrawer({
    required this.activeTab,
    required this.apparelColor,
    required this.elements,
    required this.selectedId,
    required this.onAddText,
    required this.onAddShape,
    required this.onUploadImage,
    required this.onSelectColor,
    required this.onSelectElement,
    required this.onMoveLayer,
    required this.onDeleteElement,
  });

  final String activeTab;
  final Color apparelColor;
  final List<DesignElement> elements;
  final String? selectedId;
  final ValueChanged<String> onAddText;
  final ValueChanged<ShapeType> onAddShape;
  final VoidCallback onUploadImage;
  final ValueChanged<Color> onSelectColor;
  final ValueChanged<String> onSelectElement;
  final Function(String id, bool forward) onMoveLayer;
  final ValueChanged<String> onDeleteElement;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      color: const Color(0xfff7f7f3),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            activeTab.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          Expanded(child: _buildDrawerContent()),
        ],
      ),
    );
  }

  Widget _buildDrawerContent() {
    switch (activeTab) {
      case 'text':
        return ListView(
          children: [
            _actionBtn('Add Heading', () => onAddText('LA FÁBRICA')),
            const SizedBox(height: 10),
            _actionBtn('Add Subtitle', () => onAddText('STUDIO 2026')),
            const SizedBox(height: 10),
            _actionBtn('Add Body Text', () => onAddText('LIMITED EDITION')),
          ],
        );
      case 'image':
        return ListView(
          children: [
            OutlinedButton.icon(
              onPressed: onUploadImage,
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Upload Local Image'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.black26),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'PRESET GRAPHICS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Color(0xff777871),
              ),
            ),
            const SizedBox(height: 12),
            _presetGraphicItem('★ STAR BADGE', '★'),
            _presetGraphicItem('⚡ LIGHTNING', '⚡'),
            _presetGraphicItem('✦ MINIMAL EMBLEM', '✦'),
          ],
        );
      case 'elements':
        return ListView(
          children: [
            _shapeBtn(ShapeType.circle, 'Circle', Icons.circle_outlined),
            const SizedBox(height: 10),
            _shapeBtn(ShapeType.square, 'Square', Icons.square_outlined),
            const SizedBox(height: 10),
            _shapeBtn(ShapeType.rectangle, 'Rectangle', Icons.rectangle_outlined),
            const SizedBox(height: 10),
            _shapeBtn(ShapeType.line, 'Line', Icons.horizontal_rule_outlined),
          ],
        );
      case 'color':
        final palette = [
          const Color(0xff1a1a1a),
          Colors.white,
          const Color(0xffd7d1c7),
          const Color(0xffe95b4d),
          const Color(0xff4a5b71),
          const Color(0xffd9ee57),
          const Color(0xff8e9aaf),
        ];
        return ListView(
          children: [
            const Text(
              'GARMENT COLOR',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: palette.map((c) {
                final sel = apparelColor == c;
                return GestureDetector(
                  onTap: () => onSelectColor(c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? const Color(0xffd9ee57) : Colors.black12,
                        width: sel ? 3 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      case 'layers':
        return ListView.builder(
          itemCount: elements.length,
          itemBuilder: (ctx, index) {
            final elem = elements[elements.length - 1 - index];
            final sel = elem.id == selectedId;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: sel ? const Color(0xffd9ee57) : Colors.white,
                border: Border.all(color: Colors.black12),
              ),
              child: ListTile(
                dense: true,
                title: Text(
                  elem.type == ElementType.text
                      ? 'Text: "${elem.content}"'
                      : elem.type == ElementType.shape
                          ? 'Shape: ${elem.shapeType.name}'
                          : 'Image Element',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: sel ? Colors.black : Colors.black87,
                  ),
                ),
                onTap: () => onSelectElement(elem.id),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 14),
                      onPressed: () => onMoveLayer(elem.id, true),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 14),
                      onPressed: () => onMoveLayer(elem.id, false),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 14),
                      onPressed: () => onDeleteElement(elem.id),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      default:
        return const SizedBox();
    }
  }

  Widget _actionBtn(String label, VoidCallback onTap) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xff181a18),
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _presetGraphicItem(String title, String symbol) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        onPressed: () => onAddText(symbol),
        child: Text(title, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  Widget _shapeBtn(ShapeType shape, String label, IconData icon) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: () => onAddShape(shape),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _InteractiveElement extends StatefulWidget {
  const _InteractiveElement({
    super.key,
    required this.element,
    required this.isSelected,
    required this.onSelect,
    required this.onUpdate,
    required this.onDelete,
    required this.onForward,
    required this.onBackward,
  });

  final DesignElement element;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onForward;
  final VoidCallback onBackward;

  @override
  State<_InteractiveElement> createState() => _InteractiveElementState();
}

class _InteractiveElementState extends State<_InteractiveElement> {
  @override
  Widget build(BuildContext context) {
    final elem = widget.element;

    return Positioned(
      left: elem.x,
      top: elem.y,
      child: GestureDetector(
        onTap: widget.onSelect,
        onPanUpdate: (details) {
          setState(() {
            elem.x += details.delta.dx;
            elem.y += details.delta.dy;
          });
          widget.onUpdate();
        },
        child: Transform.rotate(
          angle: elem.rotation * math.pi / 180,
          child: Transform.scale(
            scale: elem.scale,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.isSelected
                          ? const Color(0xffd9ee57)
                          : Colors.transparent,
                      width: 1.8,
                    ),
                  ),
                  child: _buildBody(elem),
                ),
                if (widget.isSelected) ...[
                  // Corner resize handle
                  Positioned(
                    right: -8,
                    bottom: -8,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          elem.scale = (elem.scale + details.delta.dx * 0.01)
                              .clamp(0.4, 3.5);
                        });
                        widget.onUpdate();
                      },
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Color(0xffd9ee57),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 4)
                          ],
                        ),
                        child: const Icon(Icons.aspect_ratio,
                            size: 10, color: Colors.black),
                      ),
                    ),
                  ),
                  // Top rotation handle
                  Positioned(
                    top: -24,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            elem.rotation = (elem.rotation + details.delta.dx)
                                .clamp(-180.0, 180.0);
                          });
                          widget.onUpdate();
                        },
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.rotate_right,
                              size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(DesignElement elem) {
    switch (elem.type) {
      case ElementType.text:
        return Text(
          elem.content,
          textAlign: elem.textAlign,
          style: TextStyle(
            color: elem.color,
            fontSize: elem.fontSize,
            fontWeight: elem.fontWeight,
            letterSpacing: 1.2,
          ),
        );
      case ElementType.shape:
        switch (elem.shapeType) {
          case ShapeType.circle:
            return Container(
              width: elem.width,
              height: elem.height,
              decoration: BoxDecoration(
                color: elem.color,
                shape: BoxShape.circle,
              ),
            );
          case ShapeType.square:
          case ShapeType.rectangle:
            return Container(
              width: elem.width,
              height: elem.shapeType == ShapeType.square
                  ? elem.width
                  : elem.height,
              color: elem.color,
            );
          case ShapeType.line:
            return Container(
              width: elem.width,
              height: elem.strokeWidth,
              color: elem.color,
            );
        }
      case ElementType.image:
        if (elem.imageData != null && elem.imageData!.startsWith('data:image')) {
          try {
            final base64Bytes =
                base64Decode(elem.imageData!.split(',').last);
            return Image.memory(
              base64Bytes,
              width: elem.width,
              height: elem.height,
              fit: BoxFit.contain,
            );
          } catch (_) {}
        }
        return Icon(Icons.image, size: elem.width, color: elem.color);
    }
  }
}

class _PropertiesPanel extends StatelessWidget {
  const _PropertiesPanel({
    required this.selectedElement,
    required this.apparelType,
    required this.apparelColor,
    required this.onApparelTypeChanged,
    required this.onApparelColorChanged,
    required this.onElementChanged,
    required this.onDelete,
    required this.onMoveForward,
    required this.onMoveBackward,
  });

  final DesignElement? selectedElement;
  final ApparelType apparelType;
  final Color apparelColor;
  final ValueChanged<ApparelType> onApparelTypeChanged;
  final ValueChanged<Color> onApparelColorChanged;
  final VoidCallback onElementChanged;
  final VoidCallback onDelete;
  final VoidCallback onMoveForward;
  final VoidCallback onMoveBackward;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: const Color(0xfff7f7f3),
      padding: const EdgeInsets.all(18),
      child: ListView(
        children: [
          Text(
            selectedElement == null
                ? 'GARMENT PROPERTIES'
                : 'ELEMENT PROPERTIES',
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 20),
          if (selectedElement == null) ...[
            const Text(
              'APPAREL TYPE',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ApparelType>(
              value: apparelType,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.zero),
              ),
              items: ApparelType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t.label),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) onApparelTypeChanged(val);
              },
            ),
          ] else ...[
            if (selectedElement!.type == ElementType.text) ...[
              const Text(
                'TEXT CONTENT',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextFormField(
                initialValue: selectedElement!.content,
                maxLines: 2,
                onChanged: (val) {
                  selectedElement!.content = val;
                  onElementChanged();
                },
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                ),
              ),
              const SizedBox(height: 18),
              _slider(
                label: 'FONT SIZE',
                value: selectedElement!.fontSize,
                min: 10,
                max: 72,
                display: '${selectedElement!.fontSize.round()}px',
                onChanged: (v) {
                  selectedElement!.fontSize = v;
                  onElementChanged();
                },
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'COLOR',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Colors.white,
                Colors.black,
                const Color(0xffd9ee57),
                const Color(0xffe95b4d),
                const Color(0xff4a5b71),
              ].map((c) {
                final sel = selectedElement!.color == c;
                return GestureDetector(
                  onTap: () {
                    selectedElement!.color = c;
                    onElementChanged();
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? Colors.black : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            _slider(
              label: 'SCALE',
              value: selectedElement!.scale,
              min: 0.5,
              max: 3.0,
              display: '${(selectedElement!.scale * 100).round()}%',
              onChanged: (v) {
                selectedElement!.scale = v;
                onElementChanged();
              },
            ),
            const SizedBox(height: 14),
            _slider(
              label: 'ROTATION',
              value: selectedElement!.rotation,
              min: -180,
              max: 180,
              display: '${selectedElement!.rotation.round()}°',
              onChanged: (v) {
                selectedElement!.rotation = v;
                onElementChanged();
              },
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    onPressed: onMoveForward,
                    icon: const Icon(Icons.arrow_upward, size: 14),
                    label: const Text('Forward', style: TextStyle(fontSize: 10)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    onPressed: onMoveBackward,
                    icon: const Icon(Icons.arrow_downward, size: 14),
                    label: const Text('Backward', style: TextStyle(fontSize: 10)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffe95b4d),
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Delete Element'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            Text(display, style: const TextStyle(fontSize: 10)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          activeColor: Colors.black,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
