import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/link.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/blues_theme.dart';

Uri? safeWebUri(String? value) {
  if (value == null || RegExp(r'[\x00-\x20]').hasMatch(value)) return null;
  final uri = Uri.tryParse(value);
  return uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.hasAuthority &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

class MessageCard extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool incomplete;
  final bool generating;
  final List<Map<String, dynamic>> sources;
  final List<String> warnings;
  const MessageCard({
    super.key,
    required this.text,
    this.isUser = false,
    this.incomplete = false,
    this.generating = false,
    this.sources = const [],
    this.warnings = const [],
  });

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('답변을 복사했습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 800),
      margin: EdgeInsets.only(
        top: isUser ? 20 : 12,
        bottom: 12,
        left: isUser ? 32 : 0,
      ),
      padding: EdgeInsets.all(isUser ? 18 : 22),
      decoration: BoxDecoration(
        color: isUser ? BluesColors.blue : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isUser
            ? null
            : Border.all(
                color: incomplete ? const Color(0xFFE1B36D) : BluesColors.line,
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: BluesColors.paleBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.sports_soccer,
                    size: 16,
                    color: BluesColors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'BLUES BOT',
                  style: TextStyle(
                    fontSize: 10,
                    color: BluesColors.blue,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                if (generating)
                  const Text(
                    '작성 중',
                    style: TextStyle(fontSize: 10, color: BluesColors.muted),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (isUser)
            SelectableText(
              text,
              style: const TextStyle(
                color: Colors.white,
                height: 1.7,
                fontSize: 14,
              ),
            )
          else if (text.isEmpty)
            const Text(
              '근거를 확인하고 있습니다...',
              style: TextStyle(color: BluesColors.muted, height: 1.7),
            )
          else
            MarkdownBody(
              data: text,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    p: const TextStyle(
                      color: BluesColors.ink,
                      fontSize: 14,
                      height: 1.85,
                    ),
                    h1: const TextStyle(
                      color: BluesColors.ink,
                      fontSize: 23,
                      height: 1.5,
                      fontWeight: FontWeight.w800,
                    ),
                    h2: const TextStyle(
                      color: BluesColors.ink,
                      fontSize: 19,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
                    h3: const TextStyle(
                      color: BluesColors.ink,
                      fontSize: 16,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
                    a: const TextStyle(
                      color: BluesColors.blue,
                      decoration: TextDecoration.underline,
                    ),
                    blockSpacing: 12,
                    code: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      backgroundColor: BluesColors.paleBlue,
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: BluesColors.canvas,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    blockquoteDecoration: BoxDecoration(
                      color: BluesColors.paleBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    tableColumnWidth: const _ReadableColumnWidth(),
                    tableCellsPadding: const EdgeInsets.all(10),
                    tableBorder: TableBorder.all(color: BluesColors.line),
                    tableHead: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    tableBody: const TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: BluesColors.ink,
                    ),
                  ),
              // Generated Markdown must never fetch remote images or read local files.
              imageBuilder: (uri, title, alt) => Text(
                alt ?? '이미지',
                style: const TextStyle(color: BluesColors.muted),
              ),
              onTapLink: (label, href, title) async {
                final uri = safeWebUri(href);
                var opened = false;
                if (uri != null) {
                  try {
                    opened = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                      webOnlyWindowName: '_blank',
                    );
                  } catch (_) {
                    /* The user may have no browser handler. */
                  }
                }
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('이 링크를 열 수 없습니다.')),
                  );
                }
              },
            ),
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7EA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  warning,
                  style: const TextStyle(
                    color: Color(0xFF805013),
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          if (sources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Material(
                color: Colors.transparent,
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    backgroundColor: Colors.transparent,
                    collapsedBackgroundColor: Colors.transparent,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    initiallyExpanded: false,
                    leading: const Icon(
                      Icons.library_books_outlined,
                      size: 17,
                      color: BluesColors.blue,
                    ),
                    title: Text(
                      '참고한 출처 ${sources.length}개',
                      style: const TextStyle(
                        fontSize: 12,
                        color: BluesColors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      for (final source in sources) SourceCard(source: source),
                    ],
                  ),
                ),
              ),
            ),
          if (!isUser && text.isNotEmpty && !generating) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (!incomplete)
                  const Expanded(
                    child: Text(
                      '출처와 함께 답변을 확인해 주세요.',
                      style: TextStyle(color: BluesColors.muted, fontSize: 10),
                    ),
                  ),
                if (incomplete) const Spacer(),
                IconButton(
                  tooltip: '답변 복사',
                  onPressed: () => _copy(context),
                  icon: const Icon(
                    Icons.copy_outlined,
                    size: 17,
                    color: BluesColors.muted,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

// Short Korean labels must not collapse to one glyph per line after restoration.
// Extending IntrinsicColumnWidth retains the renderer's horizontal table scroll.
class _ReadableColumnWidth extends IntrinsicColumnWidth {
  const _ReadableColumnWidth();
  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      math.max(96.0, super.minIntrinsicWidth(cells, containerWidth));
  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) =>
      math.max(96.0, super.maxIntrinsicWidth(cells, containerWidth));
}

class SourceCard extends StatelessWidget {
  final Map<String, dynamic> source;
  const SourceCard({super.key, required this.source});
  @override
  Widget build(BuildContext context) {
    final uri = safeWebUri(source['url'] as String?);
    final date = DateTime.tryParse(source['retrieved_at'] as String? ?? '')
        ?.toLocal();
    final checked = date == null
        ? '조회 시각 미상'
        : '조회 ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final kind = switch (source['kind']) {
      'web' => '웹 자료',
      'football' => '축구 데이터',
      _ => '구단 문서',
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BluesColors.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BluesColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[${source['id']}] ${source['title']}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '$kind · $checked${source['cached'] == true ? ' · 캐시' : ''}',
            style: const TextStyle(color: BluesColors.muted, fontSize: 10),
          ),
          if (source['published_at'] != null)
            Text(
              '발행 ${source['published_at']}',
              style: const TextStyle(color: BluesColors.muted, fontSize: 10),
            ),
          if (source['excerpt'] is String &&
              (source['excerpt'] as String).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              source['excerpt'] as String,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: BluesColors.muted,
                height: 1.6,
              ),
            ),
          ],
          if (uri != null)
            Link(
              uri: uri,
              target: LinkTarget.blank,
              builder: (context, followLink) => TextButton.icon(
                onPressed: followLink,
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('원문 열기'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 48),
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
