import 'package:flutter/material.dart';
import 'editor_state.dart';
import 'gemini_service.dart';

void main() {
  runApp(const PhotoEditorApp());
}

class PhotoEditorApp extends StatelessWidget {
  const PhotoEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Photo Editor',
      theme: ThemeData.dark(),
      home: const EditorScreen(),
    );
  }
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  EditorState _state = const EditorState();
  final TextEditingController _promptController = TextEditingController();
  bool _isLoading = false;
  
  // Provide your valid Gemini API key here to test
  late final GeminiService _geminiService = GeminiService('YOUR_API_KEY');

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

  Widget _buildSlider(String label, double value, double min, double max, double defaultValue, void Function(double) onChanged) {
    return GestureDetector(
      onDoubleTap: () => onChanged(defaultValue),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(value.toStringAsFixed(2)),
              ],
            ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.50,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColorFiltered(
                    colorFilter: ColorFilter.matrix(_buildColorMatrix(_state)),
                    child: Image.network(
                      'https://images.unsplash.com/photo-1542038784456-1ea8e935640e?q=80&w=1000',
                      fit: BoxFit.cover,
                    ),
                  ),
                  GestureDetector(
                    onPanUpdate: (details) {
                      if (_state.showMaskOverlay || _state.vignetteAmount != 0) {
                        RenderBox box = context.findRenderObject() as RenderBox;
                        final size = box.size;
                        double newX = (details.localPosition.dx / size.width).clamp(0.0, 1.0);
                        double newY = (details.localPosition.dy / (size.height * 0.50)).clamp(0.0, 1.0);
                        _updateState(_state.copyWith(maskCenterX: newX, maskCenterY: newY));
                      }
                    },
                    child: CustomPaint(
                      painter: VignettePainter(_state),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: DefaultTabController(
                length: 4,
                child: Column(
                  children: [
                    const TabBar(
                      labelColor: Colors.blue,
                      unselectedLabelColor: Colors.grey,
                      isScrollable: true,
                      tabs: [
                        Tab(text: 'Light'),
                        Tab(text: 'Color'),
                        Tab(text: 'Detail'),
                        Tab(text: 'Mask'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          ListView(
                            padding: const EdgeInsets.all(8),
                            children: [
                              _buildSlider('Exposure', _state.exposure, -2.0, 2.0, 0.0, (v) => _updateState(_state.copyWith(exposure: v))),
                              _buildSlider('Contrast', _state.contrast, 0.5, 2.0, 1.0, (v) => _updateState(_state.copyWith(contrast: v))),
                              _buildSlider('Highlights', _state.highlights, -1.0, 1.0, 0.0, (v) => _updateState(_state.copyWith(highlights: v))),
                              _buildSlider('Shadows', _state.shadows, -1.0, 1.0, 0.0, (v) => _updateState(_state.copyWith(shadows: v))),
                              _buildSlider('Whites', _state.whites, -1.0, 1.0, 0.0, (v) => _updateState(_state.copyWith(whites: v))),
                              _buildSlider('Blacks', _state.blacks, -1.0, 1.0, 0.0, (v) => _updateState(_state.copyWith(blacks: v))),
                            ],
                          ),
                          ListView(
                            padding: const EdgeInsets.all(8),
                            children: [
                              _buildSlider('Temperature', _state.temperature, -1.0, 1.0, 0.0, (v) => _updateState(_state.copyWith(temperature: v))),
                              _buildSlider('Tint', _state.tint, -1.0, 1.0, 0.0, (v) => _updateState(_state.copyWith(tint: v))),
                              _buildSlider('Saturation', _state.saturation, 0.0, 2.0, 1.0, (v) => _updateState(_state.copyWith(saturation: v))),
                              _buildSlider('Vibrance', _state.vibrance, -1.0, 1.0, 0.0, (v) => _updateState(_state.copyWith(vibrance: v))),
                              _buildSlider('Color Grading Shadow Hue', _state.colorGradingShadowHue, 0.0, 360.0, 0.0, (v) => _updateState(_state.copyWith(colorGradingShadowHue: v))),
                              _buildSlider('Color Grading Highlight Hue', _state.colorGradingHighlightHue, 0.0, 360.0, 0.0, (v) => _updateState(_state.copyWith(colorGradingHighlightHue: v))),
                            ],
                          ),
                          ListView(
                            padding: const EdgeInsets.all(8),
                            children: [
                              _buildSlider('Clarity', _state.clarity, -1.0, 1.0, 0.0, (v) => _updateState(_state.copyWith(clarity: v))),
                              _buildSlider('Sharpness', _state.sharpness, 0.0, 1.0, 0.0, (v) => _updateState(_state.copyWith(sharpness: v))),
                              _buildSlider('Grain', _state.grain, 0.0, 1.0, 0.0, (v) => _updateState(_state.copyWith(grain: v))),
                            ],
                          ),
                          ListView(
                            padding: const EdgeInsets.all(8),
                            children: [
                              SwitchListTile(
                                title: const Text('Show Mask Overlay'),
                                value: _state.showMaskOverlay,
                                onChanged: (v) => _updateState(_state.copyWith(showMaskOverlay: v)),
                              ),
                              _buildSlider('Vignette Amount', _state.vignetteAmount, -1.0, 1.0, 0.0, (v) => _updateState(_state.copyWith(vignetteAmount: v))),
                              _buildSlider('Vignette Radius', _state.vignetteRadius, 0.1, 1.5, 0.8, (v) => _updateState(_state.copyWith(vignetteRadius: v))),
                              _buildSlider('Vignette Feather', _state.vignetteFeather, 0.0, 1.0, 0.6, (v) => _updateState(_state.copyWith(vignetteFeather: v))),
                              _buildSlider('Mask Center X', _state.maskCenterX, 0.0, 1.0, 0.5, (v) => _updateState(_state.copyWith(maskCenterX: v))),
                              _buildSlider('Mask Center Y', _state.maskCenterY, 0.0, 1.0, 0.5, (v) => _updateState(_state.copyWith(maskCenterY: v))),
                              _buildSlider('Mask Aspect Ratio', _state.maskAspectRatio, 0.5, 2.0, 1.0, (v) => _updateState(_state.copyWith(maskAspectRatio: v))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.black12,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attachment),
                    onPressed: () {},
                  ),
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      decoration: InputDecoration(
                        hintText: 'Enter AI prompt...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        )
                      : ElevatedButton(
                          onPressed: _applyAI,
                          child: const Text('Apply'),
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

class VignettePainter extends CustomPainter {
  final EditorState state;
  VignettePainter(this.state);

  @override
  void paint(Canvas canvas, Size size) {
    if (state.vignetteAmount != 0 || state.showMaskOverlay) {
      final center = Offset(size.width * state.maskCenterX, size.height * state.maskCenterY);
      final radius = (size.width > size.height ? size.width : size.height) * state.vignetteRadius;
      
      final rect = Rect.fromCenter(
        center: center,
        width: radius * 2,
        height: radius * 2 / state.maskAspectRatio,
      );

      if (state.vignetteAmount != 0) {
        double stop = 1.0 - state.vignetteFeather;
        if (stop < 0.0) stop = 0.0;
        if (stop >= 1.0) stop = 0.999;
        
        final paint = Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.transparent,
              (state.vignetteAmount < 0 ? Colors.black : Colors.white).withOpacity(state.vignetteAmount.abs()),
            ],
            stops: [stop, 1.0],
          ).createShader(rect);
        
        canvas.drawRect(Offset.zero & size, paint);
      }

      if (state.showMaskOverlay) {
        final redPaint = Paint()
          ..color = Colors.red
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        
        canvas.drawOval(rect, redPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant VignettePainter oldDelegate) => true;
}
