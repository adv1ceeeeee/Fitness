import 'package:flutter/material.dart';
import 'package:sportwai/config/theme.dart';

/// Reusable 4-digit PIN pad.
/// Calls [onComplete] as soon as the 4th digit is entered.
/// Shows [errorText] in red below the dots when provided.
class PinPad extends StatefulWidget {
  final void Function(String pin) onComplete;
  final String? errorText;

  const PinPad({
    super.key,
    required this.onComplete,
    this.errorText,
  });

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _pin = '';
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void didUpdateWidget(PinPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trigger shake when a new error appears
    if (widget.errorText != null &&
        widget.errorText != oldWidget.errorText) {
      _shake();
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _shake() {
    _shakeController.forward(from: 0);
  }

  /// Reset the entered PIN (called externally from setup screen steps).
  void reset() => setState(() => _pin = '');

  void _onDigit(String d) {
    if (_pin.length >= 4) return;
    final newPin = _pin + d;
    setState(() => _pin = newPin);
    if (newPin.length == 4) {
      widget.onComplete(newPin);
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Dot indicators ─────────────────────────────────────────────────
        AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (_, child) {
            final dx = _shakeController.isAnimating
                ? 8 * (_shakeAnimation.value - 0.5) * 2
                : 0.0;
            return Transform.translate(
              offset: Offset(dx, 0),
              child: child,
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final filled = i < _pin.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled
                      ? AppColors.accent
                      : AppColors.card,
                  border: Border.all(
                    color: filled
                        ? AppColors.accent
                        : AppColors.textSecondary,
                    width: 2,
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        // ── Error text ─────────────────────────────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: widget.errorText != null
              ? Text(
                  widget.errorText!,
                  key: ValueKey(widget.errorText),
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                )
              : const SizedBox(height: 20),
        ),
        const SizedBox(height: 24),
        // ── Keypad ─────────────────────────────────────────────────────────
        _buildKeypad(),
      ],
    );
  }

  Widget _buildKeypad() {
    final digits = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Column(
      children: [
        for (final row in digits) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row
                .map((d) => _KeyButton(label: d, onTap: () => _onDigit(d)))
                .toList(),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 88), // empty slot
            _KeyButton(label: '0', onTap: () => _onDigit('0')),
            _BackspaceButton(onTap: _onBackspace),
          ],
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _KeyButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: AppColors.card,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 64,
            height: 64,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackspaceButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackspaceButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 64,
            height: 64,
            child: Center(
              child: Icon(
                Icons.backspace_outlined,
                color: AppColors.textSecondary,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
