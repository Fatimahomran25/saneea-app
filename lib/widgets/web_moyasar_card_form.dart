import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moyasar/moyasar.dart';

/// A minimal, self-contained credit-card entry form used ONLY on Flutter Web.
///
/// Why this exists: Moyasar's own `CreditCard` widget always pushes a
/// `ThreeDSWebView` (a real `webview_flutter` WebView) after a successful
/// charge to complete the 3-D Secure confirmation step. `webview_flutter`
/// has no usable web implementation (`webview_flutter_web` throws
/// `UnimplementedError` on `setJavaScriptMode`, which `ThreeDSWebView` calls
/// unconditionally), so that widget crashes on Flutter Web.
///
/// This widget replicates the same 4 fields and calls the low-level
/// `Moyasar.pay()` API directly (the "customize the UI" path the package
/// itself documents), then hands control back to the caller via
/// [onInitiated] whenever the bank needs a confirmation step, instead of
/// trying to render that step in-app.
class WebMoyasarCardForm extends StatefulWidget {
  const WebMoyasarCardForm({
    super.key,
    required this.config,
    required this.onPaymentResult,
    required this.onInitiated,
  });

  final PaymentConfig config;

  /// Called when Moyasar returns a terminal result (paid/failed/etc.) without
  /// needing a redirect step.
  final void Function(dynamic result) onPaymentResult;

  /// Called when the charge came back as `initiated`, meaning the bank needs
  /// a confirmation step. The caller is responsible for opening
  /// [PaymentResponse]'s transaction URL and polling for completion.
  final void Function(PaymentResponse result) onInitiated;

  @override
  State<WebMoyasarCardForm> createState() => _WebMoyasarCardFormState();
}

class _WebMoyasarCardFormState extends State<WebMoyasarCardForm> {
  // Matches the app's brand palette (see `primary`/`_chatPanelSurface` in
  // chat_view.dart) so this form doesn't look like a bare, unstyled Flutter
  // form dropped into an otherwise-branded app.
  static const Color _primary = Color(0xFF5A3E9E);
  static const Color _fieldFill = Color(0xFFF8F4FD);

  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _numberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvcController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _expiryController.dispose();
    _cvcController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter the name on the card';
    }
    return null;
  }

  String? _validateNumber(String? value) {
    final digits = (value ?? '').replaceAll(' ', '');
    if (digits.length < 12 || digits.length > 19) {
      return 'Enter a valid card number';
    }
    return null;
  }

  String? _validateExpiry(String? value) {
    final cleaned = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.length != 4) {
      return 'MM/YY';
    }
    final month = int.tryParse(cleaned.substring(0, 2));
    if (month == null || month < 1 || month > 12) {
      return 'Invalid month';
    }
    return null;
  }

  String? _validateCvc(String? value) {
    final digits = (value ?? '').trim();
    if (digits.length < 3 || digits.length > 4) {
      return 'Invalid CVC';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;

    final cleanedExpiry =
        _expiryController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final month = cleanedExpiry.substring(0, 2);
    final yearShort = cleanedExpiry.substring(2, 4);

    final cardData = CardFormModel(
      name: _nameController.text.trim(),
      number: _numberController.text.replaceAll(' ', ''),
      month: month,
      year: '20$yearShort',
      cvc: _cvcController.text.trim(),
    );

    final source = CardPaymentRequestSource(
      creditCardData: cardData,
      tokenizeCard: false,
      manualPayment: false,
    );
    final paymentRequest = PaymentRequest(widget.config, source);

    setState(() => _isSubmitting = true);

    final result = await Moyasar.pay(
      apiKey: widget.config.publishableApiKey,
      paymentRequest: paymentRequest,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result is PaymentResponse && result.status == PaymentStatus.initiated) {
      widget.onInitiated(result);
      return;
    }

    widget.onPaymentResult(result);
  }

  InputDecoration _fieldDecoration(String hintText) {
    final radius = BorderRadius.circular(12);
    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: _fieldFill,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: _primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Color(0xFFC75A5A)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Color(0xFFC75A5A), width: 1.5),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: _primary,
      fontWeight: FontWeight.w700,
      fontSize: 14,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel('Name on Card'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameController,
              enabled: !_isSubmitting,
              style: const TextStyle(color: Colors.black87),
              decoration: _fieldDecoration('Name on Card'),
              validator: _validateName,
            ),
            const SizedBox(height: 16),
            _fieldLabel('Card information'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _numberController,
              enabled: !_isSubmitting,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.black87),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(19),
                _CardNumberFormatter(),
              ],
              decoration: _fieldDecoration('Card Number'),
              validator: _validateNumber,
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _expiryController,
                    enabled: !_isSubmitting,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.black87),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                      _ExpiryFormatter(),
                    ],
                    decoration: _fieldDecoration('Expiry (MM / YY)'),
                    validator: _validateExpiry,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _cvcController,
                    enabled: !_isSubmitting,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    style: const TextStyle(color: Colors.black87),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: _fieldDecoration('CVC'),
                    validator: _validateCvc,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _primary.withOpacity(0.35),
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Pay ${widget.config.currency} '
                        '${(widget.config.amount / 100).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'Powered by MOYASAR',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown after a web charge comes back `initiated` (bank confirmation
/// needed). The actual confirmation happens in a separate browser tab
/// (opened by the caller before showing this dialog); this dialog just
/// polls [verify] until it succeeds, the user cancels, or attempts run out.
///
/// Pops with `true` once [verify] succeeds, `false` otherwise.
class PaymentConfirmationDialog extends StatefulWidget {
  const PaymentConfirmationDialog({
    super.key,
    required this.verify,
    this.maxAttempts = 100,
    this.pollInterval = const Duration(seconds: 3),
  });

  final Future<void> Function() verify;
  final int maxAttempts;
  final Duration pollInterval;

  @override
  State<PaymentConfirmationDialog> createState() =>
      _PaymentConfirmationDialogState();
}

class _PaymentConfirmationDialogState
    extends State<PaymentConfirmationDialog> {
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    for (var attempt = 0; attempt < widget.maxAttempts; attempt++) {
      if (_cancelled || !mounted) return;
      try {
        await widget.verify();
        if (mounted) Navigator.of(context).pop(true);
        return;
      } catch (_) {
        // Still pending confirmation — keep polling.
      }
      if (_cancelled || !mounted) return;
      await Future.delayed(widget.pollInterval);
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirming payment'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Complete the confirmation in the new tab, then come back '
            'here — this checks automatically.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.of(context).pop(false);
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i != 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2) buffer.write(' / ');
      buffer.write(digits[i]);
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}
