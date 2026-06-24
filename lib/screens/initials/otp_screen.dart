import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loringo_app/components/wave_form.dart';
import 'package:loringo_app/screens/initials/confirm_reset_password_screen.dart';
import 'package:loringo_app/services/auth/otp_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ─── Same gradient + bottom colour as the entire auth flow ───────────────────
const _kTopGradient = LinearGradient(
  colors: [Color(0xFFF6E96B), Color(0xFFBEDC74), Color(0xFFA2CA71)],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);
const _kBottomColor = Color(0xFFF2F8F2);

class OTPScreen extends StatefulWidget {
  final String email;
  const OTPScreen({super.key, required this.email});

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final OTPService _otpService = OTPService();

  // Six individual controllers + focus nodes for the OTP boxes
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  int _remainingTime = 30; // 30-second resend cooldown
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _tryAutoPaste();
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final n in _focusNodes) n.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _snack(String msg, {Color color = AppColors.danger}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md)),
    ));
  }

  String get _otpValue =>
      _controllers.map((c) => c.text).join();

  void _clearFields() {
    for (final c in _controllers) c.clear();
    _focusNodes[0].requestFocus();
  }

  // ── Countdown for resend button ────────────────────────────────────────────
  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_remainingTime > 0) {
        setState(() {
          _remainingTime--;
          if (_remainingTime == 0) _canResend = true;
        });
        _startCountdown();
      }
    });
  }

  // ── Auto-paste from clipboard on open ────────────────────────────────────
  Future<void> _tryAutoPaste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (RegExp(r'^\d{6}$').hasMatch(text)) {
        for (int i = 0; i < 6; i++) {
          _controllers[i].text = text[i];
        }
        _focusNodes[5].requestFocus();
        _snack('Code pasted automatically', color: AppColors.success);
      }
    } catch (_) {
      // Silent — user can still type manually
    }
  }

  // ── Manual paste from clipboard button ───────────────────────────────────
  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text?.replaceAll(RegExp(r'\s+'), '') ?? '';
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 6) {
        for (int i = 0; i < 6; i++) {
          _controllers[i].text = digits[i];
        }
        _focusNodes[5].requestFocus();
        _snack('Code pasted', color: AppColors.success);
      } else {
        _snack('Clipboard doesn\'t contain a valid code', color: AppColors.warning);
      }
    } catch (_) {
      _snack('Could not paste code');
    }
  }

  // ── Verify OTP ────────────────────────────────────────────────────────────
  Future<void> _verifyOTP() async {
    final code = _otpValue;
    if (code.length != 6) {
      _snack('Please enter all 6 digits', color: AppColors.warning);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final isValid = await _otpService.verifyOTP(widget.email, code);
      if (isValid) {
        await _otpService.cleanupSession();
        _snack('Code verified!', color: AppColors.success);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ConfirmResetPasswordScreen(
                email: widget.email,
                otp: code,
              ),
            ),
          );
        }
      } else {
        _snack('Invalid or expired code');
        _clearFields();
      }
    } catch (e) {
      _snack('Verification error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────
  Future<void> _resendOTP() async {
    if (!_canResend) return;
    setState(() => _isLoading = true);
    try {
      final canResend = await _otpService.canResendOTP(widget.email);
      if (!canResend['canSend']) {
        _snack(canResend['message'] as String, color: AppColors.warning);
        return;
      }
      await _otpService.sendOTPToEmail(widget.email);
      _snack('New code sent to ${widget.email}', color: AppColors.success);
      setState(() {
        _remainingTime = 30;
        _canResend = false;
      });
      _startCountdown();
      _clearFields();
    } catch (e) {
      _snack('Error resending code: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final heroH = screenH * 0.40;

    return Scaffold(
      backgroundColor: _kBottomColor,
      body: Stack(
        children: [
          Container(color: _kBottomColor),

          // ── Hero gradient ────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroH + 20,
            child: Container(
              decoration: const BoxDecoration(gradient: _kTopGradient),
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    // Shield / verification icon
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mark_email_read_rounded,
                        size: 52,
                        color: Color(0xFF2E6B30),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Check your email',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E6B30),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Enter the 6-digit code we sent',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF3D7A3F),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),

          // ── Wave divider ─────────────────────────────────────────────────
          Positioned(
            top: heroH - 8,
            left: 0,
            right: 0,
            child: const WaveDivider(
              color: _kBottomColor,
              height: 54,
              waveIntensity: 1.0,
            ),
          ),

          // ── Scrollable form ───────────────────────────────────────────────
          Positioned(
            top: heroH + 20,
            left: 0,
            right: 0,
            bottom: 0,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.lg),

                    // ── White card ─────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadii.lg + 4),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Destination email label
                          Text(
                            'Code sent to',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.email,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryDark,
                            ),
                          ),

                          const SizedBox(height: AppSpacing.lg),

                          // ── 6 OTP boxes ──────────────────────────────────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: List.generate(6, (i) => _OTPBox(
                              controller: _controllers[i],
                              focusNode: _focusNodes[i],
                              onChanged: (v) {
                                if (v.isNotEmpty && i < 5) {
                                  _focusNodes[i + 1].requestFocus();
                                } else if (v.isEmpty && i > 0) {
                                  _focusNodes[i - 1].requestFocus();
                                }
                              },
                              onBackspace: () {
                                if (_controllers[i].text.isEmpty && i > 0) {
                                  _focusNodes[i - 1].requestFocus();
                                  _controllers[i - 1].clear();
                                }
                              },
                            )),
                          ),

                          const SizedBox(height: AppSpacing.sm),

                          // Paste button
                          TextButton.icon(
                            onPressed: _pasteFromClipboard,
                            icon: const Icon(Icons.content_paste_rounded,
                                size: 18),
                            label: const Text('Paste code'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              textStyle: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),

                          const SizedBox(height: AppSpacing.md),

                          // Verify button
                          ElevatedButton(
                            onPressed: _isLoading ? null : _verifyOTP,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onPrimary,
                              disabledBackgroundColor: AppColors.primaryLight,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadii.md)),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : const Text('Verify Code',
                                    style: AppText.button),
                          ),

                          const SizedBox(height: AppSpacing.md),

                          // Resend row
                          _canResend
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Didn\'t receive it? ',
                                      style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 14),
                                    ),
                                    GestureDetector(
                                      onTap: _resendOTP,
                                      child: const Text(
                                        'Resend',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          decoration:
                                              TextDecoration.underline,
                                          decorationColor: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  'Resend code in $_remainingTime seconds',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 14),
                                ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xl * 2),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Extracted OTP box widget (keeps build() clean) ──────────────────────────

class _OTPBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  const _OTPBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 58,
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (event) {
          if (event is RawKeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace) {
            if (controller.text.isEmpty) onBackspace();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryDark,
          ),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            filled: true,
            fillColor: AppColors.scaffoldBackground,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide:
                  BorderSide(color: AppColors.primarySoft(0.3), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
          onChanged: onChanged,
          onTap: () => controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          ),
        ),
      ),
    );
  }
}