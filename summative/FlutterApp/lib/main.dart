import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String apiUrl = 'https://liner-regression-model-project.onrender.com/predict';

// Free Render services sleep when idle and can take about a minute to wake up.
const Duration requestTimeout = Duration(seconds: 70);

/// Earthy colours borrowed from imigongo, the geometric art of eastern Rwanda.
abstract final class Palette {
  static const ink = Color(0xFF2B2622);
  static const cream = Color(0xFFF6F1E7);
  static const paper = Color(0xFFFFFCF6);
  static const line = Color(0xFFE3D9C8);
  static const muted = Color(0xFF7A7064);
  static const clay = Color(0xFFB4532A);
  static const leaf = Color(0xFF2F5D46);
  static const river = Color(0xFF2E6A8E);
}

void main() => runApp(const FoodPriceApp());

class FoodPriceApp extends StatelessWidget {
  const FoodPriceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Palette.line),
    );
    return MaterialApp(
      title: 'Rwanda Food Price Predictor',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const NoStretchScrollBehavior(),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Palette.leaf, surface: Palette.cream),
        scaffoldBackgroundColor: Palette.cream,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Palette.paper,
          isDense: true,
          helperMaxLines: 2,
          helperStyle: const TextStyle(color: Palette.muted),
          prefixIconColor: Palette.muted,
          floatingLabelStyle: const TextStyle(color: Palette.clay, fontWeight: FontWeight.w600),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: const BorderSide(color: Palette.clay, width: 1.6)),
        ),
      ),
      home: const PredictionPage(),
    );
  }
}

/// Turns off Android's stretch effect so the page does not distort when pulled past its edges.
class NoStretchScrollBehavior extends MaterialScrollBehavior {
  const NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}

// ---------------------------------------------------------------------------
// Form fields
// ---------------------------------------------------------------------------

enum FieldKind { text, integer, decimal }

class InputField {
  const InputField(this.key, this.label, this.hint, this.icon,
      {this.kind = FieldKind.decimal, this.allowed = const [], this.chips = const []});

  final String key;
  final String label;
  final String hint;
  final IconData icon;
  final FieldKind kind;
  final List<String> allowed;
  final List<String> chips;

  /// Converts the typed text into the value the API expects, or throws a readable message.
  /// Ranges and allowed values are left to the API, which reports them precisely.
  Object parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) throw '"$label" is missing. Please fill in every field.';
    return switch (kind) {
      // Match the API's spelling so "beans (dry)" is accepted as "Beans (dry)".
      FieldKind.text => allowed.firstWhere((v) => v.toLowerCase() == text.toLowerCase(), orElse: () => text),
      FieldKind.integer =>
        int.tryParse(text) ?? (throw '"$label" must be a whole number, e.g. 9 (you entered "$text").'),
      FieldKind.decimal =>
        double.tryParse(text) ?? (throw '"$label" must be a number, e.g. 45.5 (you entered "$text").'),
    };
  }
}

class Section {
  const Section(this.title, this.subtitle, this.fields);

  final String title;
  final String subtitle;
  final List<InputField> fields;
}

const List<String> commodities = [
  'Bananas', 'Beans (dry)', 'Cabbage', 'Cassava', 'Cassava flour', 'Cassava leaves', 'Fish (dry)',
  'Maize', 'Maize flour', 'Maize flour (imported)', 'Meat (beef)', 'Potatoes', 'Potatoes (Irish)',
  'Rice (imported)', 'Rice (local)', 'Rice (long grain, high quality, local)', 'Salt', 'Sorghum', 'Sugar',
];

const List<String> provinces = [
  'Kigali City', 'Eastern Province', 'Northern Province', 'Southern Province', 'Western Province',
];

const List<Section> sections = [
  Section('Food and market', 'What is sold, and where', [
    InputField('commodity', 'Food item', 'One of 19 foods, e.g. Beans (dry)', Icons.shopping_basket_outlined,
        kind: FieldKind.text,
        allowed: commodities,
        chips: ['Beans (dry)', 'Maize', 'Maize flour', 'Cassava', 'Cassava flour', 'Rice (local)', 'Potatoes (Irish)', 'Sugar']),
    InputField('province', 'Province', 'Kigali City, or the Eastern, Northern, Southern or Western Province',
        Icons.map_outlined,
        kind: FieldKind.text, allowed: provinces, chips: provinces),
    InputField('market_type', 'Market type', 'Refugee camp or Town market', Icons.holiday_village_outlined,
        kind: FieldKind.text, allowed: ['Refugee camp', 'Town market'], chips: ['Refugee camp', 'Town market']),
    InputField('distance_to_kigali_km', 'Distance from Kigali', 'Kilometres, 0 to 150', Icons.route_outlined),
  ]),
  Section('Month to predict', 'The month you want a price for', [
    InputField('year', 'Year', 'Whole number, 2018 to 2030', Icons.event_outlined, kind: FieldKind.integer),
    InputField('month', 'Month', 'Whole number, 1 (January) to 12 (December)', Icons.date_range_outlined,
        kind: FieldKind.integer),
  ]),
  Section("Last month's prices", 'Retail price per kg, in Rwandan francs', [
    InputField('price_last_month', 'Price in this market last month', 'RWF per kg, e.g. 362.5', Icons.sell_outlined),
    InputField('national_median_last_month', 'National median price last month', 'RWF per kg across Rwanda',
        Icons.public_outlined),
  ]),
];

final Map<String, InputField> fieldsByKey = {
  for (final field in sections.expand((section) => section.fields)) field.key: field,
};

/// Nyabiheke refugee camp, September 2025, taken from the test set.
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

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

class PricePrediction {
  PricePrediction.fromJson(Map<String, dynamic> json)
      : price = (json['predicted_price_rwf_per_kg'] as num).toDouble(),
        changePct = (json['change_vs_last_month_pct'] as num).toDouble(),
        alert = json['price_alert'] as String,
        message = json['message'] as String;

  final double price;
  final double changePct;
  final String alert;
  final String message;

  Color get color => switch (alert) { 'Rising' => Palette.clay, 'Falling' => Palette.river, _ => Palette.leaf };

  String get changeText => '${changePct > 0 ? '+' : ''}${changePct.toStringAsFixed(1)}%';
}

/// Calls the API. Failures are thrown as a message that can be shown to the user as-is.
Future<PricePrediction> requestPrediction(Map<String, Object> inputs) async {
  final http.Response response;
  try {
    response = await http
        .post(Uri.parse(apiUrl), headers: {'Content-Type': 'application/json'}, body: jsonEncode(inputs))
        .timeout(requestTimeout);
  } on TimeoutException {
    throw 'The server took too long to respond. It may be waking up - please press Predict again.';
  } catch (_) {
    throw 'Could not reach the prediction service. Check your internet connection and try again.';
  }

  return switch (response.statusCode) {
    200 => PricePrediction.fromJson(jsonDecode(response.body) as Map<String, dynamic>),
    422 => throw _describeValidationError(jsonDecode(response.body)),
    _ => throw 'Server error (${response.statusCode}). Please try again.',
  };
}

/// Turns the first FastAPI/Pydantic validation error into a sentence that names the field.
String _describeValidationError(dynamic body) {
  final detail = body is Map ? body['detail'] : null;
  if (detail is! List || detail.isEmpty) return 'Some values are not valid. Please check your inputs.';

  final error = detail.first as Map;
  final location = error['loc'] as List;
  final label = fieldsByKey[location.isEmpty ? '' : location.last.toString()]?.label;

  var reason = (error['msg'] ?? 'Invalid value').toString();
  final context = error['ctx'];
  if (context is Map) {
    if (context.containsKey('ge')) reason = 'must be at least ${context['ge']}';
    if (context.containsKey('gt')) reason = 'must be greater than ${context['gt']}';
    if (context.containsKey('le')) reason = 'must be at most ${context['le']}';
    if (context.containsKey('expected')) reason = 'must be one of ${context['expected']}';
  }
  return label == null ? '$reason.' : '"$label" $reason.';
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  final _controllers = {for (final key in fieldsByKey.keys) key: TextEditingController()};
  final _resultKey = GlobalKey();

  bool _loading = false;
  String? _error;
  PricePrediction? _prediction;
  double _lastMonthPrice = 0;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _fillExample() {
    exampleMarket.forEach((key, value) => _controllers[key]!.text = value);
    _showResult();
  }

  void _reset() {
    for (final controller in _controllers.values) {
      controller.clear();
    }
    _showResult();
  }

  void _showResult({String? error, PricePrediction? prediction}) {
    if (!mounted) return;
    setState(() {
      _error = error;
      _prediction = prediction;
    });
    if (error != null || prediction != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final resultContext = _resultKey.currentContext;
        if (resultContext != null) {
          Scrollable.ensureVisible(resultContext, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
        }
      });
    }
  }

  Future<void> _predict() async {
    FocusScope.of(context).unfocus();
    try {
      final inputs = {
        for (final entry in fieldsByKey.entries) entry.key: entry.value.parse(_controllers[entry.key]!.text),
      };
      setState(() => _loading = true);
      _showResult();
      final prediction = await requestPrediction(inputs);
      _lastMonthPrice = inputs['price_last_month'] as double;
      _showResult(prediction: prediction);
    } on String catch (message) {
      _showResult(error: message);
    } catch (_) {
      _showResult(error: 'Something went wrong while reading the prediction. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rwanda Food Price Predictor', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: Palette.leaf,
        foregroundColor: Palette.cream,
        actions: [
          IconButton(tooltip: 'Clear all fields', icon: const Icon(Icons.refresh), onPressed: _loading ? null : _reset),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const IntroCard(),
              for (final (index, section) in sections.indexed) ...[
                const SizedBox(height: 20),
                SectionBlock(number: index + 1, section: section, controllers: _controllers),
              ],
              const SizedBox(height: 20),
              ActionRow(loading: _loading, onFillExample: _fillExample, onPredict: _predict),
              const SizedBox(height: 20),
              KeyedSubtree(
                key: _resultKey,
                child: _error != null
                    ? ErrorNote(message: _error!)
                    : _prediction != null
                        ? PriceTag(prediction: _prediction!, lastMonthPrice: _lastMonthPrice)
                        : const EmptyResult(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form widgets
// ---------------------------------------------------------------------------

class IntroCard extends StatelessWidget {
  const IntroCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Palette.leaf, Color(0xFF467A5E)]),
        borderRadius: BorderRadius.circular(10),
        border: const Border(bottom: BorderSide(color: Palette.clay, width: 4)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Color(0x33F6F1E7),
            child: Icon(Icons.shopping_basket_rounded, color: Palette.cream),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Will families afford food next month?',
                  style: TextStyle(color: Palette.cream, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  "Enter a food item, its market and last month's prices to predict next month's retail "
                  'price per kg in a Rwandan town market or refugee camp.',
                  style: TextStyle(color: Palette.cream, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SectionBlock extends StatelessWidget {
  const SectionBlock({super.key, required this.number, required this.section, required this.controllers});

  final int number;
  final Section section;
  final Map<String, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: BoxDecoration(
        color: Palette.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '${number.toString().padLeft(2, '0')}  ',
                style: const TextStyle(color: Palette.clay, fontWeight: FontWeight.w800),
              ),
              TextSpan(text: section.title),
            ]),
            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: Palette.ink),
          ),
          Text(section.subtitle, style: const TextStyle(color: Palette.muted, fontSize: 13)),
          const SizedBox(height: 16),
          for (final field in section.fields) FieldTile(field: field, controller: controllers[field.key]!),
        ],
      ),
    );
  }
}

class FieldTile extends StatelessWidget {
  const FieldTile({super.key, required this.field, required this.controller});

  final InputField field;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            keyboardType: switch (field.kind) {
              FieldKind.text => TextInputType.text,
              FieldKind.integer => TextInputType.number,
              FieldKind.decimal => const TextInputType.numberWithOptions(decimal: true),
            },
            textCapitalization: field.kind == FieldKind.text ? TextCapitalization.sentences : TextCapitalization.none,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: field.label, helperText: field.hint, prefixIcon: Icon(field.icon)),
          ),
          if (field.chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => ChoicePicker(
                options: field.chips,
                selected: value.text.trim().toLowerCase(),
                onPick: (option) => controller.text = option,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shortcuts that fill the text field above: a switch for two options, wrapped pills otherwise.
class ChoicePicker extends StatelessWidget {
  const ChoicePicker({super.key, required this.options, required this.selected, required this.onPick});

  final List<String> options;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final asSwitch = options.length == 2;
    final choices = [
      for (final option in options)
        GestureDetector(
          onTap: () => onPick(option),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: asSwitch ? 10 : 8),
            decoration: BoxDecoration(
              color: option.toLowerCase() == selected ? Palette.ink : (asSwitch ? Colors.transparent : Palette.paper),
              borderRadius: BorderRadius.circular(asSwitch ? 8 : 20),
              border: asSwitch ? null : Border.all(color: option.toLowerCase() == selected ? Palette.ink : Palette.line),
            ),
            child: Text(
              option,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: option.toLowerCase() == selected ? Palette.cream : Palette.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
    ];

    if (!asSwitch) return Wrap(spacing: 8, runSpacing: 8, children: choices);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Palette.cream,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Palette.line),
      ),
      child: Row(children: [for (final choice in choices) Expanded(child: choice)]),
    );
  }
}

class ActionRow extends StatelessWidget {
  const ActionRow({super.key, required this.loading, required this.onFillExample, required this.onPredict});

  final bool loading;
  final VoidCallback onFillExample;
  final VoidCallback onPredict;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    return SizedBox(
      height: 52,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: OutlinedButton(
              onPressed: loading ? null : onFillExample,
              style: OutlinedButton.styleFrom(
                foregroundColor: Palette.ink,
                side: const BorderSide(color: Palette.ink),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: shape,
              ),
              child: const Text('Fill example', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: FilledButton(
              onPressed: loading ? null : onPredict,
              style: FilledButton.styleFrom(backgroundColor: Palette.leaf, shape: shape),
              child: loading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text(
                      'Predict',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result widgets
// ---------------------------------------------------------------------------

/// The prediction, laid out like a market price tag.
class PriceTag extends StatelessWidget {
  const PriceTag({super.key, required this.prediction, required this.lastMonthPrice});

  final PricePrediction prediction;
  final double lastMonthPrice;

  @override
  Widget build(BuildContext context) {
    final color = prediction.color;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Palette.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Palette.ink, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'NEXT MONTH',
                  style: TextStyle(color: Palette.muted, fontSize: 12, letterSpacing: 1.6, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                child: Text(
                  prediction.alert.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, letterSpacing: 1.2, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: prediction.price.toStringAsFixed(1),
                  style: const TextStyle(fontFamily: 'serif', fontSize: 44, fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: '  RWF / kg', style: TextStyle(fontSize: 16, color: Palette.muted)),
              ]),
            ),
          ),
          const Divider(height: 24, color: Palette.line),
          _row('Last month', '${lastMonthPrice.toStringAsFixed(1)} RWF / kg', Palette.ink),
          _row('Change', prediction.changeText, color),
          const SizedBox(height: 12),
          Text(prediction.message, style: const TextStyle(height: 1.45)),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color valueColor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Flexible(child: Text(label, style: const TextStyle(color: Palette.muted))),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(color: valueColor, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}

class ErrorNote extends StatelessWidget {
  const ErrorNote({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBEDE6),
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: Palette.clay, width: 4)),
      ),
      child: Text(message, style: const TextStyle(color: Palette.ink, fontSize: 15, height: 1.4)),
    );
  }
}

class EmptyResult extends StatelessWidget {
  const EmptyResult({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Palette.line)),
      child: const Text(
        "Next month's price will appear here.",
        textAlign: TextAlign.center,
        style: TextStyle(color: Palette.muted),
      ),
    );
  }
}
