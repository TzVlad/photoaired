import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'editor_state.dart';
import 'gemini_service.dart';

void main() {
  runApp(const PhotoEditorApp());
}

class AppColors {
  static const Color background = Color(0xFF000000);
  static const Color panel = Color(0xFF18181A);
  static const Color border = Color(0xFF28282A);
  static const Color accent = Color(0xFFFFFFFF);
  static const Color activeThumb = Color(0xFFFFFFFF);
  static const Color inactiveTrack = Color(0xFF333333);
  static const Color secondaryText = Color(0xFF9CA3AF);
}

class PhotoEditorApp extends StatelessWidget {
  const PhotoEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Photo Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.accent,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          surface: AppColors.panel,
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: AppColors.accent,
          inactiveTrackColor: AppColors.inactiveTrack,
          thumbColor: AppColors.activeThumb,
          trackHeight: 2.0,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.0, elevation: 0, pressedElevation: 0),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 14.0),
          overlayColor: Colors.transparent,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.panel,
          selectedColor: Colors.white24,
          labelStyle: const TextStyle(color: Colors.white),
          secondaryLabelStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
      home: const EditorScreen(),
    );
  }
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with TickerProviderStateMixin {
  EditorState _state = const EditorState();
  final EditorState _originalState = const EditorState();
  final TextEditingController _promptController = TextEditingController();
  final FocusNode _promptFocusNode = FocusNode();
  bool _isLoading = false;
  bool _showOriginal = false;
  bool _isTourPlaying = false;
  late TabController _tabController;
  
  File? _currentImageFile;
  Uint8List? _imageBytes;

  final List<EditorState> _undoStack = [];
  final List<EditorState> _redoStack = [];
  XFile? _referenceImage;
  final GlobalKey _previewGlobalKey = GlobalKey();
  
  late final GeminiService _geminiService = GeminiService('AQ.Ab8RN6Kztm9E0SzF9S6AXTSL8WotBaTPj6faoA7qKIJv8LnRQw');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _promptController.dispose();
    _promptFocusNode.dispose();
    super.dispose();
  }

  void _resetState() {
    _state = const EditorState();
    _undoStack.clear();
    _redoStack.clear();
    _referenceImage = null;
  }

  void _closeImage() {
    setState(() {
      _currentImageFile = null;
      _imageBytes = null;
      _resetState();
    });
  }

  Future<void> _selectImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, maxWidth: 2048, maxHeight: 2048);
    if (picked != null) {
      final file = File(picked.path);
      final bytes = await file.readAsBytes();
      setState(() {
        _currentImageFile = file;
        _imageBytes = bytes;
        _resetState();
      });
    }
  }

  Future<void> _loadDemoImage() async {
    setState(() {
      _isLoading = true;
    });
    try {
      const demoUrl = 'https://images.unsplash.com/photo-1542038784456-1ea8e935640e?q=80&w=1000';
      final response = await http.get(Uri.parse(demoUrl));
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/temp_demo.jpg');
        await file.writeAsBytes(response.bodyBytes);
        setState(() {
          _currentImageFile = file;
          _imageBytes = response.bodyBytes;
          _resetState();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Помилка завантаження демо: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _pushUndoState() {
    _undoStack.add(_state);
    if (_undoStack.length > 30) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _redoStack.add(_state);
      _state = _undoStack.removeLast();
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(_state);
      _state = _redoStack.removeLast();
    });
  }

  Future<void> _exportImage() async {
    try {
      final boundary = _previewGlobalKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      
      // Request access to save photos
      bool hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        hasAccess = await Gal.requestAccess(toAlbum: true);
      }
      if (!hasAccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Access denied')));
        }
        return;
      }

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes != null) {
        await Gal.putImageBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo saved to gallery')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    }
  }

  Future<void> _pickReferenceImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024);
    if (picked != null) {
      setState(() {
        _referenceImage = picked;
      });
    }
  }

  List<double> _buildColorMatrix(EditorState state) {
    // 1. Експозиція та контраст
    final double c = state.contrast;
    final double t = (1.0 - c) * 128.0;
    final double e = state.exposure * 128.0;

    // 2. Тональний діапазон (Whites, Blacks, Highlights, Shadows)
    // Імітація через комбінований зсув рівнів чорного, білого та півтонів
    final double wShift = state.whites * 40.0;
    final double bShift = state.blacks * 40.0;
    final double hShift = state.highlights * 35.0;
    final double shShift = state.shadows * 35.0;
    final double lumaOffset = e + t + wShift + bShift + hShift + shShift;

    // 3. Насиченість та Vibrance
    // Vibrance підсилює загальну насиченість із захистом від перепалу
    final double effectiveSat = (state.saturation * (1.0 + state.vibrance * 0.4)).clamp(0.0, 3.0);
    final double invS = 1.0 - effectiveSat;
    const double rW = 0.2126;
    const double gW = 0.7152;
    const double bW = 0.0722;

    final double rR = invS * rW + effectiveSat;
    final double rG = invS * gW;
    final double rB = invS * bW;

    final double gR = invS * rW;
    final double gG = invS * gW + effectiveSat;
    final double gB = invS * bW;

    final double bR = invS * rW;
    final double bG = invS * gW;
    final double bB = invS * bW + effectiveSat;

    // 4. White Balance (Температура та Тінт)
    final double temp = state.temperature * 45.0;
    final double tint = state.tint * 45.0;

    // 5. Color Grading (Split Toning через Hue тіней та світла)
    double shadowR = 0, shadowG = 0, shadowB = 0;
    if (state.colorGradingShadowHue > 0) {
      final double radS = state.colorGradingShadowHue * 3.1415926535 / 180.0;
      shadowR = 15.0 * math.cos(radS);
      shadowG = 15.0 * math.sin(radS);
      shadowB = -15.0 * math.cos(radS);
    }

    double highlightR = 0, highlightG = 0, highlightB = 0;
    if (state.colorGradingHighlightHue > 0) {
      final double radH = state.colorGradingHighlightHue * 3.1415926535 / 180.0;
      highlightR = 12.0 * math.cos(radH);
      highlightG = 12.0 * math.sin(radH);
      highlightB = -12.0 * math.cos(radH);
    }

    // Підсумкове зведення в ColorFilter.matrix (4x5)
    return [
      rR * c, rG * c, rB * c, 0, lumaOffset + temp + tint + shadowR + highlightR,
      gR * c, gG * c, gB * c, 0, lumaOffset - tint + shadowG + highlightG,
      bR * c, bG * c, bB * c, 0, lumaOffset - temp + shadowB + highlightB,
      0,      0,      0,      1, 0,
    ];
  }

  void _updateState(EditorState newState) {
    setState(() {
      _state = newState;
    });
  }

  bool _hasLightDelta(EditorState a, EditorState b) {
    return (a.exposure - b.exposure).abs() > 0.001 ||
           (a.contrast - b.contrast).abs() > 0.001 ||
           (a.highlights - b.highlights).abs() > 0.001 ||
           (a.shadows - b.shadows).abs() > 0.001 ||
           (a.whites - b.whites).abs() > 0.001 ||
           (a.blacks - b.blacks).abs() > 0.001;
  }

  bool _hasColorDelta(EditorState a, EditorState b) {
    return (a.temperature - b.temperature).abs() > 0.001 ||
           (a.tint - b.tint).abs() > 0.001 ||
           (a.saturation - b.saturation).abs() > 0.001 ||
           (a.vibrance - b.vibrance).abs() > 0.001 ||
           (a.colorGradingShadowHue - b.colorGradingShadowHue).abs() > 0.001 ||
           (a.colorGradingHighlightHue - b.colorGradingHighlightHue).abs() > 0.001;
  }

  bool _hasDetailDelta(EditorState a, EditorState b) {
    return (a.clarity - b.clarity).abs() > 0.001 ||
           (a.sharpness - b.sharpness).abs() > 0.001 ||
           (a.grain - b.grain).abs() > 0.001;
  }

  EditorState _mergeTabState(EditorState current, EditorState target, int tabIndex) {
    if (tabIndex == 0) {
      return current.copyWith(
        exposure: target.exposure,
        contrast: target.contrast,
        highlights: target.highlights,
        shadows: target.shadows,
        whites: target.whites,
        blacks: target.blacks,
      );
    } else if (tabIndex == 1) {
      return current.copyWith(
        temperature: target.temperature,
        tint: target.tint,
        saturation: target.saturation,
        vibrance: target.vibrance,
        colorGradingShadowHue: target.colorGradingShadowHue,
        colorGradingHighlightHue: target.colorGradingHighlightHue,
      );
    } else if (tabIndex == 2) {
      return current.copyWith(
        clarity: target.clarity,
        sharpness: target.sharpness,
        grain: target.grain,
      );
    } else if (tabIndex == 3) {
      return current.copyWith(
        masks: target.masks,
        selectedMaskIndex: target.selectedMaskIndex,
      );
    }
    return current;
  }

  Future<void> _animateStateTransition({
    required EditorState from,
    required EditorState to,
    required Duration duration,
    required Curve curve,
  }) async {
    final controller = AnimationController(vsync: this, duration: duration);
    final curvedAnim = CurvedAnimation(parent: controller, curve: curve);

    controller.addListener(() {
      if (mounted) {
        setState(() {
          _state = from.lerpTo(to, curvedAnim.value);
        });
      }
    });

    await controller.forward();
    controller.dispose();
  }

  Future<void> _runSynchronizedTour(EditorState initialState, EditorState finalTargetState) async {
    if (!mounted) return;
    setState(() => _isTourPlaying = true);

    EditorState progressingState = initialState;

    final steps = <int>[];
    if (_hasLightDelta(initialState, finalTargetState)) steps.add(0);
    if (_hasColorDelta(initialState, finalTargetState)) steps.add(1);
    if (_hasDetailDelta(initialState, finalTargetState)) steps.add(2);
    if (initialState.masks.length != finalTargetState.masks.length) steps.add(3);

    debugPrint('[AI Pipeline] Detected changed tabs: $steps');

    try {
      if (steps.isEmpty) {
        if (mounted) {
          setState(() {
            _state = finalTargetState;
          });
        }
        return;
      }

      for (final tabIndex in steps) {
        if (!mounted) return;
        
        _tabController.animateTo(tabIndex);
        await Future.delayed(const Duration(milliseconds: 60));

        if (!mounted) return;
        final stepTargetState = _mergeTabState(progressingState, finalTargetState, tabIndex);

        await _animateStateTransition(
          from: progressingState,
          to: stepTargetState,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );

        progressingState = stepTargetState;
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 120));
      }
    } finally {
      if (mounted) {
        setState(() {
          _state = finalTargetState;
          _isTourPlaying = false;
        });
      }
    }
  }

  Future<void> _applyAI() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    
    if (_imageBytes == null && _currentImageFile != null) {
      _imageBytes = await _currentImageFile!.readAsBytes();
    }
    if (_imageBytes == null) return;

    _promptFocusNode.unfocus();

    setState(() {
      _isLoading = true;
    });

    try {
      final referenceBytes = _referenceImage != null ? await _referenceImage!.readAsBytes() : null;
      final newState = await _geminiService.processPrompt(
        prompt: prompt,
        targetImageBytes: _imageBytes!,
        referenceImageBytes: referenceBytes,
        currentState: _state,
      );
      
      if (newState != null) {
        _pushUndoState();
        
        final animStartState = _state;
        final animTargetState = newState;
        
        await _runSynchronizedTour(animStartState, animTargetState);
      }
    } catch (e, stackTrace) {
      debugPrint('[ERROR] Execution Exception: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI Processing Error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _isEdited(int index) {
    if (index == 0) {
      return _state.exposure != 0 || _state.contrast != 1.0 || _state.highlights != 0 || _state.shadows != 0 || _state.whites != 0 || _state.blacks != 0;
    } else if (index == 1) {
      return _state.temperature != 0 || _state.tint != 0 || _state.saturation != 1.0 || _state.vibrance != 0 || _state.colorGradingShadowHue != 0 || _state.colorGradingHighlightHue != 0;
    } else if (index == 2) {
      return _state.clarity != 0 || _state.sharpness != 0 || _state.grain != 0;
    } else if (index == 3) {
      return _state.masks.isNotEmpty;
    }
    return false;
  }

  Widget _buildPillTabs() {
    final tabs = ['Light', 'Color', 'Detail', 'Mask'];
    return Container(
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(tabs.length, (index) {
          final isActive = _tabController.index == index;
          final isEdited = _isEdited(index);
          return GestureDetector(
            onTap: () => _tabController.animateTo(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: isActive ? Colors.white : Colors.white.withAlpha(20),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tabs[index],
                    style: TextStyle(
                      color: isActive ? Colors.black : Colors.white,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  if (isEdited) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive ? Colors.black : Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentImageFile == null) {
      return _buildImportScreen();
    }

    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            EditorTopBar(
              onClose: _closeImage,
              onShowOriginalDown: () => setState(() => _showOriginal = true),
              onShowOriginalUp: () => setState(() => _showOriginal = false),
              canUndo: _undoStack.isNotEmpty,
              canRedo: _redoStack.isNotEmpty,
              onUndo: _undo,
              onRedo: _redo,
              onExport: _exportImage,
            ),
            Expanded(
              child: ClipRect(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: RepaintBoundary(
                      key: _previewGlobalKey,
                      child: Stack(
                        fit: StackFit.loose,
                        children: [
                        ColorFiltered(
                          colorFilter: ColorFilter.matrix(_buildColorMatrix(_showOriginal ? _originalState : _state)),
                          child: Image.file(
                            _currentImageFile!,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => const Center(
                              child: Text('Помилка завантаження фото', style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ),
                        if (!_showOriginal)
                          Positioned.fill(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return GestureDetector(
                                  onPanUpdate: (details) {
                                    if (_state.selectedMaskIndex >= 0 && _state.selectedMaskIndex < _state.masks.length && _tabController.index == 3) {
                                      final width = constraints.maxWidth;
                                      final height = constraints.maxHeight;
                                      double newX = (details.localPosition.dx / width).clamp(0.0, 1.0);
                                      double newY = (details.localPosition.dy / height).clamp(0.0, 1.0);
                                      final activeMask = _state.masks[_state.selectedMaskIndex];
                                      _updateState(_state.updateActiveMask(activeMask.copyWith(centerX: newX, centerY: newY)));
                                    }
                                  },
                                  child: CustomPaint(
                                    size: Size.infinite,
                                    painter: MaskPainter(_state, isMaskTabActive: _tabController.index == 3),
                                  ),
                                );
                              }
                            ),
                          ),
                      ],
                    ),
                    ),
                  ),
                ),
              ),
            ),
            
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: isKeyboardOpen
                      ? const SizedBox(width: double.infinity, height: 0)
                      : IgnorePointer(
                          ignoring: _isTourPlaying,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildPillTabs(),
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 8.0),
                                decoration: BoxDecoration(
                                  color: AppColors.panel,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: AppColors.border, width: 1),
                                ),
                                child: SizedBox(
                                  height: 220,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    transitionBuilder: (Widget child, Animation<double> animation) {
                                      return FadeTransition(opacity: animation, child: child);
                                    },
                                    child: _buildCurrentPanel(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                _buildPromptBar(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border, width: 1),
                  ),
                  child: const Icon(Icons.photo_library_outlined, size: 36, color: Colors.white),
                ),
                const SizedBox(height: 24),
                const Text(
                  'AI Photo Editor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose a photo from your device or camera to start editing',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 40),
                if (_isLoading)
                  const CircularProgressIndicator(color: Colors.white)
                else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                      elevation: 0,
                    ),
                    onPressed: () => _selectImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library, size: 20),
                    label: const Text(
                      'Select from Gallery',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.border),
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                    ),
                    onPressed: () => _selectImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt, size: 20),
                    label: const Text(
                      'Take a Photo',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.secondaryText,
                    ),
                    onPressed: _loadDemoImage,
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: const Text(
                      'Спробувати демо-кадр',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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

  Widget _buildCurrentPanel() {
    switch (_tabController.index) {
      case 0:
        return AdjustControlPanel(key: const ValueKey(0), state: _state, onChanged: _updateState, onChangeStart: _pushUndoState);
      case 1:
        return ColorControlPanel(key: const ValueKey(1), state: _state, onChanged: _updateState, onChangeStart: _pushUndoState);
      case 2:
        return DetailControlPanel(key: const ValueKey(2), state: _state, onChanged: _updateState, onChangeStart: _pushUndoState);
      case 3:
        return MaskControlPanel(key: const ValueKey(3), state: _state, onChanged: _updateState, onChangeStart: _pushUndoState);
      default:
        return const SizedBox.shrink(key: ValueKey(-1));
    }
  }

  Widget _buildPromptBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        color: AppColors.background,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFF222222),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.attach_file, color: Colors.grey, size: 18),
                onPressed: _pickReferenceImage,
              ),
            ),
            if (_referenceImage != null)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(_referenceImage!.path),
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: -12,
                      right: -12,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _referenceImage = null),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 10, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _promptController,
                focusNode: _promptFocusNode,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'cinematic moody warm low-key...',
                  hintStyle: TextStyle(color: Color(0xFF666666), fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              )
            else
              GestureDetector(
                onTap: _applyAI,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Apply',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class EditorTopBar extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onShowOriginalDown;
  final VoidCallback onShowOriginalUp;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onExport;

  const EditorTopBar({
    super.key, 
    required this.onClose,
    required this.onShowOriginalDown, 
    required this.onShowOriginalUp,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.close, color: Colors.white, size: 22),
            onPressed: onClose,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40),
                icon: Icon(Icons.undo, size: 20, color: canUndo ? Colors.white : const Color(0xFF3A3A3C)),
                onPressed: canUndo ? onUndo : null,
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40),
                icon: Icon(Icons.redo, size: 20, color: canRedo ? Colors.white : const Color(0xFF3A3A3C)),
                onPressed: canRedo ? onRedo : null,
              ),
              GestureDetector(
                onTapDown: (_) => onShowOriginalDown(),
                onTapUp: (_) => onShowOriginalUp(),
                onTapCancel: () => onShowOriginalUp(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Icon(Icons.visibility_outlined, color: Color(0xFF8E8E93), size: 22),
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: onExport,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Export',
                style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildEditorSlider(String label, double value, double min, double max, double defaultValue, void Function(double) onChanged, void Function(double)? onChangeStart) {
  final safeValue = value.clamp(min, max);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
            Text(
              safeValue.toStringAsFixed(2), 
              style: const TextStyle(
                color: Colors.white70, 
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()]
              )
            ),
          ],
        ),
        Slider(
          value: safeValue,
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeStart: onChangeStart,
        ),
      ],
    ),
  );
}

class AdjustControlPanel extends StatelessWidget {
  final EditorState state;
  final ValueChanged<EditorState> onChanged;
  final VoidCallback onChangeStart;

  const AdjustControlPanel({super.key, required this.state, required this.onChanged, required this.onChangeStart});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Column(
          children: [
            _buildEditorSlider('Exposure', state.exposure, -2.0, 2.0, 0.0, (v) => onChanged(state.copyWith(exposure: v)), (_) => onChangeStart()),
            _buildEditorSlider('Contrast', state.contrast, 0.5, 2.0, 1.0, (v) => onChanged(state.copyWith(contrast: v)), (_) => onChangeStart()),
            _buildEditorSlider('Highlights', state.highlights, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(highlights: v)), (_) => onChangeStart()),
            _buildEditorSlider('Shadows', state.shadows, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(shadows: v)), (_) => onChangeStart()),
            _buildEditorSlider('Whites', state.whites, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(whites: v)), (_) => onChangeStart()),
            _buildEditorSlider('Blacks', state.blacks, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(blacks: v)), (_) => onChangeStart()),
          ],
        ),
      ),
    );
  }
}

class ColorControlPanel extends StatelessWidget {
  final EditorState state;
  final ValueChanged<EditorState> onChanged;
  final VoidCallback onChangeStart;

  const ColorControlPanel({super.key, required this.state, required this.onChanged, required this.onChangeStart});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Column(
          children: [
            _buildEditorSlider('Temperature', state.temperature, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(temperature: v)), (_) => onChangeStart()),
            _buildEditorSlider('Tint', state.tint, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(tint: v)), (_) => onChangeStart()),
            _buildEditorSlider('Saturation', state.saturation, 0.0, 2.0, 1.0, (v) => onChanged(state.copyWith(saturation: v)), (_) => onChangeStart()),
            _buildEditorSlider('Vibrance', state.vibrance, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(vibrance: v)), (_) => onChangeStart()),
            _buildEditorSlider('Color Grading Shadow Hue', state.colorGradingShadowHue, 0.0, 360.0, 0.0, (v) => onChanged(state.copyWith(colorGradingShadowHue: v)), (_) => onChangeStart()),
            _buildEditorSlider('Color Grading Highlight Hue', state.colorGradingHighlightHue, 0.0, 360.0, 0.0, (v) => onChanged(state.copyWith(colorGradingHighlightHue: v)), (_) => onChangeStart()),
          ],
        ),
      ),
    );
  }
}

class DetailControlPanel extends StatelessWidget {
  final EditorState state;
  final ValueChanged<EditorState> onChanged;
  final VoidCallback onChangeStart;

  const DetailControlPanel({super.key, required this.state, required this.onChanged, required this.onChangeStart});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Column(
          children: [
            _buildEditorSlider('Clarity', state.clarity, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(clarity: v)), (_) => onChangeStart()),
            _buildEditorSlider('Sharpness', state.sharpness, 0.0, 1.0, 0.0, (v) => onChanged(state.copyWith(sharpness: v)), (_) => onChangeStart()),
            _buildEditorSlider('Grain', state.grain, 0.0, 1.0, 0.0, (v) => onChanged(state.copyWith(grain: v)), (_) => onChangeStart()),
          ],
        ),
      ),
    );
  }
}

class MaskControlPanel extends StatelessWidget {
  final EditorState state;
  final ValueChanged<EditorState> onChanged;
  final VoidCallback onChangeStart;

  const MaskControlPanel({super.key, required this.state, required this.onChanged, required this.onChangeStart});

  @override
  Widget build(BuildContext context) {
    if (state.masks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.format_shapes, size: 28, color: Color(0xFF666666)),
            const SizedBox(height: 12),
            const Text('No active masks', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                final newMask = AdjustmentMask(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: 'Mask 1',
                );
                onChanged(state.addMask(newMask));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text('Add Mask', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            children: [
              if (state.masks.length < 4)
                ActionChip(
                  label: const Text('+ New', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white)),
                  backgroundColor: Colors.white.withAlpha(25),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onPressed: () {
                    final newMask = AdjustmentMask(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: 'Mask ${state.masks.length + 1}',
                    );
                    onChanged(state.addMask(newMask));
                  },
                ),
              if (state.masks.length < 4) const SizedBox(width: 8),
              ...List.generate(state.masks.length, (index) {
                final mask = state.masks[index];
                final isActive = index == state.selectedMaskIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: InputChip(
                    label: Text(mask.name, style: TextStyle(fontSize: 12, color: isActive ? Colors.black : Colors.white, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal)),
                    selected: isActive,
                    showCheckmark: false,
                    selectedColor: Colors.white,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: isActive ? Colors.white : AppColors.border, width: isActive ? 0.0 : 1.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    deleteIcon: Icon(Icons.close, size: 14, color: isActive ? Colors.black : Colors.white54),
                    onSelected: (bool selected) {
                      onChanged(state.selectMask(index));
                    },
                    onDeleted: () {
                      onChanged(state.removeMask(index));
                    },
                  ),
                );
              }),
            ],
          ),
        ),
        
        Expanded(
          child: (state.selectedMaskIndex >= 0 && state.selectedMaskIndex < state.masks.length)
              ? SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Text('Show Overlay', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    height: 32,
                                    child: FittedBox(
                                      fit: BoxFit.fill,
                                      child: Switch(
                                        value: state.showMaskOverlay,
                                        activeThumbColor: Colors.black,
                                        activeTrackColor: Colors.white,
                                        inactiveThumbColor: Colors.white,
                                        inactiveTrackColor: Colors.grey.shade800,
                                        onChanged: (v) => onChanged(state.copyWith(showMaskOverlay: v)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Text('Invert', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    height: 32,
                                    child: FittedBox(
                                      fit: BoxFit.fill,
                                      child: Switch(
                                        value: state.masks[state.selectedMaskIndex].isInverted,
                                        activeThumbColor: Colors.black,
                                        activeTrackColor: Colors.white,
                                        inactiveThumbColor: Colors.white,
                                        inactiveTrackColor: Colors.grey.shade800,
                                        onChanged: (v) {
                                          final m = state.masks[state.selectedMaskIndex];
                                          onChanged(state.updateActiveMask(m.copyWith(isInverted: v)));
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildEditorSlider('Local Exposure', state.masks[state.selectedMaskIndex].exposure, -1.0, 1.0, 0.0, (v) {
                          final m = state.masks[state.selectedMaskIndex];
                          onChanged(state.updateActiveMask(m.copyWith(exposure: v)));
                        }, (_) => onChangeStart()),
                        _buildEditorSlider('Radius', state.masks[state.selectedMaskIndex].radius, 0.05, 1.0, 0.5, (v) {
                          final m = state.masks[state.selectedMaskIndex];
                          onChanged(state.updateActiveMask(m.copyWith(radius: v)));
                        }, (_) => onChangeStart()),
                        _buildEditorSlider('Feather', state.masks[state.selectedMaskIndex].feather, 0.05, 1.0, 0.5, (v) {
                          final m = state.masks[state.selectedMaskIndex];
                          onChanged(state.updateActiveMask(m.copyWith(feather: v)));
                        }, (_) => onChangeStart()),
                      ],
                    ),
                  ),
                )
              : const Center(
                  child: Text('Select a mask', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
        ),
      ],
    );
  }
}

class MaskPainter extends CustomPainter {
  final EditorState state;
  final bool isMaskTabActive;
  MaskPainter(this.state, {this.isMaskTabActive = true});

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < state.masks.length; i++) {
      final mask = state.masks[i];
      if (mask.exposure == 0) continue;

      final center = Offset(size.width * mask.centerX, size.height * mask.centerY);
      final maxDim = size.width > size.height ? size.width : size.height;
      final maskRadius = maxDim * mask.radius;
      
      double stop = 1.0 - mask.feather;
      stop = stop.clamp(0.0, 0.999);

      final rect = Rect.fromCenter(
        center: center,
        width: maskRadius * 2,
        height: maskRadius * 2,
      );

      final color = mask.exposure > 0 ? Colors.white : Colors.black;
      final opacity = mask.exposure.abs().clamp(0.0, 1.0);
      
      List<Color> colors;
      List<double> stops;
      if (mask.isInverted) {
        colors = [color.withAlpha(0), color.withAlpha(0), color.withValues(alpha: opacity)];
        stops = [0.0, stop, 1.0];
      } else {
        colors = [color.withValues(alpha: opacity), color.withAlpha(0)];
        stops = [stop, 1.0];
      }

      final paint = Paint()
        ..blendMode = BlendMode.softLight
        ..shader = RadialGradient(
          colors: colors,
          stops: stops,
        ).createShader(rect);

      if (mask.isInverted) {
        canvas.drawRect(Offset.zero & size, paint);
      } else {
        canvas.drawRect(rect, paint);
      }
    }

    if (isMaskTabActive && state.showMaskOverlay && state.selectedMaskIndex >= 0 && state.selectedMaskIndex < state.masks.length) {
      final mask = state.masks[state.selectedMaskIndex];
      final center = Offset(size.width * mask.centerX, size.height * mask.centerY);
      final maxDim = size.width > size.height ? size.width : size.height;
      final maskRadius = maxDim * mask.radius;
      
      final rect = Rect.fromCenter(
        center: center,
        width: maskRadius * 2,
        height: maskRadius * 2,
      );

      final redPaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
        
      canvas.drawOval(rect, redPaint);
    }
  }

  @override
  bool shouldRepaint(covariant MaskPainter oldDelegate) => true;
}

