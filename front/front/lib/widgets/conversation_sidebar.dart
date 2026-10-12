import 'package:flutter/material.dart';

import '../theme/blues_theme.dart';
import 'brand.dart';

class ConversationSidebar extends StatelessWidget {
  final String username;
  final String? selectedId;
  final List<Map<String, dynamic>> conversations;
  final bool loading;
  final bool archived;
  final bool pinnedOnly;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final VoidCallback onNew;
  final ValueChanged<String> onOpen;
  final ValueChanged<bool> onArchiveView;
  final VoidCallback onPinnedView;
  final ValueChanged<Map<String, dynamic>> onRename;
  final ValueChanged<Map<String, dynamic>> onArchive;
  final ValueChanged<Map<String, dynamic>> onPin;
  final VoidCallback onLogout;
  const ConversationSidebar({
    super.key,
    required this.username,
    this.selectedId,
    required this.conversations,
    required this.loading,
    required this.archived,
    required this.pinnedOnly,
    required this.searchController,
    required this.onSearch,
    required this.onNew,
    required this.onOpen,
    required this.onArchiveView,
    required this.onPinnedView,
    required this.onRename,
    required this.onArchive,
    required this.onPin,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: BluesColors.navy,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 28, 16, 30),
            child: BluesBrand(light: true),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('새 대화 시작'),
              style: FilledButton.styleFrom(
                backgroundColor: BluesColors.blue,
                foregroundColor: Colors.white,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('conversation-search'),
              controller: searchController,
              onChanged: onSearch,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLength: 80,
              decoration: InputDecoration(
                hintText: '대화 내용 검색',
                counterText: '',
                hintStyle: const TextStyle(
                  color: Color(0xFFB7C6E5),
                  fontSize: 12,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Color(0xFFB7C6E5),
                  size: 19,
                ),
                filled: true,
                fillColor: const Color(0xFF1D2C4D),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '검색 지우기',
                        onPressed: () {
                          searchController.clear();
                          onSearch('');
                        },
                        icon: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white70,
                        ),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
            child: Row(
              children: [
                _tab('내 대화', !archived, () => onArchiveView(false)),
                _tab('보관한 대화', archived, () => onArchiveView(true)),
                const Spacer(),
                IconButton(
                  tooltip: pinnedOnly ? '전체 대화 보기' : '즐겨찾기만 보기',
                  onPressed: onPinnedView,
                  icon: Icon(
                    pinnedOnly ? Icons.star_rounded : Icons.star_border_rounded,
                    color: pinnedOnly
                        ? BluesColors.gold
                        : const Color(0xFFB7C6E5),
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
          Expanded(
            child: conversations.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        searchController.text.isNotEmpty
                            ? '검색 결과가 없습니다.'
                            : pinnedOnly
                            ? '즐겨찾기한 대화가 없습니다.'
                            : archived
                            ? '보관한 대화가 없습니다.'
                            : '첫 첼시 이야기를 시작해 보세요.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB7C6E5),
                          fontSize: 12,
                          height: 1.7,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final item = conversations[index];
                      final selected = selectedId == item['id'];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: selected
                              ? const Color(0xFF263A62)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: ListTile(
                            contentPadding: const EdgeInsets.only(
                              left: 12,
                              right: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            onTap: () => onOpen(item['id'] as String),
                            leading: Icon(
                              item['pinned'] == true
                                  ? Icons.star_rounded
                                  : Icons.chat_bubble_outline_rounded,
                              size: 17,
                              color: item['pinned'] == true
                                  ? BluesColors.gold
                                  : const Color(0xFF9CADCE),
                            ),
                            minLeadingWidth: 16,
                            title: Text(
                              item['title'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFECF1FC),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              _date(item['updated_at']),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFFB7C6E5),
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: '대화 관리',
                              iconColor: const Color(0xFFB7C6E5),
                              onSelected: (action) {
                                switch (action) {
                                  case 'pin':
                                    onPin(item);
                                  case 'rename':
                                    onRename(item);
                                  case 'archive':
                                    onArchive(item);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'pin',
                                  child: Text(
                                    item['pinned'] == true ? '즐겨찾기 해제' : '즐겨찾기',
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Text('이름 바꾸기'),
                                ),
                                PopupMenuItem(
                                  value: 'archive',
                                  child: Text(archived ? '복원하기' : '보관하기'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(color: Color(0xFF2B3B5B), height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(0xFF304569),
                  child: Text(
                    username.substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      const Text(
                        'MY BLUE SPACE',
                        style: TextStyle(
                          color: Color(0xFFB7C6E5),
                          fontSize: 8,
                          letterSpacing: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '로그아웃',
                  onPressed: onLogout,
                  icon: const Icon(
                    Icons.logout_rounded,
                    size: 18,
                    color: Color(0xFFB7C6E5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _tab(String text, bool active, VoidCallback tap) => TextButton(
    onPressed: tap,
    style: TextButton.styleFrom(
      foregroundColor: active ? Colors.white : const Color(0xFFB7C6E5),
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
  );

  String _date(dynamic timestamp) {
    if (timestamp is! num) return '저장된 대화';
    final date = DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).round())
        .toLocal();
    return '${date.month}월 ${date.day}일';
  }
}
