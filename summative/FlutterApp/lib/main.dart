import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Public URL of the deployed FastAPI /predict endpoint.
/// Change this if your Render service has a different name.
const String apiUrl = 'https://uganda-learning-predictor.onrender.com/predict';

const Color brandGreen = Color(0xFF1B5E20);
const Color brandLight = Color(0xFFF3F7F2);

void main() => runApp(const LearningPredictorApp());

class LearningPredictorApp extends StatelessWidget {
  const LearningPredictorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Village Learning Predictor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: brandGreen,
        scaffoldBackgroundColor: brandLight,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
      home: const PredictionPage(),
    );
  }
}

/// One input variable of the model: the JSON key the API expects, its label, hint and icon.
/// Text fields can offer quick-fill options (they still remain text fields).
class InputField {
  const InputField(this.key, this.label, this.hint, this.icon, {this.options = const []});

  final String key;
  final String label;
  final String hint;
  final IconData icon;
  final List<String> options;

  bool get isText => options.isNotEmpty;
}

class Section {
  const Section(this.title, this.subtitle, this.icon, this.fields);

  final String title;
  final String subtitle;
  final IconData icon;
  final List<InputField> fields;
}

/// The 12 variables the model needs, grouped into three sections.
const List<Section> sections = [
  Section('Location', 'Where the village is', Icons.place_outlined, [
    InputField('region', 'Region', 'Central, Eastern, North or Western', Icons.map_outlined,
        options: ['Central', 'Eastern', 'North', 'Western']),
    InputField('area', 'Area', 'Rural or Urban', Icons.location_city_outlined, options: ['Rural', 'Urban']),
  ]),
  Section('Households', 'Share of households in the village (%)', Icons.home_outlined, [
    InputField('pct_mother_secondary', 'Mothers with secondary education', '0 to 100 %', Icons.school_outlined),
    InputField('pct_electricity', 'Households with electricity', '0 to 100 %', Icons.bolt_outlined),
    InputField('pct_phone', 'Households with a mobile phone', '0 to 100 %', Icons.smartphone_outlined),
    InputField('pct_toilet', 'Households with a toilet', '0 to 100 %', Icons.wc_outlined),
    InputField('pct_three_meals', 'Households eating 3+ meals a day', '0 to 100 %', Icons.restaurant_outlined),
    InputField('avg_household_size', 'Average household size', 'People per household, 1 to 20', Icons.groups_outlined),
  ]),
  Section('Children and schooling', 'Children aged 6 to 16 in the village', Icons.child_care_outlined, [
    InputField('pct_private_school', 'Children in private school', '0 to 100 %', Icons.account_balance_outlined),
    InputField('pct_paid_tuition', 'Children with paid extra tuition', '0 to 100 %', Icons.payments_outlined),
    InputField('pct_preschool', 'Children who attended preschool', '0 to 100 %', Icons.toys_outlined),
    InputField('avg_child_age', 'Average age of children', 'Years, 6 to 16', Icons.cake_outlined),
  ]),
];

/// Example village from the dataset, used by the "Fill example" button.
const Map<String, String> exampleVillage = {
  'region': 'Central',
  'area': 'Rural',
  'pct_mother_secondary': '27.8',
  'pct_electricity': '22.2',
  'pct_phone': '44.4',
  'pct_toilet': '66.7',
  'pct_three_meals': '33.3',
  'avg_household_size': '4.78',
  'pct_private_school': '0',
  'pct_paid_tuition': '0',
  'pct_preschool': '4.3',
  'avg_child_age': '10.11',
};

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  final Map<String, TextEditingController> _controllers = {
    for (final field in sections.expand((s) => s.fields)) field.key: TextEditingController(),
  };
  final GlobalKey _resultKey = GlobalKey();

  bool _loading = false;
  String? _error; // shown in the result area when something is wrong
  double? _score; // predicted learning score
  String? _priority; // High / Medium / Low
  String? _advice; // message from the API

  List<InputField> get _allFields => sections.expand((s) => s.fields).toList();

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _fillExample() {
    setState(() {
      exampleVillage.forEach((key, value) => _controllers[key]!.text = value);
      _error = null;
      _score = null;
    });
  }

  void _reset() {
    setState(() {
      for (final c in _controllers.values) {
        c.clear();
      }
      _error = null;
      _score = null;
    });
  }

  /// "central" -> "Central", so small typing differences are not rejected.
  String _capitalise(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  /// Checks every field is filled in and numbers are numbers.
  /// Allowed values and ranges are checked by the API (Pydantic) and shown here if they fail.
  Map<String, Object>? _readInputs() {
    final values = <String, Object>{};
    for (final field in _allFields) {
      final text = _controllers[field.key]!.text.trim();
      if (text.isEmpty) {
        _showError('"${field.label}" is missing. Please fill in every field.');
        return null;
      }
      if (field.isText) {
        values[field.key] = _capitalise(text);
        continue;
      }
      final value = double.tryParse(text);
      if (value == null) {
        _showError('"${field.label}" must be a number, e.g. 45.5 (you entered "$text").');
        return null;
      }
      values[field.key] = value;
    }
    return values;
  }

  void _showError(String message) {
    setState(() {
      _error = message;
      _score = null;
    });
    _scrollToResult();
  }

  void _scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _resultKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
      }
    });
  }

  /// Sends the inputs to the API's /predict endpoint and shows the result.
  Future<void> _predict() async {
    FocusScope.of(context).unfocus();
    final inputs = _readInputs();
    if (inputs == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _score = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(inputs),
          )
          .timeout(const Duration(seconds: 70)); // a sleeping free Render service can take ~1 minute to wake

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          _score = (body['predicted_learning_score'] as num).toDouble();
          _priority = body['support_priority'] as String;
          _advice = body['message'] as String;
        });
        _scrollToResult();
      } else if (response.statusCode == 422) {
        _showError(_readableValidationError(body));
      } else {
        _showError('Server error (${response.statusCode}). Please try again.');
      }
    } on TimeoutException {
      _showError('The server took too long to respond. It may be waking up - please press Predict again.');
    } catch (_) {
      _showError('Could not reach the prediction service. Check your internet connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Turns FastAPI/Pydantic 422 errors into a sentence that names the field.
  String _readableValidationError(dynamic body) {
    final detail = body is Map ? body['detail'] : null;
    if (detail is! List || detail.isEmpty) return 'Some values are not valid. Please check your inputs.';
    final err = detail.first as Map;
    final loc = (err['loc'] as List).map((e) => e.toString()).toList();
    final key = loc.isNotEmpty ? loc.last : '';
    final label = _allFields.where((f) => f.key == key).map((f) => f.label).firstOrNull;
    var msg = (err['msg'] ?? 'Invalid value').toString();
    if (err['ctx'] is Map) {
      final ctx = err['ctx'] as Map;
      if (ctx.containsKey('ge')) msg = 'must be at least ${ctx['ge']}';
      if (ctx.containsKey('le')) msg = 'must be at most ${ctx['le']}';
      if (ctx.containsKey('expected')) msg = 'must be one of ${ctx['expected']}';
    }
    return label != null ? '"$label" $msg.' : '$msg.';
  }

  Color get _priorityColor {
    switch (_priority) {
      case 'High':
        return Colors.red.shade700;
      case 'Medium':
        return Colors.orange.shade800;
      default:
        return Colors.green.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Village Learning Predictor', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: brandGreen,
        foregroundColor: Colors.white,
        actions: [
          IconButton(tooltip: 'Clear all fields', icon: const Icon(Icons.refresh), onPressed: _reset),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildIntroCard(),
              const SizedBox(height: 16),
              for (var i = 0; i < sections.length; i++) ...[
                _buildSectionCard(i + 1, sections[i]),
                const SizedBox(height: 16),
              ],
              _buildButtons(),
              const SizedBox(height: 16),
              KeyedSubtree(key: _resultKey, child: _buildResultArea()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF43A047)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white24,
            child: Icon(Icons.menu_book_rounded, color: Colors.white),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Find where learning support is needed',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text(
                  "Enter a Ugandan village's community details to predict the average reading and maths "
                  'score (0-10) of its children.',
                  style: TextStyle(color: Colors.white, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(int number, Section section) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: brandGreen,
                  child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(section.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text(section.subtitle, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Icon(section.icon, color: brandGreen),
              ],
            ),
            const Divider(height: 24),
            for (final field in section.fields) _buildField(field),
          ],
        ),
      ),
    );
  }

  Widget _buildField(InputField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controllers[field.key],
            keyboardType: field.isText ? TextInputType.text : const TextInputType.numberWithOptions(decimal: true),
            textCapitalization: field.isText ? TextCapitalization.words : TextCapitalization.none,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: field.label,
              helperText: field.hint,
              prefixIcon: Icon(field.icon, color: brandGreen),
            ),
          ),
          if (field.isText) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in field.options)
                  ActionChip(
                    label: Text(option),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _controllers[field.key]!.text = option),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _fillExample,
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('Fill example'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _loading ? null : _predict,
              style: FilledButton.styleFrom(
                backgroundColor: brandGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Predict', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ],
    );
  }

  /// Display area: shows the prediction, or a readable error message.
  Widget _buildResultArea() {
    final Widget content;
    if (_error != null) {
      content = Container(
        key: const ValueKey('error'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.red.shade300),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 10),
            Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade900, fontSize: 15, height: 1.35))),
          ],
        ),
      );
    } else if (_score != null) {
      content = Container(
        key: const ValueKey('result'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _priorityColor, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text('Predicted average learning score', style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Text('${_score!.toStringAsFixed(2)} / 10',
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (_score! / 10).clamp(0.0, 1.0),
                minHeight: 10,
                color: _priorityColor,
                backgroundColor: Colors.grey.shade200,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _priorityColor.withAlpha(31),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$_priority priority for support',
                  style: TextStyle(color: _priorityColor, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            Text(_advice ?? '', textAlign: TextAlign.center, style: const TextStyle(height: 1.35)),
          ],
        ),
      );
    } else {
      content = Container(
        key: const ValueKey('empty'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(Icons.insights_outlined, size: 32, color: Colors.grey.shade500),
            const SizedBox(height: 8),
            Text('The predicted learning score will appear here.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: content);
  }
}
