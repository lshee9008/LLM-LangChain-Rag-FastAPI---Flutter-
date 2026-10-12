import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/blues_theme.dart';

class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final bool disabled;
  final VoidCallback onSend;
  final VoidCallback onStop;
  const ChatComposer({
    super.key,
    required this.controller,
    required this.loading,
    required this.disabled,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: BluesColors.line),
            boxShadow: const [
              BoxShadow(
                color: Color(0x060B1735),
                blurRadius: 24,
                offset: Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: (node, event) {
                    final composing = controller.value.composing;
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed &&
                        !(composing.isValid && !composing.isCollapsed)) {
                      if (!loading && !disabled) onSend();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    key: const Key('question-input'),
                    controller: controller,
                    enabled: !disabled,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(fontSize: 14, height: 1.6),
                    decoration: const InputDecoration(
                      hintText: '오늘 첼시의 어떤 이야기가 궁금하세요?',
                      counterText: '',
                      hintStyle: TextStyle(
                        color: BluesColors.muted,
                        fontSize: 13,
                      ),
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, child) => IconButton.filled(
                    tooltip: loading ? '답변 중지' : '질문 보내기',
                    onPressed: loading
                        ? onStop
                        : disabled || value.text.trim().isEmpty
                        ? null
                        : onSend,
                    style: IconButton.styleFrom(
                      backgroundColor: BluesColors.blue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: BluesColors.paleBlue,
                      disabledForegroundColor: const Color(0xFF8297C9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      loading ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Flexible(
                child: Text(
                  '비공식 팬 AI · 중요한 정보는 출처에서 확인하세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: BluesColors.muted),
                ),
              ),
              if (constraints.maxWidth > 650)
                const Text(
                  '   ·   Enter 전송 / Shift + Enter 줄바꿈',
                  style: TextStyle(fontSize: 10, color: BluesColors.muted),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
