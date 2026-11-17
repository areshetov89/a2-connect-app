// A2 Connect: simple home screen — logo, one big on/off button, country list.
// The full FlClash interface stays available behind the gear button.

import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/a2_api.dart';
import 'package:flutter/foundation.dart';
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

const _cabinetUrl = a2CabinetUrl;

class A2HomeView extends ConsumerStatefulWidget {
  const A2HomeView({super.key});

  @override
  ConsumerState<A2HomeView> createState() => _A2HomeViewState();
}

class _A2HomeViewState extends ConsumerState<A2HomeView> {
  bool _busy = false;
  String? _message;
  Timer? _delayTimer;
  StreamSubscription<Uri>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = a2AuthLinks.stream.listen(_onAuthLink);
    final pending = a2PendingAuthLink;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onAuthLink(pending));
    }
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
    unawaited(_authSub?.cancel());
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

  Future<void> _addSubscription(String url) async {
    await ref
        .read(profilesActionProvider.notifier)
        .addProfileFromLink(url, label: 'A2 Connect');
    a2SimpleMode.value = true;
    await ref.read(proxiesActionProvider.notifier).updateGroups();
    _testDelays();
  }

  Future<void> _afterLogin() async {
    var url = await A2Api.instance.subscriptionUrl();
    if (url == null) {
      if (await A2Api.instance.activateTrial()) {
        url = await A2Api.instance.subscriptionUrl();
      }
    }
    if (url == null) {
      setState(
        () => _message =
            'Вы вошли, но у вас пока нет подписки. Оформите её в личном '
            'кабинете — и нажмите «Войти» ещё раз.',
      );
      return;
    }
    await _addSubscription(url);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on A2AuthException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Нет связи с сервером. Проверьте интернет и попробуйте ещё раз.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _loginTelegram() => _run(() async {
    final login = await A2Api.instance.startTelegramLogin();
    await dialogs.openUrl(login.link);
    if (mounted) {
      setState(
        () => _message = 'Нажмите «Старт» в боте Telegram и вернитесь сюда…',
      );
    }
    await login.done;
    await _afterLogin();
  });

  void _onAuthLink(Uri uri) {
    a2PendingAuthLink = null;
    final rt = uri.queryParameters['rt'];
    if (rt == null || rt.isEmpty || !mounted) return;
    if (ref.read(profilesProvider).isNotEmpty) return;
    _run(() async {
      await A2Api.instance.loginWithRefreshToken(rt);
      await _afterLogin();
    });
  }

  void _loginBrowser() => _run(() async {
    await dialogs.openUrl(A2Api.instance.browserLoginUrl);
    if (mounted) {
      setState(
        () => _message =
            'Войдите в открывшемся кабинете (Google, почта или Telegram). '
            'После входа браузер предложит открыть A2 Connect — нажмите «Открыть».',
      );
    }
  });

  void _loginEmail(String email, String password) => _run(() async {
    await A2Api.instance.loginEmail(email, password);
    await _afterLogin();
  });

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
    final selected = group == null
        ? null
        : ref.watch(selectedProxyNameProvider(group.name));
    final delays = <String, int?>{
      for (final proxy in group?.all ?? const <Proxy>[])
        proxy.name: ref.watch(delayProvider(proxyName: proxy.name)),
    };

    return DefaultTextStyle(
      style: _baseText,
      child: ColoredBox(
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
                      selected: selected,
                      delays: delays,
                      profile: profile,
                      onToggle: _toggle,
                      onSelect: _select,
                      onRefresh: _testDelays,
                    )
                  : _Onboarding(
                      busy: _busy,
                      message: _message,
                      onPaste: _pasteLink,
                      onTelegram: _loginTelegram,
                      onBrowser: _loginBrowser,
                      onEmail: _loginEmail,
                    ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

/// Overridden only by the screenshot test, which has no system font.
@visibleForTesting
String? a2FontFamily;

TextStyle get _baseText => TextStyle(
  color: _white,
  fontSize: 15,
  decoration: TextDecoration.none,
  fontWeight: FontWeight.w400,
  fontFamily: a2FontFamily,
  fontFamilyFallback: const ['Twemoji'],
);

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

class _ConnectedBody extends StatelessWidget {
  const _ConnectedBody({
    required this.isStart,
    required this.group,
    required this.selected,
    required this.delays,
    required this.profile,
    required this.onToggle,
    required this.onSelect,
    required this.onRefresh,
  });

  final bool isStart;
  final Group? group;
  final String? selected;
  final Map<String, int?> delays;
  final Profile? profile;
  final VoidCallback onToggle;
  final void Function(Group group, String proxyName) onSelect;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final selected = this.selected;
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
              delay: delays[proxy.name],
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

class _CountryRow extends StatelessWidget {
  const _CountryRow({
    required this.name,
    required this.delay,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final int? delay;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final delay = this.delay;
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

class _Onboarding extends StatefulWidget {
  const _Onboarding({
    required this.busy,
    required this.message,
    required this.onPaste,
    required this.onTelegram,
    required this.onBrowser,
    required this.onEmail,
  });

  final VoidCallback onBrowser;
  final bool busy;
  final String? message;
  final VoidCallback onPaste;
  final VoidCallback onTelegram;
  final void Function(String email, String password) onEmail;

  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _emailMode = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submitEmail() {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    widget.onEmail(_email.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        const SizedBox(height: 8),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/images/icon.png',
              width: 96,
              height: 96,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Вход в A2 Connect',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Войдите тем же способом, что и в личный кабинет — '
          'страны и подписка подключатся сами',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 14, height: 1.45),
        ),
        const SizedBox(height: 24),
        if (!_emailMode) ...[
          _FilledButton(
            label: 'Войти через Google (Gmail)',
            onTap: busy ? null : widget.onBrowser,
          ),
          const SizedBox(height: 12),
          _OutlineButton(
            label: 'Войти по почте и паролю',
            onTap: () => setState(() => _emailMode = true),
          ),
          const SizedBox(height: 12),
          _OutlineButton(
            label: busy ? 'Ожидаю вход…' : 'Войти через Telegram',
            onTap: busy ? () {} : widget.onTelegram,
          ),
        ] else ...[
          _Input(controller: _email, hint: 'Почта', keyboard: TextInputType.emailAddress),
          const SizedBox(height: 10),
          _Input(
            controller: _password,
            hint: 'Пароль',
            obscure: true,
            onSubmitted: _submitEmail,
          ),
          const SizedBox(height: 14),
          _FilledButton(
            label: busy ? 'Вхожу…' : 'Войти',
            onTap: busy ? null : _submitEmail,
          ),
          const SizedBox(height: 12),
          _OutlineButton(
            label: 'Назад',
            onTap: () => setState(() => _emailMode = false),
          ),
        ],
        if (widget.message != null) ...[
          const SizedBox(height: 16),
          _Note(widget.message!),
        ],
        const SizedBox(height: 28),
        _Tap(
          onTap: () => dialogs.openUrl(_cabinetUrl),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Text(
              'Нет аккаунта? Зарегистрироваться',
              textAlign: TextAlign.center,
              style: TextStyle(color: _yellow, fontSize: 14),
            ),
          ),
        ),
        _Tap(
          onTap: busy ? null : widget.onPaste,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Text(
              'У меня есть ссылка подписки',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

class _Input extends StatefulWidget {
  const _Input({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboard = TextInputType.text,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType keyboard;
  final VoidCallback? onSubmitted;

  @override
  State<_Input> createState() => _InputState();
}

class _InputState extends State<_Input> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line),
        ),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (_, value, _) => value.text.isEmpty
                  ? Text(
                      widget.hint,
                      style: const TextStyle(color: _muted, fontSize: 15),
                    )
                  : const SizedBox.shrink(),
            ),
            EditableText(
              controller: widget.controller,
              focusNode: _focus,
              obscureText: widget.obscure,
              keyboardType: widget.keyboard,
              autocorrect: false,
              style: const TextStyle(
                color: _white,
                fontSize: 15,
                decoration: TextDecoration.none,
              ),
              cursorColor: _yellow,
              backgroundCursorColor: _muted,
              selectionColor: _yellow.withValues(alpha: 0.35),
              onSubmitted: (_) => widget.onSubmitted?.call(),
            ),
          ],
        ),
      ),
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
          textDirection: TextDirection.ltr,
          style: TextStyle(
            decoration: TextDecoration.none,
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


/// Screens with sample data for the screenshot check in CI.
@visibleForTesting
Widget a2Preview({required String screen}) {
  final group = Group(
    type: GroupType.Selector,
    name: 'A2',
    all: const [
      Proxy(name: '🇫🇮 Финляндия', type: 'vless'),
      Proxy(name: '🇩🇪 Германия', type: 'vless'),
      Proxy(name: '🇸🇪 Швеция', type: 'vless'),
      Proxy(name: '🇺🇸 США', type: 'vless'),
      Proxy(name: '🇷🇺 Россия', type: 'vless'),
    ],
  );
  final Widget body = switch (screen) {
    'login' => _Onboarding(
      busy: false,
      message: null,
      onPaste: () {},
      onTelegram: () {},
      onBrowser: () {},
      onEmail: (_, _) {},
    ),
    _ => _ConnectedBody(
      isStart: screen == 'on',
      group: group,
      selected: '🇫🇮 Финляндия',
      delays: const {
        '🇫🇮 Финляндия': 48,
        '🇩🇪 Германия': 62,
        '🇸🇪 Швеция': 71,
        '🇺🇸 США': 154,
        '🇷🇺 Россия': -1,
      },
      profile: null,
      onToggle: () {},
      onSelect: (_, _) {},
      onRefresh: () {},
    ),
  };
  return DefaultTextStyle(
    style: _baseText,
    child: ColoredBox(
      color: _black,
      child: Column(
        children: [
          _Header(onSettings: () {}),
          Expanded(child: body),
        ],
      ),
    ),
  );
}
