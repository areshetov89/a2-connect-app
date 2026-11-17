// A2 Connect: simple home screen — logo, one big on/off button, country list.
// The full FlClash interface stays available behind the gear button.

import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// true — the simple A2 screen, false — the full FlClash interface.
final a2SimpleMode = ValueNotifier<bool>(true);

const _yellow = Color(0xFFF0EB4F);
const _black = Color(0xFF0A0A0A);
const _card = Color(0xFF161616);
const _line = Color(0xFF2A2A2A);
const _muted = Color(0xFF9A9A9A);
const _white = Color(0xFFFFFFFF);
const _green = Color(0xFF3DDC84);
const _red = Color(0xFFFF5A5A);

const _cabinetUrl = 'https://lk.a2-connect.com';

class A2HomeView extends ConsumerStatefulWidget {
  const A2HomeView({super.key});

  @override
  ConsumerState<A2HomeView> createState() => _A2HomeViewState();
}

class _A2HomeViewState extends ConsumerState<A2HomeView> {
  bool _busy = false;
  String? _message;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(proxiesActionProvider.notifier).updateGroups();
      _testDelays();
    });
    _delayTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) async {
        if (!mounted) return;
        await ref.read(proxiesActionProvider.notifier).updateGroups();
        _testDelays();
      },
    );
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    super.dispose();
  }

  Group? _mainGroup(List<Group> groups) {
    final candidates = groups
        .where(
          (g) =>
              g.type == GroupType.Selector &&
              g.hidden != true &&
              g.name.toUpperCase() != 'GLOBAL' &&
              g.all.isNotEmpty,
        )
        .toList();
    if (candidates.isNotEmpty) return candidates.first;
    final any = groups.where((g) => g.all.isNotEmpty).toList();
    return any.isEmpty ? null : any.first;
  }

  void _testDelays() {
    if (!mounted) return;
    final group = _mainGroup(ref.read(groupsProvider));
    if (group == null) return;
    unawaited(
      ref.read(proxiesActionProvider.notifier).delayTestGroups([group]),
    );
  }

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!text.startsWith('http') && !text.isShareLink) {
      setState(
        () => _message =
            'В буфере нет ссылки. Скопируйте ссылку подписки в личном кабинете '
            '(«Подписка» → ссылка https://sub.a2-connect.com/...) и нажмите снова.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(profilesActionProvider.notifier)
          .addProfileFromLink(text, label: 'A2 Connect');
      a2SimpleMode.value = true;
      await ref.read(proxiesActionProvider.notifier).updateGroups();
      _testDelays();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle() {
    ref.read(commonActionProvider.notifier).toggleRunning();
  }

  void _select(Group group, String proxyName) {
    ref
        .read(proxiesActionProvider.notifier)
        .changeProxyDebounce(group.name, proxyName);
  }

  @override
  Widget build(BuildContext context) {
    final hasProfile = ref.watch(
      profilesProvider.select((state) => state.isNotEmpty),
    );
    final isStart = ref.watch(isStartProvider);
    final groups = ref.watch(groupsProvider);
    final group = _mainGroup(groups);
    final profile = ref.watch(currentProfileProvider);

    return ColoredBox(
      color: _black,
      child: SafeArea(
        child: Column(
          children: [
            _Header(onSettings: () => a2SimpleMode.value = false),
            Expanded(
              child: hasProfile
                  ? _ConnectedBody(
                      isStart: isStart,
                      group: group,
                      profile: profile,
                      onToggle: _toggle,
                      onSelect: _select,
                      onRefresh: _testDelays,
                    )
                  : _Onboarding(
                      busy: _busy,
                      message: _message,
                      onPaste: _pasteLink,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/icon.png',
              width: 40,
              height: 40,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'A2 Connect',
              style: TextStyle(
                color: _white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _Tap(
            onTap: onSettings,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _line),
              ),
              child: const Text(
                '⚙︎',
                style: TextStyle(color: _muted, fontSize: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectedBody extends ConsumerWidget {
  const _ConnectedBody({
    required this.isStart,
    required this.group,
    required this.profile,
    required this.onToggle,
    required this.onSelect,
    required this.onRefresh,
  });

  final bool isStart;
  final Group? group;
  final Profile? profile;
  final VoidCallback onToggle;
  final void Function(Group group, String proxyName) onSelect;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = group == null
        ? null
        : ref.watch(selectedProxyNameProvider(group!.name));
    final expire = profile?.subscriptionInfo?.expire ?? 0;
    String? daysLeft;
    if (expire > 0) {
      final left = DateTime.fromMillisecondsSinceEpoch(
        expire * 1000,
      ).difference(DateTime.now()).inDays;
      daysLeft = left >= 0 ? 'Подписка: осталось $left дн.' : 'Подписка истекла';
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const SizedBox(height: 12),
        Center(
          child: _BigButton(isStart: isStart, onTap: onToggle),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            isStart ? 'Защищено' : 'Не подключено',
            style: TextStyle(
              color: isStart ? _yellow : _muted,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (isStart && selected != null) ...[
          const SizedBox(height: 4),
          Center(
            child: Text(
              _pretty(selected),
              style: const TextStyle(color: _muted, fontSize: 14),
            ),
          ),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Страна',
                style: TextStyle(
                  color: _white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _Tap(
              onTap: onRefresh,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Text(
                  'Проверить пинг',
                  style: TextStyle(color: _yellow, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (group == null)
          const _Note('Список стран появится через несколько секунд…')
        else
          for (final proxy in group!.all)
            _CountryRow(
              name: proxy.name,
              selected: proxy.name == selected,
              onTap: () => onSelect(group!, proxy.name),
            ),
        const SizedBox(height: 20),
        if (daysLeft != null) Center(child: _Note(daysLeft)),
        const SizedBox(height: 10),
        _OutlineButton(
          label: 'Продлить подписку',
          onTap: () => dialogs.openUrl(_cabinetUrl),
        ),
      ],
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.isStart, required this.onTap});

  final bool isStart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 190,
        height: 190,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isStart ? _yellow : _card,
          border: Border.all(color: isStart ? _yellow : _line, width: 3),
          boxShadow: isStart
              ? [
                  BoxShadow(
                    color: _yellow.withValues(alpha: 0.35),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ]
              : const [],
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '⏻',
              style: TextStyle(
                color: isStart ? _black : _yellow,
                fontSize: 54,
                height: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isStart ? 'Выключить' : 'Включить',
              style: TextStyle(
                color: isStart ? _black : _white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryRow extends ConsumerWidget {
  const _CountryRow({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delay = ref.watch(delayProvider(proxyName: name));
    final String delayText;
    final Color delayColor;
    if (delay == null) {
      delayText = '';
      delayColor = _muted;
    } else if (delay < 0) {
      delayText = 'нет связи';
      delayColor = _red;
    } else if (delay == 0) {
      delayText = '…';
      delayColor = _muted;
    } else {
      delayText = '$delay мс';
      delayColor = delay < 300 ? _green : _yellow;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Tap(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _yellow : _line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(_flag(name), style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _pretty(name),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _white,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                delayText,
                style: TextStyle(color: delayColor, fontSize: 13),
              ),
              const SizedBox(width: 10),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? _yellow : const Color(0x00000000),
                  border: Border.all(
                    color: selected ? _yellow : _muted,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: selected
                    ? const Text(
                        '✓',
                        style: TextStyle(
                          color: _black,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Onboarding extends StatelessWidget {
  const _Onboarding({
    required this.busy,
    required this.message,
    required this.onPaste,
  });

  final bool busy;
  final String? message;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        const SizedBox(height: 20),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset(
              'assets/images/icon.png',
              width: 120,
              height: 120,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Добро пожаловать в A2 Connect',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '1. Откройте личный кабинет и скопируйте ссылку подписки\n'
          '2. Нажмите «Вставить ссылку»',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 28),
        _FilledButton(
          label: busy ? 'Добавляю…' : 'Вставить ссылку',
          onTap: busy ? null : onPaste,
        ),
        const SizedBox(height: 12),
        _OutlineButton(
          label: 'Открыть личный кабинет',
          onTap: () => dialogs.openUrl(_cabinetUrl),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          _Note(message!),
        ],
      ],
    );
  }
}

class _FilledButton extends StatelessWidget {
  const _FilledButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _Tap(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? _yellow.withValues(alpha: 0.5) : _yellow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: _black,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tap(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: _white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: _muted, fontSize: 13, height: 1.4),
    );
  }
}

class _Tap extends StatelessWidget {
  const _Tap({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

/// Small floating button shown over the full interface to get back.
class A2BackButton extends StatelessWidget {
  const A2BackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return _Tap(
      onTap: () => a2SimpleMode.value = true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _yellow,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 12),
          ],
        ),
        child: const Text(
          '← A2',
          style: TextStyle(
            color: _black,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Strips the flag emoji (shown separately) from a node name.
String _pretty(String name) {
  final runes = name.runes.toList();
  var i = 0;
  while (i < runes.length && (_isRegional(runes[i]) || runes[i] == 0x20)) {
    i++;
  }
  final rest = String.fromCharCodes(runes.sublist(i)).trim();
  return rest.isEmpty ? name : rest;
}

bool _isRegional(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;

String _flag(String name) {
  final runes = name.runes.toList();
  if (runes.length >= 2 && _isRegional(runes[0]) && _isRegional(runes[1])) {
    return String.fromCharCodes(runes.sublist(0, 2));
  }
  final n = name.toLowerCase();
  const map = <String, String>{
    'фин': '🇫🇮', 'finland': '🇫🇮', 'helsinki': '🇫🇮', 'хельсинки': '🇫🇮',
    'герм': '🇩🇪', 'german': '🇩🇪', 'frankfurt': '🇩🇪',
    'швец': '🇸🇪', 'swed': '🇸🇪', 'stockholm': '🇸🇪',
    'сша': '🇺🇸', 'usa': '🇺🇸', 'united states': '🇺🇸', 'америк': '🇺🇸',
    'росс': '🇷🇺', 'russia': '🇷🇺', 'москв': '🇷🇺', 'moscow': '🇷🇺',
    'нидерл': '🇳🇱', 'netherl': '🇳🇱', 'amsterdam': '🇳🇱', 'амстер': '🇳🇱',
    'европ': '🇪🇺', 'europe': '🇪🇺',
    'auto': '⚡', 'авто': '⚡', 'быстр': '⚡',
  };
  for (final entry in map.entries) {
    if (n.contains(entry.key)) return entry.value;
  }
  return '🌐';
}
