import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

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
  final FocusNode _focusNode = FocusNode();

  List<DesignElement> _elements = [];
  String? _selectedElementId;
  ApparelType _apparelType = ApparelType.tshirt;
  Color _apparelColor = const Color(0xff181a18);

  // Colorways state
  List<GarmentColorway> _colorways = [];
  String _activeColorwayId = '';

  // Studio canvas & controls state
  double _zoomLevel = 1.0;
  bool _studioMode = false;
  bool _showGuides = true;
  bool _showGrid = false;
  bool _snapActiveX = false;
  bool _snapActiveY = false;
  bool _isTransparentExportMode = false;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _isDirty = false;
  String _activeTab = 'text'; // 'text', 'image', 'elements', 'color', 'layers', 'align'

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

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDesignState() async {
    setState(() => _isLoading = true);

    String? jsonStr = widget.project.designData;

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

        if (data['colorways'] is List && (data['colorways'] as List).isNotEmpty) {
          _colorways = (data['colorways'] as List)
              .map((c) => GarmentColorway.fromJson(c as Map<String, dynamic>))
              .toList();
        }

        if (data['activeColorwayId'] != null) {
          _activeColorwayId = data['activeColorwayId'].toString();
        }

        if (data['elements'] is List) {
          _elements = (data['elements'] as List)
              .map((e) => DesignElement.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (e) {
        debugPrint('Error parsing designData: $e');
      }
    }

    // Initialize colorways if none exists
    if (_colorways.isEmpty) {
      _colorways = [
        GarmentColorway(
          id: 'c_primary',
          name: 'Primary Garment',
          color: _apparelColor,
          isPrimary: true,
        ),
        GarmentColorway(id: 'c_cream', name: 'Vintage Cream', color: const Color(0xfff3f0e6)),
        GarmentColorway(id: 'c_navy', name: 'Deep Navy', color: const Color(0xff1c2538)),
        GarmentColorway(id: 'c_heather', name: 'Heather Grey', color: const Color(0xff94979e)),
      ];
      _activeColorwayId = 'c_primary';
    } else if (_activeColorwayId.isEmpty) {
      _activeColorwayId = _colorways.first.id;
    }

    // Align active colorway color
    final active = _colorways.firstWhere(
      (c) => c.id == _activeColorwayId,
      orElse: () => _colorways.first,
    );
    _apparelColor = active.color;

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
      activeColorwayId: _activeColorwayId,
      colorways: _colorways.map((c) => c.clone()).toList(),
      elements: _elements.map((e) => e.clone()).toList(),
    ));
    if (_undoStack.length > 35) {
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
      activeColorwayId: _activeColorwayId,
      colorways: _colorways.map((c) => c.clone()).toList(),
      elements: _elements.map((e) => e.clone()).toList(),
    );
    _redoStack.add(current);

    final prev = _undoStack.removeLast();
    setState(() {
      _apparelColor = prev.apparelColor;
      _apparelType = prev.apparelType;
      _activeColorwayId = prev.activeColorwayId;
      _colorways = prev.colorways.map((c) => c.clone()).toList();
      _elements = prev.elements.map((e) => e.clone()).toList();
      _isDirty = true;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final current = _EditorHistoryState(
      apparelColor: _apparelColor,
      apparelType: _apparelType,
      activeColorwayId: _activeColorwayId,
      colorways: _colorways.map((c) => c.clone()).toList(),
      elements: _elements.map((e) => e.clone()).toList(),
    );
    _undoStack.add(current);

    final next = _redoStack.removeLast();
    setState(() {
      _apparelColor = next.apparelColor;
      _apparelType = next.apparelType;
      _activeColorwayId = next.activeColorwayId;
      _colorways = next.colorways.map((c) => c.clone()).toList();
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

  void _duplicateSelected() {
    final elem = _selectedElement;
    if (elem == null) return;
    _pushHistory();
    final String newId = 'elem_${DateTime.now().millisecondsSinceEpoch}';
    final clone = elem.clone();
    final dup = DesignElement(
      id: newId,
      type: clone.type,
      shapeType: clone.shapeType,
      x: (clone.x + 14).clamp(0.0, 220.0),
      y: (clone.y + 14).clamp(0.0, 260.0),
      width: clone.width,
      height: clone.height,
      scale: clone.scale,
      rotation: clone.rotation,
      color: clone.color,
      content: clone.content,
      fontFamily: clone.fontFamily,
      fontWeight: clone.fontWeight,
      textAlign: clone.textAlign,
      fontSize: clone.fontSize,
      imageData: clone.imageData,
      strokeWidth: clone.strokeWidth,
    );
    setState(() {
      _elements.add(dup);
      _selectedElementId = newId;
    });
  }

  // Quick alignment helpers for printable area (260 x 300)
  void _alignElement(String alignment) {
    final elem = _selectedElement;
    if (elem == null) return;
    _pushHistory();
    setState(() {
      final w = elem.width * elem.scale;
      final h = elem.height * elem.scale;
      switch (alignment) {
        case 'center_h':
          elem.x = (260.0 - w) / 2;
          _snapActiveX = true;
          break;
        case 'center_v':
          elem.y = (300.0 - h) / 2;
          _snapActiveY = true;
          break;
        case 'center':
          elem.x = (260.0 - w) / 2;
          elem.y = (300.0 - h) / 2;
          _snapActiveX = true;
          _snapActiveY = true;
          break;
        case 'left':
          elem.x = 8.0;
          break;
        case 'right':
          elem.x = 260.0 - w - 8.0;
          break;
        case 'top':
          elem.y = 8.0;
          break;
        case 'bottom':
          elem.y = 300.0 - h - 8.0;
          break;
      }
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _snapActiveX = false;
          _snapActiveY = false;
        });
      }
    });
  }

  void _switchColorway(GarmentColorway cw) {
    _pushHistory();
    setState(() {
      _activeColorwayId = cw.id;
      _apparelColor = cw.color;
    });
  }

  void _addColorway(String name, Color color) {
    _pushHistory();
    final newCw = GarmentColorway(
      id: 'cw_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      color: color,
    );
    setState(() {
      _colorways.add(newCw);
      _activeColorwayId = newCw.id;
      _apparelColor = color;
    });
  }

  void _optimizeContrast() {
    _pushHistory();
    final bool isDarkGarment = _apparelColor.computeLuminance() < 0.45;
    final Color targetColor = isDarkGarment ? Colors.white : const Color(0xff181a18);
    setState(() {
      for (final e in _elements) {
        if (e.type == ElementType.text) {
          e.color = targetColor;
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isDarkGarment
              ? 'Artwork contrast optimized for dark garment (White text applied)'
              : 'Artwork contrast optimized for light garment (Dark text applied)',
        ),
        backgroundColor: const Color(0xff181a18),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCtrlOrCmd = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isCtrlOrCmd && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        _redo();
      } else {
        _undo();
      }
      return KeyEventResult.handled;
    } else if (isCtrlOrCmd && event.logicalKey == LogicalKeyboardKey.keyY) {
      _redo();
      return KeyEventResult.handled;
    } else if (isCtrlOrCmd && event.logicalKey == LogicalKeyboardKey.keyS) {
      _saveDesign();
      return KeyEventResult.handled;
    } else if (isCtrlOrCmd && event.logicalKey == LogicalKeyboardKey.keyD) {
      _duplicateSelected();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_selectedElementId != null) {
        _deleteElement(_selectedElementId!);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_selectedElementId != null) {
        setState(() => _selectedElementId = null);
        return KeyEventResult.handled;
      }
    } else if (_selectedElement != null) {
      final step = isShift ? 10.0 : 1.0;
      final elem = _selectedElement!;
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _pushHistory();
        setState(() => elem.y = (elem.y - step).clamp(-80.0, 360.0));
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _pushHistory();
        setState(() => elem.y = (elem.y + step).clamp(-80.0, 360.0));
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _pushHistory();
        setState(() => elem.x = (elem.x - step).clamp(-80.0, 340.0));
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _pushHistory();
        setState(() => elem.x = (elem.x + step).clamp(-80.0, 340.0));
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
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
      'colorways': _colorways.map((c) => c.toJson()).toList(),
      'activeColorwayId': _activeColorwayId,
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
            content: Text('Saved ✓  Design & Colorways persisted to Studio Catalog'),
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

  // Print-Ready Export Profiles
  Future<void> _openExportStudio() async {
    setState(() => _isExporting = true);
    try {
      // 1. Capture Commercial Print file (Transparent background, pure artwork)
      setState(() => _isTransparentExportMode = true);
      await Future.delayed(const Duration(milliseconds: 60));
      final boundary =
          _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Canvas render boundary unavailable');
      }

      final ui.Image printImage = await boundary.toImage(pixelRatio: 4.0); // 300 DPI
      final ByteData? printByteData =
          await printImage.toByteData(format: ui.ImageByteFormat.png);
      if (printByteData == null) throw Exception('Failed to generate Print PNG');
      final Uint8List printPngBytes = printByteData.buffer.asUint8List();

      // 2. Capture E-Commerce Mockup (With garment vector and styling)
      setState(() => _isTransparentExportMode = false);
      await Future.delayed(const Duration(milliseconds: 60));
      final ui.Image mockupImage = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? mockupByteData =
          await mockupImage.toByteData(format: ui.ImageByteFormat.png);
      if (mockupByteData == null) throw Exception('Failed to generate Mockup PNG');
      final Uint8List mockupPngBytes = mockupByteData.buffer.asUint8List();

      if (mounted) {
        setState(() => _isExporting = false);
        _showExportStudioModal(printPngBytes, mockupPngBytes);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _isTransparentExportMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: ${e.toString()}')),
        );
      }
    }
  }

  void _showExportStudioModal(Uint8List printBytes, Uint8List mockupBytes) {
    showDialog(
      context: context,
      builder: (ctx) => _ExportStudioModal(
        projectName: widget.project.name,
        apparelType: _apparelType,
        activeColorway: _colorways.firstWhere(
          (c) => c.id == _activeColorwayId,
          orElse: () => _colorways.first,
        ),
        colorways: _colorways,
        elements: _elements,
        printArtworkBytes: printBytes,
        mockupBytes: mockupBytes,
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
      color: type == ElementType.text
          ? (_apparelColor.computeLuminance() < 0.45 ? Colors.white : Colors.black)
          : const Color(0xffd9ee57),
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Processing high-res image for studio print...')),
      );

      final String dataUri = await ImageHelper.processAndCompressImage(bytes);
      _addElement(ElementType.image, imageData: dataUri);
    } catch (e) {
      if (!mounted) return;
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

  void _showShortcutsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff181a18),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Row(
          children: [
            Icon(Icons.keyboard_outlined, color: Color(0xffd9ee57)),
            SizedBox(width: 10),
            Text(
              'STUDIO KEYBOARD SHORTCUTS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _shortcutRow('Ctrl / Cmd + Z', 'Undo edit'),
              _shortcutRow('Ctrl / Cmd + Y / Shift+Z', 'Redo edit'),
              _shortcutRow('Ctrl / Cmd + S', 'Save design & colorways'),
              _shortcutRow('Ctrl / Cmd + D', 'Duplicate selected element'),
              _shortcutRow('Arrow Keys', 'Nudge element by 1px'),
              _shortcutRow('Shift + Arrow Keys', 'Nudge element by 10px'),
              _shortcutRow('Delete / Backspace', 'Remove selected element'),
              _shortcutRow('Escape', 'Deselect active element'),
              _shortcutRow('F', 'Toggle Studio Mode (distraction-free)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Color(0xffd9ee57))),
          ),
        ],
      ),
    );
  }

  Widget _shortcutRow(String keys, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xff2a2c2a),
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              keys,
              style: const TextStyle(
                color: Color(0xffd9ee57),
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: const Color(0xff121312),
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
                studioMode: _studioMode,
                onToggleStudioMode: () => setState(() => _studioMode = !_studioMode),
                onBack: () async {
                  final navigator = Navigator.of(context);
                  if (_isDirty) {
                    final leave = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Unsaved Studio Changes'),
                        content: const Text(
                          'You have unsaved changes in your artwork or colorways. Leave anyway?',
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
                    if (leave == true && mounted) {
                      navigator.pop();
                    }
                  } else {
                    navigator.pop();
                  }
                },
                onUndo: _undo,
                onRedo: _redo,
                onSave: _saveDesign,
                onExport: _openExportStudio,
                onShowShortcuts: _showShortcutsDialog,
              ),
              // COLORWAYS SWATCH BAR (FEATURE 2)
              _ColorwaysBar(
                colorways: _colorways,
                activeColorwayId: _activeColorwayId,
                onSelectColorway: _switchColorway,
                onAddColorway: () => _showAddColorwayDialog(),
                onOptimizeContrast: _optimizeContrast,
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xffd9ee57)),
                      )
                    : Row(
                        children: [
                          // LEFT TOOLS NAVIGATION (Hidden in distraction-free studio mode)
                          if (!_studioMode) ...[
                            _ToolsSidebar(
                              activeTab: _activeTab,
                              onTabChanged: (tab) => setState(() => _activeTab = tab),
                            ),
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
                              onAlign: _alignElement,
                            ),
                          ],
                          // CENTER APPAREL CANVAS
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                _focusNode.requestFocus();
                                setState(() => _selectedElementId = null);
                              },
                              child: Container(
                                color: const Color(0xff181a18),
                                child: Stack(
                                  children: [
                                    // Subtle Grid Pattern when enabled
                                    if (_showGrid)
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: _GridDotsPainter(),
                                        ),
                                      ),
                                    // Studio Canvas Center
                                    Center(
                                      child: Transform.scale(
                                        scale: _zoomLevel,
                                        child: RepaintBoundary(
                                          key: _canvasKey,
                                          child: Container(
                                            width: 540,
                                            height: 600,
                                            color: _isTransparentExportMode
                                                ? Colors.transparent
                                                : const Color(0xff222422),
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                if (!_isTransparentExportMode)
                                                  Positioned(
                                                    top: 14,
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                              horizontal: 8, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xff181a18),
                                                            borderRadius:
                                                                BorderRadius.circular(2),
                                                            border: Border.all(
                                                                color: Colors.white12),
                                                          ),
                                                          child: Text(
                                                            '${_apparelType.label.toUpperCase()} · ${_colorways.firstWhere((c) => c.id == _activeColorwayId, orElse: () => _colorways.first).name.toUpperCase()}',
                                                            style: const TextStyle(
                                                              fontSize: 9,
                                                              letterSpacing: 1.5,
                                                              color: Color(0xffd9ee57),
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ApparelMockup(
                                                  type: _apparelType,
                                                  color: _apparelColor,
                                                  large: true,
                                                  showPrintAreaBorder: !_isTransparentExportMode,
                                                  transparentGarment: _isTransparentExportMode,
                                                  showGuides: _showGuides && !_isTransparentExportMode,
                                                  snapActiveX: _snapActiveX,
                                                  snapActiveY: _snapActiveY,
                                                  child: Stack(
                                                    clipBehavior: Clip.none,
                                                    children: _elements.map((elem) {
                                                      final isSel =
                                                          elem.id == _selectedElementId;
                                                      return _InteractiveElement(
                                                        key: ValueKey(elem.id),
                                                        element: elem,
                                                        isSelected: isSel,
                                                        onSelect: () {
                                                          _focusNode.requestFocus();
                                                          setState(() =>
                                                              _selectedElementId = elem.id);
                                                        },
                                                        onUpdate: () {
                                                          _pushHistory();
                                                          // Snapping calculation
                                                          final centerElemX = elem.x +
                                                              (elem.width * elem.scale) / 2;
                                                          final centerElemY = elem.y +
                                                              (elem.height * elem.scale) / 2;

                                                          bool snapX = false;
                                                          bool snapY = false;
                                                          if ((centerElemX - 130.0).abs() < 6.0) {
                                                            elem.x = 130.0 -
                                                                (elem.width * elem.scale) / 2;
                                                            snapX = true;
                                                          }
                                                          if ((centerElemY - 150.0).abs() < 6.0) {
                                                            elem.y = 150.0 -
                                                                (elem.height * elem.scale) / 2;
                                                            snapY = true;
                                                          }
                                                          setState(() {
                                                            _snapActiveX = snapX;
                                                            _snapActiveY = snapY;
                                                          });
                                                        },
                                                        onPanEnd: () {
                                                          setState(() {
                                                            _snapActiveX = false;
                                                            _snapActiveY = false;
                                                          });
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
                                                if (!_isTransparentExportMode)
                                                  Positioned(
                                                    bottom: 12,
                                                    child: Text(
                                                      _selectedElement != null
                                                          ? 'X: ${_selectedElement!.x.round()}  Y: ${_selectedElement!.y.round()}  ·  W: ${(_selectedElement!.width * _selectedElement!.scale).round()}px  H: ${(_selectedElement!.height * _selectedElement!.scale).round()}px  ·  ROT: ${_selectedElement!.rotation.round()}°'
                                                          : 'PRESS [?] FOR SHORTCUTS · DRAG ELEMENT TO MOVE · SNAPPING ACTIVE',
                                                      style: const TextStyle(
                                                        fontSize: 9,
                                                        letterSpacing: 1.2,
                                                        color: Color(0xff888a82),
                                                        fontFamily: 'monospace',
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // FLOATING STUDIO CONTROLS (ZOOM, GUIDES, GRID)
                                    Positioned(
                                      bottom: 18,
                                      right: 18,
                                      child: _StudioHudControls(
                                        zoomLevel: _zoomLevel,
                                        showGuides: _showGuides,
                                        showGrid: _showGrid,
                                        onZoomIn: () => setState(() =>
                                            _zoomLevel = (_zoomLevel + 0.15).clamp(0.5, 2.2)),
                                        onZoomOut: () => setState(() =>
                                            _zoomLevel = (_zoomLevel - 0.15).clamp(0.5, 2.2)),
                                        onZoomReset: () => setState(() => _zoomLevel = 1.0),
                                        onToggleGuides: () =>
                                            setState(() => _showGuides = !_showGuides),
                                        onToggleGrid: () =>
                                            setState(() => _showGrid = !_showGrid),
                                      ),
                                    ),
                                    // DISTRACTION FREE TOGGLE FLOATING BADGE
                                    if (_studioMode)
                                      Positioned(
                                        top: 14,
                                        left: 14,
                                        child: FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xffd9ee57),
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                          ),
                                          onPressed: () =>
                                              setState(() => _studioMode = false),
                                          icon: const Icon(Icons.fullscreen_exit, size: 16),
                                          label: const Text('Exit Studio Mode',
                                              style: TextStyle(
                                                  fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // RIGHT PROPERTIES INSPECTOR (Hidden in distraction-free studio mode)
                          if (!_studioMode)
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
                              onAlign: _alignElement,
                              onDuplicate: _duplicateSelected,
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddColorwayDialog() {
    final nameController = TextEditingController();
    Color selectedColor = const Color(0xff2d4059);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final presets = [
            const Color(0xff181a18),
            const Color(0xfff3f0e6),
            const Color(0xff1c2538),
            const Color(0xff2e4a3d),
            const Color(0xff8c4333),
            const Color(0xff94979e),
            const Color(0xff533454),
            const Color(0xffc29b38),
          ];

          return AlertDialog(
            backgroundColor: const Color(0xff1f211f),
            title: const Text(
              'ADD GARMENT COLORWAY',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 1.2,
              ),
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Colorway Name',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Midnight Forest, Terracotta Drop',
                      hintStyle: TextStyle(color: Colors.white30),
                      border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Pick Garment Swatch',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: presets.map((c) {
                      final isChosen = selectedColor == c;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedColor = c),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isChosen ? const Color(0xffd9ee57) : Colors.white24,
                              width: isChosen ? 3 : 1,
                            ),
                          ),
                          child: isChosen
                              ? Icon(
                                  Icons.check,
                                  size: 16,
                                  color: c.computeLuminance() > 0.5
                                      ? Colors.black
                                      : Colors.white,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xffd9ee57),
                  foregroundColor: Colors.black,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                onPressed: () {
                  final name = nameController.text.trim().isNotEmpty
                      ? nameController.text.trim()
                      : 'Colorway ${_colorways.length + 1}';
                  _addColorway(name, selectedColor);
                  Navigator.pop(ctx);
                },
                child: const Text('Add Colorway'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EditorHistoryState {
  _EditorHistoryState({
    required this.apparelColor,
    required this.apparelType,
    required this.activeColorwayId,
    required this.colorways,
    required this.elements,
  });
  final Color apparelColor;
  final ApparelType apparelType;
  final String activeColorwayId;
  final List<GarmentColorway> colorways;
  final List<DesignElement> elements;
}

// ---------------------------------------------------------
// TOP BAR WITH STUDIO CONTROLS
// ---------------------------------------------------------
class _EditorTopBar extends StatelessWidget {
  const _EditorTopBar({
    required this.name,
    required this.isDirty,
    required this.canUndo,
    required this.canRedo,
    required this.isSaving,
    required this.isExporting,
    required this.studioMode,
    required this.onToggleStudioMode,
    required this.onBack,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
    required this.onExport,
    required this.onShowShortcuts,
  });

  final String name;
  final bool isDirty;
  final bool canUndo;
  final bool canRedo;
  final bool isSaving;
  final bool isExporting;
  final bool studioMode;
  final VoidCallback onToggleStudioMode;
  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onSave;
  final VoidCallback onExport;
  final VoidCallback onShowShortcuts;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xff181a18),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            tooltip: 'Back to Dashboard',
          ),
          const SizedBox(width: 8),
          const Text(
            'LA FÁBRICA',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              fontSize: 15,
            ),
          ),
          Container(
            height: 18,
            width: 1,
            color: Colors.white24,
            margin: const EdgeInsets.symmetric(horizontal: 14),
          ),
          Text(
            name,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isDirty ? const Color(0x33e95b4d) : const Color(0x33d9ee57),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              isDirty ? 'Unsaved' : 'Synced ✓',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: isDirty ? const Color(0xffe95b4d) : const Color(0xffd9ee57),
              ),
            ),
          ),
          const Spacer(),
          // Studio Mode Distraction-Free Toggle
          IconButton(
            onPressed: onToggleStudioMode,
            icon: Icon(
              studioMode ? Icons.fullscreen_exit : Icons.fullscreen,
              color: studioMode ? const Color(0xffd9ee57) : Colors.white70,
              size: 20,
            ),
            tooltip: studioMode ? 'Exit Studio Mode (F)' : 'Studio Mode (Distraction-Free)',
          ),
          IconButton(
            onPressed: onShowShortcuts,
            icon: const Icon(Icons.keyboard_outlined, color: Colors.white70, size: 20),
            tooltip: 'Keyboard Shortcuts (?)',
          ),
          IconButton(
            onPressed: canUndo ? onUndo : null,
            icon: Icon(
              Icons.undo_outlined,
              color: canUndo ? Colors.white : Colors.white24,
              size: 19,
            ),
            tooltip: 'Undo (Ctrl+Z)',
          ),
          IconButton(
            onPressed: canRedo ? onRedo : null,
            icon: Icon(
              Icons.redo_outlined,
              color: canRedo ? Colors.white : Colors.white24,
              size: 19,
            ),
            tooltip: 'Redo (Ctrl+Y)',
          ),
          const SizedBox(width: 14),
          OutlinedButton(
            onPressed: isSaving ? null : onSave,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            ),
            child: isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save Design', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: isExporting ? null : onExport,
            icon: const Icon(Icons.file_download_outlined, size: 16),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffd9ee57),
              foregroundColor: Colors.black,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            ),
            label: isExporting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Text('Export Studio',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// COLORWAYS BAR (FEATURE 2: ONE DESIGN, MULTIPLE COLORWAYS)
// ---------------------------------------------------------
class _ColorwaysBar extends StatelessWidget {
  const _ColorwaysBar({
    required this.colorways,
    required this.activeColorwayId,
    required this.onSelectColorway,
    required this.onAddColorway,
    required this.onOptimizeContrast,
  });

  final List<GarmentColorway> colorways;
  final String activeColorwayId;
  final ValueChanged<GarmentColorway> onSelectColorway;
  final VoidCallback onAddColorway;
  final VoidCallback onOptimizeContrast;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xff1e201e),
      child: Row(
        children: [
          const Icon(Icons.style_outlined, size: 16, color: Color(0xffd9ee57)),
          const SizedBox(width: 8),
          const Text(
            'COLORWAYS:',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: colorways.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (ctx, index) {
                final cw = colorways[index];
                final isActive = cw.id == activeColorwayId;
                return Center(
                  child: InkWell(
                    onTap: () => onSelectColorway(cw),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xff2d302d) : const Color(0xff161716),
                        border: Border.all(
                          color: isActive ? const Color(0xffd9ee57) : Colors.white12,
                          width: isActive ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: cw.color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24, width: 0.8),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cw.name,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              color: isActive ? Colors.white : Colors.white70,
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.check, size: 12, color: Color(0xffd9ee57)),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          OutlinedButton.icon(
            onPressed: onAddColorway,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('+ Colorway', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onOptimizeContrast,
            icon: const Icon(Icons.tonality, size: 17, color: Color(0xffd9ee57)),
            tooltip: 'Auto-Optimize Artwork Contrast for Garment',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// STUDIO HUD CONTROLS (ZOOM, ALIGN, GUIDES)
// ---------------------------------------------------------
class _StudioHudControls extends StatelessWidget {
  const _StudioHudControls({
    required this.zoomLevel,
    required this.showGuides,
    required this.showGrid,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.onToggleGuides,
    required this.onToggleGrid,
  });

  final double zoomLevel;
  final bool showGuides;
  final bool showGrid;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;
  final VoidCallback onToggleGuides;
  final VoidCallback onToggleGrid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xff181a18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onToggleGuides,
            icon: Icon(
              Icons.straighten,
              size: 16,
              color: showGuides ? const Color(0xffd9ee57) : Colors.white38,
            ),
            tooltip: 'Snapping & Center Guides',
          ),
          IconButton(
            onPressed: onToggleGrid,
            icon: Icon(
              Icons.grid_on,
              size: 16,
              color: showGrid ? const Color(0xffd9ee57) : Colors.white38,
            ),
            tooltip: 'Studio Alignment Grid',
          ),
          Container(
            height: 16,
            width: 1,
            color: Colors.white24,
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          IconButton(
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove, size: 16, color: Colors.white),
            tooltip: 'Zoom Out',
          ),
          InkWell(
            onTap: onZoomReset,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '${(zoomLevel * 100).round()}%',
                style: const TextStyle(
                  color: Color(0xffd9ee57),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onZoomIn,
            icon: const Icon(Icons.add, size: 16, color: Colors.white),
            tooltip: 'Zoom In',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// GRID DOTS PAINTER
// ---------------------------------------------------------
class _GridDotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = const Color(0x1fffffff);
    const double step = 20.0;
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------
// TOOLS SIDEBAR
// ---------------------------------------------------------
class _ToolsSidebar extends StatelessWidget {
  const _ToolsSidebar({required this.activeTab, required this.onTabChanged});
  final String activeTab;
  final ValueChanged<String> onTabChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      color: const Color(0xff181a18),
      child: Column(
        children: [
          const SizedBox(height: 12),
          _item('text', Icons.title, 'Text'),
          _item('image', Icons.image_outlined, 'Graphics'),
          _item('elements', Icons.category_outlined, 'Shapes'),
          _item('align', Icons.align_horizontal_center, 'Align'),
          _item('color', Icons.palette_outlined, 'Palette'),
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
        height: 60,
        width: double.infinity,
        color: selected ? const Color(0xffd9ee57) : Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 19,
              color: selected ? Colors.black : Colors.white70,
            ),
            const SizedBox(height: 3),
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

// ---------------------------------------------------------
// TOOL DRAWER
// ---------------------------------------------------------
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
    required this.onAlign,
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
  final ValueChanged<String> onAlign;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
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
          const SizedBox(height: 16),
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
            _actionBtn('Add Headline', () => onAddText('LA FÁBRICA')),
            const SizedBox(height: 10),
            _actionBtn('Add Subtitle', () => onAddText('STUDIO 2026')),
            const SizedBox(height: 10),
            _actionBtn('Add Editorial Body', () => onAddText('LIMITED EDITION')),
            const SizedBox(height: 10),
            _actionBtn('Add Minimalist Brandmark', () => onAddText('LF-01')),
          ],
        );
      case 'image':
        return ListView(
          children: [
            OutlinedButton.icon(
              onPressed: onUploadImage,
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Upload Artwork Image'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.black26),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'STUDIO EMBLEMS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Color(0xff777871),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _presetGraphicItem('★ STAR BADGE', '★'),
            _presetGraphicItem('⚡ LIGHTNING', '⚡'),
            _presetGraphicItem('✦ MINIMAL EMBLEM', '✦'),
            _presetGraphicItem('❖ STUDIO MOTIF', '❖'),
            _presetGraphicItem('❂ COMPASS EMBLEM', '❂'),
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
            _shapeBtn(ShapeType.line, 'Divider Line', Icons.horizontal_rule_outlined),
          ],
        );
      case 'align':
        return ListView(
          children: [
            const Text(
              'ALIGN TO PRINT AREA',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 12),
            _alignBtn('Center Horizontal', Icons.align_horizontal_center, () => onAlign('center_h')),
            const SizedBox(height: 8),
            _alignBtn('Center Vertical', Icons.align_vertical_center, () => onAlign('center_v')),
            const SizedBox(height: 8),
            _alignBtn('Center Both', Icons.filter_center_focus, () => onAlign('center')),
            const SizedBox(height: 8),
            _alignBtn('Align Left', Icons.align_horizontal_left, () => onAlign('left')),
            const SizedBox(height: 8),
            _alignBtn('Align Right', Icons.align_horizontal_right, () => onAlign('right')),
            const SizedBox(height: 8),
            _alignBtn('Align Top', Icons.vertical_align_top, () => onAlign('top')),
            const SizedBox(height: 8),
            _alignBtn('Align Bottom', Icons.vertical_align_bottom, () => onAlign('bottom')),
          ],
        );
      case 'color':
        final palette = [
          const Color(0xff181a18),
          Colors.white,
          const Color(0xfff3f0e6),
          const Color(0xff1c2538),
          const Color(0xff2e4a3d),
          const Color(0xff8c4333),
          const Color(0xff94979e),
          const Color(0xffd9ee57),
          const Color(0xffe95b4d),
        ];
        return ListView(
          children: [
            const Text(
              'QUICK PALETTE SWATCH',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
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
                          : 'Artwork Image',
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

  Widget _alignBtn(String label, IconData icon, VoidCallback onTap) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
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

// ---------------------------------------------------------
// INTERACTIVE ELEMENT (STUDIO SELECTION HANDLES + DRAG + ROTATION)
// ---------------------------------------------------------
class _InteractiveElement extends StatefulWidget {
  const _InteractiveElement({
    super.key,
    required this.element,
    required this.isSelected,
    required this.onSelect,
    required this.onUpdate,
    required this.onPanEnd,
    required this.onDelete,
    required this.onForward,
    required this.onBackward,
  });

  final DesignElement element;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onUpdate;
  final VoidCallback onPanEnd;
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
        onPanEnd: (_) => widget.onPanEnd(),
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
                // Studio Selection Handles (4 corners + top rotation stem)
                if (widget.isSelected) ...[
                  // Top rotation stalk with angle badge
                  Positioned(
                    top: -26,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            elem.rotation = (elem.rotation + details.delta.dx * 1.5)
                                .clamp(-180.0, 180.0);
                          });
                          widget.onUpdate();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black38, blurRadius: 4),
                            ],
                          ),
                          child: const Icon(Icons.rotate_right,
                              size: 13, color: Color(0xffd9ee57)),
                        ),
                      ),
                    ),
                  ),
                  // Bottom-right scale handle
                  Positioned(
                    right: -7,
                    bottom: -7,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          elem.scale = (elem.scale + details.delta.dx * 0.012)
                              .clamp(0.3, 3.8);
                        });
                        widget.onUpdate();
                      },
                      child: _handlePoint(),
                    ),
                  ),
                  // Top-left scale handle
                  Positioned(
                    left: -7,
                    top: -7,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          elem.scale = (elem.scale - details.delta.dx * 0.012)
                              .clamp(0.3, 3.8);
                        });
                        widget.onUpdate();
                      },
                      child: _handlePoint(),
                    ),
                  ),
                  // Top-right scale handle
                  Positioned(
                    right: -7,
                    top: -7,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          elem.scale = (elem.scale + details.delta.dx * 0.012)
                              .clamp(0.3, 3.8);
                        });
                        widget.onUpdate();
                      },
                      child: _handlePoint(),
                    ),
                  ),
                  // Bottom-left scale handle
                  Positioned(
                    left: -7,
                    bottom: -7,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          elem.scale = (elem.scale - details.delta.dx * 0.012)
                              .clamp(0.3, 3.8);
                        });
                        widget.onUpdate();
                      },
                      child: _handlePoint(),
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

  Widget _handlePoint() {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: const Color(0xffd9ee57),
        border: Border.all(color: Colors.black, width: 1.5),
        shape: BoxShape.rectangle,
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

// ---------------------------------------------------------
// PROPERTIES PANEL
// ---------------------------------------------------------
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
    required this.onAlign,
    required this.onDuplicate,
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
  final ValueChanged<String> onAlign;
  final VoidCallback onDuplicate;

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
                : 'ELEMENT STUDIO PROPERTIES',
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          if (selectedElement == null) ...[
            const Text(
              'APPAREL SILHOUETTE',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ApparelType>(
              initialValue: apparelType,
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
            const SizedBox(height: 20),
            const Text(
              'CANVAS SPECS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Print Area: 260 × 300 px (12" × 14")',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Resolution: 300 DPI Export Ready',
                      style: TextStyle(fontSize: 11, color: Colors.black54)),
                  SizedBox(height: 4),
                  Text('Color Engine: CMYK Emulation PNG',
                      style: TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
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
              'ARTWORK COLOR',
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
                const Color(0xfff3f0e6),
                const Color(0xffc29b38),
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
              min: 0.4,
              max: 3.5,
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
            const SizedBox(height: 18),
            const Text(
              'QUICK ALIGN',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onAlign('center_h'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('Center X', style: TextStyle(fontSize: 10)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onAlign('center_v'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('Center Y', style: TextStyle(fontSize: 10)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    ),
                    onPressed: onMoveBackward,
                    icon: const Icon(Icons.arrow_downward, size: 14),
                    label: const Text('Backward', style: TextStyle(fontSize: 10)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: onDuplicate,
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('Duplicate Element (Ctrl+D)', style: TextStyle(fontSize: 11)),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffe95b4d),
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('Delete Element', style: TextStyle(fontSize: 11)),
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
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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

// ---------------------------------------------------------
// PRINT-READY EXPORT STUDIO MODAL (FEATURE 4)
// ---------------------------------------------------------
class _ExportStudioModal extends StatefulWidget {
  const _ExportStudioModal({
    required this.projectName,
    required this.apparelType,
    required this.activeColorway,
    required this.colorways,
    required this.elements,
    required this.printArtworkBytes,
    required this.mockupBytes,
  });

  final String projectName;
  final ApparelType apparelType;
  final GarmentColorway activeColorway;
  final List<GarmentColorway> colorways;
  final List<DesignElement> elements;
  final Uint8List printArtworkBytes;
  final Uint8List mockupBytes;

  @override
  State<_ExportStudioModal> createState() => _ExportStudioModalState();
}

class _ExportStudioModalState extends State<_ExportStudioModal> {
  int _selectedTab = 0; // 0: Commercial Print PNG, 1: E-Commerce Mockup, 2: Production Tech Pack

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xff181a18),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        width: 680,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.print_outlined, color: Color(0xffd9ee57), size: 22),
                const SizedBox(width: 10),
                const Text(
                  'EXPORT STUDIO · PRODUCTION PROFILES',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Profile selector tabs
            Row(
              children: [
                _profileTab(0, 'Commercial Print (Transparent PNG)', Icons.checkroom),
                const SizedBox(width: 8),
                _profileTab(1, 'E-Commerce Visual Mockup', Icons.photo_camera_back),
                const SizedBox(width: 8),
                _profileTab(2, 'Tech Pack Spec Sheet', Icons.description_outlined),
              ],
            ),
            const SizedBox(height: 18),
            // Preview & Profile details
            if (_selectedTab == 0) _buildPrintArtworkProfile(),
            if (_selectedTab == 1) _buildMockupProfile(),
            if (_selectedTab == 2) _buildTechPackProfile(),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(color: Colors.white70)),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xffd9ee57),
                    foregroundColor: Colors.black,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: _handleDownload,
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(_selectedTab == 2 ? 'Copy Tech Pack' : 'Download Master File'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileTab(int index, String label, IconData icon) {
    final sel = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: sel ? const Color(0xff2a2c2a) : const Color(0xff141514),
            border: Border.all(
              color: sel ? const Color(0xffd9ee57) : Colors.white12,
              width: sel ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: sel ? const Color(0xffd9ee57) : Colors.white70),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    color: sel ? Colors.white : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrintArtworkProfile() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Checkerboard transparent preview
        Container(
          width: 250,
          height: 260,
          decoration: BoxDecoration(
            color: const Color(0xff222422),
            border: Border.all(color: Colors.white24),
          ),
          child: Center(
            child: Image.memory(widget.printArtworkBytes, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'DIRECT-TO-GARMENT / SCREEN PRINT PROFILE',
                style: TextStyle(
                  color: Color(0xffd9ee57),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              _specItem('Format', 'High-Res PNG (Alpha Transparency)'),
              _specItem('DPI Preset', '300 DPI Production Master (4x Canvas Buffer)'),
              _specItem('Print Dimensions', '12" × 14" (3600 × 4200 px equivalent)'),
              _specItem('Garment Background', 'Completely Transparent (Artwork Only)'),
              _specItem('Color Profile', 'sRGB CMYK-Calibrated Emulation'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xff2a2c2a),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Text(
                  '✓ Isolates artwork cleanly from garment mockup for automated send-to-print queues.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMockupProfile() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 250,
          height: 260,
          decoration: BoxDecoration(
            color: const Color(0xff222422),
            border: Border.all(color: Colors.white24),
          ),
          child: Center(
            child: Image.memory(widget.mockupBytes, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'E-COMMERCE CATALOG & STORE LOOKBOOK',
                style: TextStyle(
                  color: Color(0xffd9ee57),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              _specItem('Garment Silhouette', widget.apparelType.label),
              _specItem('Active Colorway', '${widget.activeColorway.name} (${widget.activeColorway.color.toARGB32().toRadixString(16).substring(2).toUpperCase()})'),
              _specItem('Included Variations', '${widget.colorways.length} Colorways Defined'),
              _specItem('Visual Details', 'Neck stitch, collar ribbing, drop shadow'),
              _specItem('Usage', 'Shopify, Lookbooks, Line Sheets, Instagram Drops'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xff2a2c2a),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Text(
                  '✓ Realistic fabric drape and accurate artwork scale ready for commercial listings.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTechPackProfile() {
    return Container(
      height: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff222422),
        border: Border.all(color: Colors.white24),
      ),
      child: ListView(
        children: [
          const Text(
            'APPAREL PRODUCTION TECH PACK SPECIFICATION',
            style: TextStyle(
              color: Color(0xffd9ee57),
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const Divider(color: Colors.white24, height: 20),
          _specItem('Project Name', widget.projectName),
          _specItem('Garment Silhouette', widget.apparelType.label),
          _specItem('Active Colorway', '${widget.activeColorway.name} (#${widget.activeColorway.color.toARGB32().toRadixString(16).substring(2).toUpperCase()})'),
          _specItem('Total Colorways', widget.colorways.map((c) => c.name).join(', ')),
          _specItem('Print Placement', 'Center Chest · 130mm from top collar seam'),
          _specItem('Artwork Layers', '${widget.elements.length} components'),
          const SizedBox(height: 8),
          const Text('Element Breakdown:',
              style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          ...widget.elements.map((e) => Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text(
                  '• [${e.type.name.toUpperCase()}] "${e.content}" (Font: ${e.fontSize.round()}px, Color: #${e.color.toARGB32().toRadixString(16).substring(2).toUpperCase()}, X: ${e.x.round()}, Y: ${e.y.round()})',
                  style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'monospace'),
                ),
              )),
        ],
      ),
    );
  }

  Widget _specItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  void _handleDownload() {
    final cleanName = widget.projectName.toLowerCase().replaceAll(' ', '_');
    if (_selectedTab == 0) {
      final filename = '${cleanName}_commercial_artwork_300dpi.png';
      if (kIsWeb) {
        FilePickerHelper.downloadPngWeb(widget.printArtworkBytes, filename);
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded Commercial Print PNG: $filename')),
      );
    } else if (_selectedTab == 1) {
      final filename = '${cleanName}_${widget.activeColorway.name.toLowerCase().replaceAll(' ', '_')}_mockup.png';
      if (kIsWeb) {
        FilePickerHelper.downloadPngWeb(widget.mockupBytes, filename);
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded E-Commerce Visual Mockup: $filename')),
      );
    } else {
      // Tech pack copy
      final techPackText = '''
==================================================
LA FÁBRICA APPAREL PRODUCTION TECH PACK
==================================================
Design: ${widget.projectName}
Garment Silhouette: ${widget.apparelType.label}
Primary Colorway: ${widget.activeColorway.name} (#${widget.activeColorway.color.toARGB32().toRadixString(16).substring(2).toUpperCase()})
All Colorways: ${widget.colorways.map((c) => "${c.name} (#${c.color.toARGB32().toRadixString(16).substring(2).toUpperCase()})").join(', ')}
Print Placement: Center Chest (130mm from collar)
Layers (${widget.elements.length}):
${widget.elements.map((e) => "- [${e.type.name}] ${e.content} (Size: ${e.fontSize.round()}px, Color: #${e.color.toARGB32().toRadixString(16).substring(2).toUpperCase()}, X: ${e.x.round()}, Y: ${e.y.round()})").join('\n')}
==================================================
Generated on ${DateTime.now().toIso8601String()}
''';
      Clipboard.setData(ClipboardData(text: techPackText));
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tech Pack Spec Sheet copied to Clipboard ✓')),
      );
    }
  }
}
