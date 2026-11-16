import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Public URL of the deployed FastAPI /predict endpoint.
/// Change this if your Render service has a different name.
const String apiUrl = 'https://rwanda-food-price-predictor.onrender.com/predict';

const Color brandGreen = Color(0xFF1B5E20);
const Color brandLight = Color(0xFFF3F7F2);

void main() => runApp(const FoodPriceApp());

class FoodPriceApp extends StatelessWidget {
  const FoodPriceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rwanda Food Price Predictor',
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

enum FieldKind { text, integer, decimal }

/// One input variable of the model: the JSON key the API expects, its label, hint and icon.
/// Text fields can offer quick-fill chips (they still remain text fields).
class InputField {
  const InputField(this.key, this.label, this.hint, this.icon,
      {this.kind = FieldKind.decimal, this.allowed = const [], this.chips = const []});

  final String key;
  final String label;
  final String hint;
  final IconData icon;
  final FieldKind kind;
  final List<String> allowed; // values the API accepts, used to fix capitalisation
  final List<String> chips; // quick-fill shortcuts shown under the field

  bool get isText => kind == FieldKind.text;
}

class Section {
  const Section(this.title, this.subtitle, this.icon, this.fields);

  final String title;
  final String subtitle;
  final IconData icon;
  final List<InputField> fields;
}

const List<String> commodities = [
  'Bananas', 'Beans (dry)', 'Cabbage', 'Cassava', 'Cassava flour', 'Cassava leaves', 'Fish (dry)',
  'Maize', 'Maize flour', 'Maize flour (imported)', 'Meat (beef)', 'Potatoes', 'Potatoes (Irish)',
  'Rice (imported)', 'Rice (local)', 'Rice (long grain, high quality, local)', 'Salt', 'Sorghum', 'Sugar',
];
const List<String> provinces = [
  'Eastern Province', 'Kigali City', 'Northern Province', 'Southern Province', 'Western Province',
];

/// The 8 variables the model needs, grouped into three sections.
const List<Section> sections = [
  Section('Food and market', 'What is sold and where', Icons.storefront_outlined, [
    InputField('commodity', 'Food item', 'One of 19 foods, e.g. Beans (dry)', Icons.shopping_basket_outlined,
        kind: FieldKind.text,
        allowed: commodities,
        chips: ['Beans (dry)', 'Maize', 'Maize flour', 'Cassava flour', 'Rice (local)', 'Potatoes (Irish)', 'Sugar', 'Salt']),
    InputField('province', 'Province', 'Eastern, Kigali City, Northern, Southern or Western', Icons.map_outlined,
        kind: FieldKind.text, allowed: provinces, chips: provinces),
    InputField('market_type', 'Market type', 'Refugee camp or Town market', Icons.holiday_village_outlined,
        kind: FieldKind.text, allowed: ['Refugee camp', 'Town market'], chips: ['Refugee camp', 'Town market']),
    InputField('distance_to_kigali_km', 'Distance from Kigali', 'Kilometres, 0 to 150', Icons.route_outlined),
  ]),
  Section('Month to predict', 'The month you want a price for', Icons.calendar_month_outlined, [
    InputField('year', 'Year', 'Whole number, 2018 to 2030', Icons.event_outlined, kind: FieldKind.integer),
    InputField('month', 'Month', 'Whole number, 1 (January) to 12 (December)', Icons.date_range_outlined,
        kind: FieldKind.integer),
  ]),
  Section("Last month's prices", 'Retail price per kg in Rwandan francs (RWF)', Icons.payments_outlined, [
    InputField('price_last_month', 'Price in this market last month', 'RWF per kg, e.g. 362.5', Icons.sell_outlined),
    InputField('national_median_last_month', 'National median price last month', 'RWF per kg across Rwanda',
        Icons.public_outlined),
  ]),
];

/// Example from the test set (Nyabiheke refugee camp, September 2025), used by the "Fill example" button.
const Map<String, String> exampleMarket = {
  'commodity': 'Cassava',
  'province': 'Eastern Province',
  'market_type': 'Refugee camp',
  'distance_to_kigali_km': '44.8',
  'year': '2025',
  'month': '9',
  'price_last_month': '362.5',
  'national_median_last_month': '350',
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
  double? _price; // predicted price, RWF per kg
  double? _change; // % change from last month
  String? _alert; // Rising / Stable / Falling
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
      exampleMarket.forEach((key, value) => _controllers[key]!.text = value);
      _error = null;
      _price = null;
    });
  }

  void _reset() {
    setState(() {
      for (final c in _controllers.values) {
        c.clear();
      }
      _error = null;
      _price = null;
    });
  }

  /// "beans (dry)" -> "Beans (dry)", so capitalisation differences are not rejected.
  String _matchAllowed(InputField field, String text) {
    for (final value in field.allowed) {
      if (value.toLowerCase() == text.toLowerCase()) return value;
    }
    return text; // unknown value: the API will explain what is allowed
  }

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
        values[field.key] = _matchAllowed(field, text);
        continue;
      }
      if (field.kind == FieldKind.integer) {
        final whole = int.tryParse(text);
        if (whole == null) {
          _showError('"${field.label}" must be a whole number, e.g. 9 (you entered "$text").');
          return null;
        }
        values[field.key] = whole;
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
      _price = null;
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
      _price = null;
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
          _price = (body['predicted_price_rwf_per_kg'] as num).toDouble();
          _change = (body['change_vs_last_month_pct'] as num).toDouble();
          _alert = body['price_alert'] as String;
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
      if (ctx.containsKey('gt')) msg = 'must be greater than ${ctx['gt']}';
      if (ctx.containsKey('le')) msg = 'must be at most ${ctx['le']}';
      if (ctx.containsKey('expected')) msg = 'must be one of ${ctx['expected']}';
    }
    return label != null ? '"$label" $msg.' : '$msg.';
  }

  Color get _alertColor {
    switch (_alert) {
      case 'Rising':
        return Colors.red.shade700;
      case 'Falling':
        return Colors.blue.shade700;
      default:
        return Colors.green.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rwanda Food Price Predictor', style: TextStyle(fontWeight: FontWeight.w600)),
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
            child: Icon(Icons.shopping_basket_rounded, color: Colors.white),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Will families afford food next month?",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text(
                  "Enter a food item, its market and last month's prices to predict next month's retail "
                  'price per kg in a Rwandan town market or refugee camp.',
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
            keyboardType: switch (field.kind) {
              FieldKind.text => TextInputType.text,
              FieldKind.integer => TextInputType.number,
              FieldKind.decimal => const TextInputType.numberWithOptions(decimal: true),
            },
            textCapitalization: field.isText ? TextCapitalization.sentences : TextCapitalization.none,
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
                for (final option in field.chips)
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
    } else if (_price != null) {
      final sign = _change! > 0 ? '+' : '';
      content = Container(
        key: const ValueKey('result'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _alertColor, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text('Predicted retail price', style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Text('${_price!.toStringAsFixed(1)} RWF / kg',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('$sign${_change!.toStringAsFixed(1)}% compared with last month',
                style: TextStyle(color: _alertColor, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _alertColor.withAlpha(31),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _alert == 'Rising'
                        ? Icons.trending_up
                        : _alert == 'Falling'
                            ? Icons.trending_down
                            : Icons.trending_flat,
                    color: _alertColor,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text('Price ${_alert!.toLowerCase()}',
                      style: TextStyle(color: _alertColor, fontWeight: FontWeight.bold)),
                ],
              ),
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
            Text('The predicted price will appear here.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: content);
  }
}
