import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Public URL of the deployed FastAPI /predict endpoint.
/// Change this if your Render service has a different name.
const String apiUrl = 'https://student-grade-predictor.onrender.com/predict';

// Chocolate colour palette.
const Color chocolate = Color(0xFF5D3A1A);
const Color milkChocolate = Color(0xFF8B5A2B);
const Color cream = Color(0xFFFAF5EF);
const Color fieldFill = Color(0xFFFFFCF8);
const Color softBorder = Color(0xFFE5D5C3);

void main() => runApp(const GradePredictorApp());

/// Removes the Android "stretch" overscroll effect that distorts the page when it is pulled.
class NoStretchScrollBehavior extends MaterialScrollBehavior {
  const NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}

class GradePredictorApp extends StatelessWidget {
  const GradePredictorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: chocolate, primary: chocolate, secondary: milkChocolate);
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: softBorder),
    );
    return MaterialApp(
      title: 'Student Grade Predictor',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const NoStretchScrollBehavior(),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: cream,
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: softBorder),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: fieldFill,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          prefixIconColor: milkChocolate,
          floatingLabelStyle: const TextStyle(color: chocolate, fontWeight: FontWeight.w600),
          helperMaxLines: 2,
          border: fieldBorder,
          enabledBorder: fieldBorder,
          focusedBorder: fieldBorder.copyWith(borderSide: const BorderSide(color: chocolate, width: 2)),
        ),
      ),
      home: const PredictionPage(),
    );
  }
}

/// One input variable of the model: the JSON key the API expects,
/// the label shown to the user, a hint, an icon and whether it is a whole number.
class InputField {
  const InputField(this.key, this.label, this.hint, this.icon, {this.isInteger = true});

  final String key;
  final String label;
  final String hint;
  final IconData icon;
  final bool isInteger;
}

/// A titled group of input fields shown as one numbered card.
class FormSection {
  const FormSection(this.title, this.subtitle, this.icon, this.fields);

  final String title;
  final String subtitle;
  final IconData icon;
  final List<InputField> fields;
}

/// The 13 variables the model needs, grouped into four steps.
const List<FormSection> sections = [
  FormSection('Student profile', 'Who the student is', Icons.person_outline, [
    InputField('course', 'Course code', '1 to 17', Icons.class_outlined),
    InputField('age_at_enrollment', 'Age at enrollment', 'Years, 15 to 80', Icons.cake_outlined),
    InputField('gender', 'Gender', '1 = male, 0 = female', Icons.wc),
    InputField('daytime_attendance', 'Daytime attendance', '1 = daytime, 0 = evening', Icons.wb_sunny_outlined),
    InputField('displaced', 'Displaced (studying away from home)', '1 = yes, 0 = no', Icons.home_outlined),
  ]),
  FormSection('Finances', 'Fees and financial support', Icons.account_balance_wallet_outlined, [
    InputField('scholarship_holder', 'Scholarship holder', '1 = yes, 0 = no', Icons.workspace_premium_outlined),
    InputField('tuition_fees_up_to_date', 'Tuition fees up to date', '1 = yes, 0 = no', Icons.receipt_long_outlined),
    InputField('debtor', 'Debtor', '1 = yes, 0 = no', Icons.money_off_outlined),
  ]),
  FormSection('Semester 1 results', 'Performance in the first semester', Icons.menu_book_outlined, [
    InputField('sem1_units_enrolled', 'Units enrolled (semester 1)', '0 to 30', Icons.library_books_outlined),
    InputField('sem1_units_evaluations', 'Assessments taken (semester 1)', '0 to 50', Icons.assignment_outlined),
    InputField('sem1_units_approved', 'Units passed (semester 1)', '0 to 30, not more than enrolled',
        Icons.check_circle_outline),
    InputField('sem1_grade', 'Average grade (semester 1)', '0, or 10 to 20 (e.g. 13.5)', Icons.grade_outlined,
        isInteger: false),
  ]),
  FormSection('Semester 2', 'The semester being predicted', Icons.event_note_outlined, [
    InputField('sem2_units_enrolled', 'Units enrolled (semester 2)', '1 to 30', Icons.library_add_outlined),
  ]),
];

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
  String? _errorField; // key of the field to highlight in red
  double? _grade; // predicted grade
  String? _risk; // High / Medium / Low
  String? _advice; // message from the API

  List<InputField> get _allFields => sections.expand((s) => s.fields).toList();

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Checks every field is filled in and has the right type.
  /// Range checks are done by the API (Pydantic) and shown here if they fail.
  Map<String, num>? _readInputs() {
    final values = <String, num>{};
    for (final field in _allFields) {
      final text = _controllers[field.key]!.text.trim();
      if (text.isEmpty) {
        _showError('"${field.label}" is missing. Please fill in every field.', field: field.key);
        return null;
      }
      final num? value = field.isInteger ? int.tryParse(text) : double.tryParse(text);
      if (value == null) {
        _showError(
            field.isInteger
                ? '"${field.label}" must be a whole number (you entered "$text").'
                : '"${field.label}" must be a number, e.g. 13.5 (you entered "$text").',
            field: field.key);
        return null;
      }
      values[field.key] = value;
    }
    return values;
  }

  void _showError(String message, {String? field}) {
    setState(() {
      _error = message;
      _errorField = field;
      _grade = null;
    });
    _scrollToResult();
  }

  /// Brings the result card into view after it changes.
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
      _errorField = null;
      _grade = null;
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
          _grade = (body['predicted_sem2_grade'] as num).toDouble();
          _risk = body['risk_level'] as String;
          _advice = body['message'] as String;
        });
        _scrollToResult();
      } else if (response.statusCode == 422) {
        _showValidationError(body);
      } else {
        _showError('Server error (${response.statusCode}). Please try again.');
      }
    } on TimeoutException {
      _showError('The server took too long to respond. It may be waking up - please press Predict again.');
    } catch (e) {
      _showError('Could not reach the prediction service. Check your internet connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Turns FastAPI/Pydantic 422 errors into a sentence that names the field.
  void _showValidationError(dynamic body) {
    final detail = body is Map ? body['detail'] : null;
    if (detail is! List || detail.isEmpty) {
      _showError('Some values are not valid. Please check your inputs.');
      return;
    }
    final err = detail.first as Map;
    final loc = (err['loc'] as List).map((e) => e.toString()).toList();
    final key = loc.isNotEmpty ? loc.last : '';
    final label = _allFields.where((f) => f.key == key).map((f) => f.label).firstOrNull;
    var msg = (err['msg'] ?? 'Invalid value').toString().replaceFirst('Value error, ', '');
    if (err['ctx'] is Map) {
      final ctx = err['ctx'] as Map;
      if (ctx.containsKey('ge')) msg = 'must be at least ${ctx['ge']}';
      if (ctx.containsKey('le')) msg = 'must be at most ${ctx['le']}';
    }
    _showError(label != null ? '"$label" $msg.' : '$msg.', field: label != null ? key : null);
  }

  Color get _riskColor {
    switch (_risk) {
      case 'High':
        return const Color(0xFFB3261E);
      case 'Medium':
        return const Color(0xFFC46A12);
      default:
        return const Color(0xFF2E7D32);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Grade Predictor', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: chocolate,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(), // tap outside a field to close the keyboard
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(), // stop at the edges instead of bouncing/stretching
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720), // keeps the form readable on tablets
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildIntro(theme),
                    for (var i = 0; i < sections.length; i++) ...[
                      const SizedBox(height: 16),
                      _buildSection(theme, i + 1, sections[i]),
                    ],
                    const SizedBox(height: 22),
                    _buildPredictButton(),
                    const SizedBox(height: 16),
                    KeyedSubtree(key: _resultKey, child: _buildResultArea(theme)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Banner at the top explaining what the app does.
  Widget _buildIntro(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [chocolate, milkChocolate],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: chocolate.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.school_outlined, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Early support starts here',
                    style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  "Enter a student's details at the end of semester 1 to predict their "
                  'semester 2 average grade (0-20) and flag students who need support early.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A numbered card holding one group of input fields (two columns on wide screens).
  Widget _buildSection(ThemeData theme, int step, FormSection section) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: chocolate,
                  child: Text('$step', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(section.title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: chocolate)),
                      Text(section.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(section.icon, color: milkChocolate.withValues(alpha: 0.7)),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1, color: softBorder),
            ),
            LayoutBuilder(builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 520;
              final width = twoColumns ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                children: [
                  for (final field in section.fields) SizedBox(width: width, child: _buildField(field)),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildField(InputField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controllers[field.key],
        keyboardType: TextInputType.numberWithOptions(decimal: !field.isInteger),
        textInputAction: TextInputAction.next,
        onChanged: (_) {
          if (_errorField == field.key) setState(() => _errorField = null);
        },
        decoration: InputDecoration(
          labelText: field.label,
          helperText: field.hint,
          prefixIcon: Icon(field.icon, size: 20),
          errorText: _errorField == field.key ? 'Check this value' : null,
        ),
      ),
    );
  }

  Widget _buildPredictButton() {
    return SizedBox(
      height: 54,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: chocolate,
          disabledBackgroundColor: milkChocolate.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
        onPressed: _loading ? null : _predict,
        child: _loading
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text('Predicting...',
                        overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ],
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.insights_outlined),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text('Predict',
                        overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
      ),
    );
  }

  /// Display area: shows the prediction, or a readable error message.
  Widget _buildResultArea(ThemeData theme) {
    final Widget content;
    final Color accent;
    if (_error != null) {
      accent = const Color(0xFFB3261E);
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: accent),
          const SizedBox(width: 10),
          Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFF8C1D18), fontSize: 15, height: 1.35))),
        ],
      );
    } else if (_grade != null) {
      accent = _riskColor;
      content = Column(
        children: [
          Text('Predicted semester 2 grade',
              style: theme.textTheme.titleSmall?.copyWith(color: chocolate, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: _grade!.toStringAsFixed(2),
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: accent),
              ),
              TextSpan(text: ' / 20', style: theme.textTheme.titleMedium?.copyWith(color: chocolate)),
            ]),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (_grade! / 20).clamp(0.0, 1.0),
              minHeight: 8,
              color: accent,
              backgroundColor: accent.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(20)),
            child: Text('$_risk risk',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(height: 12),
          Text(_advice ?? '', textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
        ],
      );
    } else {
      accent = softBorder;
      content = Column(
        children: [
          Icon(Icons.analytics_outlined, size: 34, color: milkChocolate.withValues(alpha: 0.7)),
          const SizedBox(height: 8),
          Text('The predicted grade will appear here.',
              textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );
    }
    final idle = _grade == null && _error == null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(minHeight: 110),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: idle ? Colors.white : accent.withValues(alpha: 0.07),
        border: Border.all(color: idle ? softBorder : accent.withValues(alpha: 0.6), width: 1.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: content,
    );
  }
}
