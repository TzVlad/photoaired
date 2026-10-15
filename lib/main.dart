import 'package:flutter/material.dart';
import 'dart:ui';
import 'editor_state.dart';
import 'gemini_service.dart';

void main() {
  runApp(const PhotoEditorApp());
}

class AppColors {
  static const Color background = Color(0xFF121212);
  static const Color panel = Color(0xFF1C1C1E);
  static const Color border = Color(0xFF2C2C2E);
  static const Color accent = Color(0xFF6366F1);
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
        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.accent,
          inactiveTrackColor: AppColors.border,
          thumbColor: Colors.white,
          trackHeight: 2.5,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0, elevation: 0, pressedElevation: 0),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
          overlayColor: AppColors.accent.withOpacity(0.15),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.panel,
          selectedColor: AppColors.accent.withOpacity(0.15),
          labelStyle: const TextStyle(color: Colors.white),
          secondaryLabelStyle: const TextStyle(color: AppColors.accent),
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

class _EditorScreenState extends State<EditorScreen> with SingleTickerProviderStateMixin {
  EditorState _state = const EditorState();
  final EditorState _originalState = const EditorState();
  final TextEditingController _promptController = TextEditingController();
  bool _isLoading = false;
  bool _showOriginal = false;
  late TabController _tabController;
  
  late final GeminiService _geminiService = GeminiService('AQ.Ab8RN6Jiqr68UTqaX58ECo-nk4aoInOXYDh04nLVirlWo164RA');

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
    super.dispose();
  }

  List<double> _buildColorMatrix(EditorState state) {
    double e = state.exposure * 255;
    double c = state.contrast;
    double t = (1.0 - c) * 128;
    double s = state.saturation;
    double temp = state.temperature * 50; 
    double tint = state.tint * 50;

    double rW = 0.2126;
    double gW = 0.7152;
    double bW = 0.0722;
    double invS = 1.0 - s;
    
    double rR = invS * rW + s;
    double rG = invS * gW;
    double rB = invS * bW;
    
    double gR = invS * rW;
    double gG = invS * gW + s;
    double gB = invS * bW;
    
    double bR = invS * rW;
    double bG = invS * gW;
    double bB = invS * bW + s;

    return [
      rR * c, rG * c, rB * c, 0, e + t + temp + tint,
      gR * c, gG * c, gB * c, 0, e + t - tint,
      bR * c, bG * c, bB * c, 0, e + t - temp,
      0, 0, 0, 1, 0,
    ];
  }

  void _updateState(EditorState newState) {
    setState(() {
      _state = newState;
    });
  }

  Future<void> _applyAI() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    final newState = await _geminiService.analyzePrompt(prompt, _state);
    
    setState(() {
      _isLoading = false;
      if (newState != null) {
        _state = newState;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            EditorTopBar(
              onShowOriginalDown: () => setState(() => _showOriginal = true),
              onShowOriginalUp: () => setState(() => _showOriginal = false),
            ),
            
            Expanded(
              child: ClipRect(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: Stack(
                      fit: StackFit.loose,
                      children: [
                        ColorFiltered(
                          colorFilter: ColorFilter.matrix(_buildColorMatrix(_showOriginal ? _originalState : _state)),
                          child: Image.network(
                            'https://images.unsplash.com/photo-1542038784456-1ea8e935640e?q=80&w=1000',
                            fit: BoxFit.contain,
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
            
            Container(
              margin: const EdgeInsets.only(top: 8.0),
              decoration: const BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: AppColors.border, width: 1)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.secondaryText.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 8),

                    SizedBox(
                      height: 220,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                        child: _buildCurrentPanel(),
                      ),
                    ),
                    
                    _buildPromptBar(),
                    
                    EditorBottomBar(tabController: _tabController),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPanel() {
    switch (_tabController.index) {
      case 0:
        return AdjustControlPanel(key: const ValueKey(0), state: _state, onChanged: _updateState);
      case 1:
        return ColorControlPanel(key: const ValueKey(1), state: _state, onChanged: _updateState);
      case 2:
        return DetailControlPanel(key: const ValueKey(2), state: _state, onChanged: _updateState);
      case 3:
        return MaskControlPanel(key: const ValueKey(3), state: _state, onChanged: _updateState);
      default:
        return const SizedBox.shrink(key: ValueKey(-1));
    }
  }

  Widget _buildPromptBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: AppColors.panel,
      child: Container(
        padding: const EdgeInsets.only(left: 14.0, right: 6.0, top: 4.0, bottom: 4.0),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppColors.accent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _promptController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Ask AI to edit...',
                  hintStyle: TextStyle(color: AppColors.secondaryText, fontSize: 13),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(right: 12.0),
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                ),
              )
            else
              GestureDetector(
                onTap: _applyAI,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class EditorTopBar extends StatelessWidget {
  final VoidCallback onShowOriginalDown;
  final VoidCallback onShowOriginalUp;

  const EditorTopBar({super.key, required this.onShowOriginalDown, required this.onShowOriginalUp});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () {},
          ),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.undo, color: AppColors.secondaryText), onPressed: () {}),
              IconButton(icon: const Icon(Icons.redo, color: AppColors.secondaryText), onPressed: () {}),
              GestureDetector(
                onTapDown: (_) => onShowOriginalDown(),
                onTapUp: (_) => onShowOriginalUp(),
                onTapCancel: () => onShowOriginalUp(),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.compare, color: Colors.white),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Export', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class EditorBottomBar extends StatelessWidget {
  final TabController tabController;

  const EditorBottomBar({super.key, required this.tabController});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.panel,
      child: TabBar(
        controller: tabController,
        isScrollable: false,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: const Color(0xFF2A2A2C),
          borderRadius: BorderRadius.circular(20),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.secondaryText,
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'Light', iconMargin: EdgeInsets.only(bottom: 4), icon: Icon(Icons.light_mode, size: 18)),
          Tab(text: 'Color', iconMargin: EdgeInsets.only(bottom: 4), icon: Icon(Icons.color_lens, size: 18)),
          Tab(text: 'Detail', iconMargin: EdgeInsets.only(bottom: 4), icon: Icon(Icons.details, size: 18)),
          Tab(text: 'Mask', iconMargin: EdgeInsets.only(bottom: 4), icon: Icon(Icons.masks, size: 18)),
        ],
      ),
    );
  }
}

Widget _buildEditorSlider(String label, double value, double min, double max, double defaultValue, void Function(double) onChanged) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2C),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                value.toStringAsFixed(2), 
                style: const TextStyle(
                  color: AppColors.secondaryText, 
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()]
                )
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class AdjustControlPanel extends StatelessWidget {
  final EditorState state;
  final ValueChanged<EditorState> onChanged;

  const AdjustControlPanel({super.key, required this.state, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Column(
          children: [
            _buildEditorSlider('Exposure', state.exposure, -2.0, 2.0, 0.0, (v) => onChanged(state.copyWith(exposure: v))),
            _buildEditorSlider('Contrast', state.contrast, 0.5, 2.0, 1.0, (v) => onChanged(state.copyWith(contrast: v))),
            _buildEditorSlider('Highlights', state.highlights, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(highlights: v))),
            _buildEditorSlider('Shadows', state.shadows, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(shadows: v))),
            _buildEditorSlider('Whites', state.whites, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(whites: v))),
            _buildEditorSlider('Blacks', state.blacks, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(blacks: v))),
          ],
        ),
      ),
    );
  }
}

class ColorControlPanel extends StatelessWidget {
  final EditorState state;
  final ValueChanged<EditorState> onChanged;

  const ColorControlPanel({super.key, required this.state, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Column(
          children: [
            _buildEditorSlider('Temperature', state.temperature, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(temperature: v))),
            _buildEditorSlider('Tint', state.tint, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(tint: v))),
            _buildEditorSlider('Saturation', state.saturation, 0.0, 2.0, 1.0, (v) => onChanged(state.copyWith(saturation: v))),
            _buildEditorSlider('Vibrance', state.vibrance, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(vibrance: v))),
            _buildEditorSlider('Color Grading Shadow Hue', state.colorGradingShadowHue, 0.0, 360.0, 0.0, (v) => onChanged(state.copyWith(colorGradingShadowHue: v))),
            _buildEditorSlider('Color Grading Highlight Hue', state.colorGradingHighlightHue, 0.0, 360.0, 0.0, (v) => onChanged(state.copyWith(colorGradingHighlightHue: v))),
          ],
        ),
      ),
    );
  }
}

class DetailControlPanel extends StatelessWidget {
  final EditorState state;
  final ValueChanged<EditorState> onChanged;

  const DetailControlPanel({super.key, required this.state, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Column(
          children: [
            _buildEditorSlider('Clarity', state.clarity, -1.0, 1.0, 0.0, (v) => onChanged(state.copyWith(clarity: v))),
            _buildEditorSlider('Sharpness', state.sharpness, 0.0, 1.0, 0.0, (v) => onChanged(state.copyWith(sharpness: v))),
            _buildEditorSlider('Grain', state.grain, 0.0, 1.0, 0.0, (v) => onChanged(state.copyWith(grain: v))),
          ],
        ),
      ),
    );
  }
}

class MaskControlPanel extends StatelessWidget {
  final EditorState state;
  final ValueChanged<EditorState> onChanged;

  const MaskControlPanel({super.key, required this.state, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (state.masks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.format_shapes, size: 28, color: AppColors.secondaryText),
            const SizedBox(height: 12),
            const Text('Немає активних масок', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.border,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () {
                final newMask = AdjustmentMask(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: 'Mask 1',
                );
                onChanged(state.addMask(newMask));
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Додати першу маску', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                  label: const Text('+ New', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  backgroundColor: AppColors.border.withOpacity(0.5),
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
                    label: Text(mask.name, style: TextStyle(fontSize: 12, color: isActive ? Colors.white : AppColors.secondaryText, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal)),
                    selected: isActive,
                    showCheckmark: false,
                    selectedColor: AppColors.accent.withOpacity(0.15),
                    backgroundColor: Colors.transparent,
                    side: BorderSide(color: isActive ? AppColors.accent : AppColors.border, width: isActive ? 1.5 : 1.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    deleteIcon: Icon(Icons.close, size: 14, color: isActive ? Colors.white : AppColors.secondaryText),
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
                                        activeColor: Colors.white,
                                        activeTrackColor: AppColors.accent,
                                        inactiveThumbColor: AppColors.secondaryText,
                                        inactiveTrackColor: AppColors.border,
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
                                        activeColor: Colors.white,
                                        activeTrackColor: AppColors.accent,
                                        inactiveThumbColor: AppColors.secondaryText,
                                        inactiveTrackColor: AppColors.border,
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
                        }),
                        _buildEditorSlider('Radius', state.masks[state.selectedMaskIndex].radius, 0.05, 1.0, 0.5, (v) {
                          final m = state.masks[state.selectedMaskIndex];
                          onChanged(state.updateActiveMask(m.copyWith(radius: v)));
                        }),
                        _buildEditorSlider('Feather', state.masks[state.selectedMaskIndex].feather, 0.05, 1.0, 0.5, (v) {
                          final m = state.masks[state.selectedMaskIndex];
                          onChanged(state.updateActiveMask(m.copyWith(feather: v)));
                        }),
                      ],
                    ),
                  ),
                )
              : const Center(
                  child: Text('Select a mask', style: TextStyle(color: AppColors.secondaryText, fontSize: 12)),
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
        colors = [color.withOpacity(0), color.withOpacity(0), color.withOpacity(opacity)];
        stops = [0.0, stop, 1.0];
      } else {
        colors = [color.withOpacity(opacity), color.withOpacity(0)];
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
        ..color = Colors.red.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
        
      canvas.drawOval(rect, redPaint);
    }
  }

  @override
  bool shouldRepaint(covariant MaskPainter oldDelegate) => true;
}
