import 'package:flutter/material.dart';

import '../theme/blues_theme.dart';
import 'brand.dart';

class WelcomePanel extends StatelessWidget {
  final ValueChanged<String> onQuestion;
  const WelcomePanel({super.key, required this.onQuestion});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 600;
      final horizontal = constraints.maxWidth >= 800;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          narrow ? 20 : 36,
          narrow ? 24 : 40,
          narrow ? 20 : 36,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (horizontal)
              Row(
                children: [
                  Expanded(child: _intro(narrow)),
                  const SizedBox(width: 24),
                  SizedBox(width: 300, child: _banner()),
                ],
              )
            else ...[
              _intro(narrow),
              const SizedBox(height: 24),
              _banner(),
            ],
            const SizedBox(height: 28),
            const Row(
              children: [
                Expanded(
                  child: Text(
                    '어디서부터 시작할까요?',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '추천 질문',
                  style: TextStyle(fontSize: 11, color: BluesColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) {
                final columns = box.maxWidth >= 500 ? 2 : 1;
                final width = (box.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final topic in _topics)
                      SizedBox(
                        width: width,
                        child: _TopicCard(
                          topic: topic,
                          onTap: () => onQuestion(topic.question),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      );
    },
  );

  Widget _intro(bool narrow) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'THE PRIDE OF LONDON',
        style: TextStyle(
          color: BluesColors.blue,
          fontSize: 11,
          letterSpacing: 2.2,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        '오늘도, 첼시 이야기.',
        style: TextStyle(
          color: BluesColors.ink,
          fontSize: narrow ? 28 : 38,
          height: 1.25,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.4,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        '경기장의 열기부터 구단의 역사까지.\n궁금한 이야기를 함께 찾아볼까요?',
        style: TextStyle(color: BluesColors.muted, fontSize: 15, height: 1.7),
      ),
    ],
  );

  Widget _banner() => Container(
    clipBehavior: Clip.antiAlias,
    width: double.infinity,
    decoration: BoxDecoration(
      color: BluesColors.blue,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -14,
          top: -48,
          bottom: -48,
          child: SizedBox(
            width: 185,
            child: PitchArt(color: Colors.white.withValues(alpha: .16)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    color: BluesColors.gold,
                    size: 17,
                  ),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'FOR THE FANS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        letterSpacing: 1.7,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '궁금함은 짧게.\n첼시 이야기는 깊게.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '답변에 담긴 출처를 함께 확인하세요.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .87),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Topic {
  final IconData icon;
  final String label;
  final String question;
  const _Topic(this.icon, this.label, this.question);
}

const _topics = [
  _Topic(Icons.sports_soccer_outlined, '매치 센터', '첼시 최근 5경기 결과 알려줘'),
  _Topic(Icons.person_outline_rounded, '선수 이야기', '콜 파머 최근 경기 소식 알려줘'),
  _Topic(Icons.leaderboard_outlined, '리그 테이블', '프리미어리그 순위 알려줘'),
  _Topic(Icons.stadium_outlined, '클럽 아카이브', '스탬포드 브릿지에 대해 알려줘'),
];

class _TopicCard extends StatelessWidget {
  final _Topic topic;
  final VoidCallback onTap;
  const _TopicCard({required this.topic, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: BluesColors.line),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: BluesColors.paleBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(topic.icon, size: 21, color: BluesColors.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: BluesColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    topic.question,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.north_east, size: 15, color: BluesColors.muted),
          ],
        ),
      ),
    ),
  );
}
