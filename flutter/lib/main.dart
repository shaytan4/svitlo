import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const String _scheduleUrl =
    'https://www.uz.gov.ua/about/activity/electropostachannia/'
    'electro_consumers/temporary_shutdown/grafikiobmezhen/622296/';

// Light theme palette — inspired by modern iOS tracker apps
const Color clrBackground = Color(0xFFF2F4FB);
const Color clrCard       = Color(0xFFFFFFFF);
const Color clrPrimary    = Color(0xFF6C5ECF); // violet
const Color clrPrimaryBg  = Color(0xFFEEEAFB); // light violet tint
const Color clrGreen      = Color(0xFF34C77B);
const Color clrGreenBg    = Color(0xFFE8F9F0);
const Color clrRed        = Color(0xFFF05C5C);
const Color clrRedBg      = Color(0xFFFFECEC);
const Color clrText       = Color(0xFF1A1640);
const Color clrSubtext    = Color(0xFF9491B4);
const Color clrBorder     = Color(0xFFE8E8F0);
// legacy aliases (kept for any remaining refs)
const Color clrForeground = clrText;
const Color clrButton     = clrPrimaryBg;
const Color clrInputBg    = clrPrimaryBg;
const Color clrGray       = clrSubtext;

// ─── Data types ───────────────────────────────────────────────────────────────

enum PowerStatus { light, off }

class ScheduleRow {
  final String hours;
  final List<String> queues;
  const ScheduleRow({required this.hours, required this.queues});
}

// ─── Parsing ──────────────────────────────────────────────────────────────────

/// Returns every "Години відключення" table on the page, in page order
/// (first — today, second — tomorrow, if published).
Future<List<List<ScheduleRow>>> parseUZSchedule() async {
  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(_scheduleUrl));
    request.headers.addAll({
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64; rv:133.0) Gecko/20100101 Firefox/133.0',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'uk-UA,uk;q=0.9,en-US;q=0.8,en;q=0.7',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
      'DNT': '1',
    });

    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw Exception('HTTP error: ${response.statusCode}');
    }

    final body = await response.stream.bytesToString();
    final doc = html_parser.parse(body);

    final tables = doc.querySelectorAll('table');
    final result = <List<ScheduleRow>>[];

    for (final table in tables) {
      final rows = table.querySelectorAll('tr');
      if (rows.length < 2) continue;

      final firstCell = rows[0].querySelectorAll('td').isNotEmpty
          ? rows[0].querySelectorAll('td')[0].text.trim()
          : '';

      if (!firstCell.contains('Години відключення')) continue;

      List<String> hoursCells = [];
      List<List<String>> queueCells = [];

      // Row 0: time intervals (skip first cell)
      final tds0 = rows[0].querySelectorAll('td');
      for (int j = 1; j < tds0.length; j++) {
        final text = tds0[j].text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).join(' ');
        hoursCells.add(text);
      }

      // Row 1: queues per slot
      final tds1 = rows[1].querySelectorAll('td');
      for (int j = 1; j < tds1.length; j++) {
        final cell = tds1[j];
        final pTags = cell.querySelectorAll('p');
        List<String> cellQueues;
        if (pTags.isNotEmpty) {
          cellQueues = pTags
              .map((p) => p.text.trim())
              .where((s) => s.isNotEmpty)
              .toList();
        } else {
          cellQueues = cell.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        }
        queueCells.add(cellQueues);
      }

      if (hoursCells.isEmpty) continue;

      result.add(List.generate(hoursCells.length, (i) {
        return ScheduleRow(
          hours: hoursCells[i],
          queues: i < queueCells.length ? queueCells[i] : [],
        );
      }));
    }

    if (result.isEmpty) {
      throw Exception('Не вдалося знайти таблицю з розкладом відключень');
    }

    return result;
  } finally {
    client.close();
  }
}

// ─── Logic helpers ────────────────────────────────────────────────────────────

/// Parses "09-00 11-00" or "9:00 11:00" → (startMin, endMin) or null.
(int, int)? parseHourRange(String s) {
  final parts = s.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;

  int? parse(String t) {
    t = t.replaceAll(':', '-');
    final m = RegExp(r'^(\d+)-(\d+)$').firstMatch(t);
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return null;
    return h * 60 + min;
  }

  final start = parse(parts.first);
  final end = parse(parts.last);
  if (start == null || end == null) return null;
  return (start, end);
}

bool isCurrentTimeInRange(String hours) {
  final range = parseHourRange(hours);
  if (range == null) return false;
  final now = DateTime.now();
  final cur = now.hour * 60 + now.minute;
  return cur >= range.$1 && cur < range.$2;
}

PowerStatus slotStatus(String selected, List<String> queues) {
  return queues.contains(selected) ? PowerStatus.off : PowerStatus.light;
}

({PowerStatus status, int remainingSec, bool found}) currentSlotInfo(
    String selected, List<ScheduleRow> rows) {
  final now = DateTime.now();
  final curMin = now.hour * 60 + now.minute;
  final curSec = now.second;

  for (final row in rows) {
    final range = parseHourRange(row.hours);
    if (range == null) continue;
    if (curMin >= range.$1 && curMin < range.$2) {
      final remaining = (range.$2 - curMin) * 60 - curSec;
      return (
        status: slotStatus(selected, row.queues),
        remainingSec: remaining,
        found: true,
      );
    }
  }
  return (status: PowerStatus.light, remainingSec: 0, found: false);
}

List<String> collectQueues(List<ScheduleRow> rows) {
  final seen = <String>{};
  final result = <String>[];
  for (final row in rows) {
    for (final q in row.queues) {
      if (q.isNotEmpty && seen.add(q)) result.add(q);
    }
  }
  return result;
}

bool isNetworkError(Object err) {
  if (err is SocketException) return true;
  final s = err.toString().toLowerCase();
  return s.contains('no such host') ||
      s.contains('connection refused') ||
      s.contains('network is unreachable') ||
      s.contains('failed host lookup');
}

String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  return '${h.toString().padLeft(2, '0')}:'
      '${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')}';
}

// ─── Entry point ──────────────────────────────────────────────────────────────

void main() {
  runApp(const SvitloApp());
}

class SvitloApp extends StatelessWidget {
  const SvitloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '⚡ Svitlo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: clrBackground,
        colorScheme: const ColorScheme.light(
          surface: clrBackground,
          primary: clrPrimary,
          secondary: clrGreen,
        ),
        cardColor: clrCard,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: clrText, fontSize: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: clrPrimary,
            foregroundColor: Color(0xFFFFFFFF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ─── Home page ────────────────────────────────────────────────────────────────

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _Tab { today, tomorrow, settings }

class _HomePageState extends State<HomePage> {
  static const String _prefsQueueKey = 'selectedQueue';

  List<ScheduleRow> _rows = [];
  List<ScheduleRow> _tomorrowRows = [];
  List<String> _queues = [];
  String _selectedQueue = '1(1,2)';
  String _statusText = '';
  bool _loading = false;
  _Tab _tab = _Tab.today;

  // Countdown state
  PowerStatus? _countdownStatus;
  int _remainingSec = 0;
  bool _countdownFound = false;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startTicker();
    _restoreQueue().then((_) => _load());
  }

  Future<void> _restoreQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsQueueKey);
    if (saved != null && mounted) setState(() => _selectedQueue = saved);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_rows.isEmpty) return;
      final info = currentSlotInfo(_selectedQueue, _rows);
      setState(() {
        _countdownFound = info.found;
        _countdownStatus = info.found ? info.status : null;
        _remainingSec = info.remainingSec;
      });
    });
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _statusText = 'Завантаження...';
      _rows = [];
      _tomorrowRows = [];
      _countdownFound = false;
    });

    try {
      final tables = await parseUZSchedule();
      final rows = tables.first;
      final tomorrowRows = tables.length > 1 ? tables[1] : <ScheduleRow>[];
      final queues = collectQueues([...rows, ...tomorrowRows]);

      final info = currentSlotInfo(_selectedQueue, rows);

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _tomorrowRows = tomorrowRows;
        _queues = queues;
        _statusText = 'Оновлено: ${_nowTime()}';
        _loading = false;
        _countdownFound = info.found;
        _countdownStatus = info.found ? info.status : null;
        _remainingSec = info.remainingSec;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusText = isNetworkError(err)
            ? '❌ No internet connection'
            : '❌ Помилка: $err';
      });
    }
  }

  String _nowTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  void _selectQueue(String q) {
    setState(() {
      _selectedQueue = q;
      final info = currentSlotInfo(q, _rows);
      _countdownFound = info.found;
      _countdownStatus = info.found ? info.status : null;
      _remainingSec = info.remainingSec;
    });
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_prefsQueueKey, q));
  }

  Future<void> _openSite() async {
    final ok = await launchUrl(Uri.parse(_scheduleUrl),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не вдалося відкрити сайт')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: clrBackground,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            ...switch (_tab) {
              _Tab.today => [
                  _buildCountdownCard(),
                  _buildStatusBar(),
                  Expanded(child: _buildScheduleList()),
                ],
              _Tab.tomorrow => [
                  _buildStatusBar(),
                  Expanded(child: _buildTomorrowList()),
                ],
              _Tab.settings => [
                  Expanded(child: _buildSettings()),
                ],
            },
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── Bottom bar ──

  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: clrCard,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Color(0xFF000000).withAlpha(25),
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            _bottomItem(Icons.today_rounded, 'Сьогодні',
                _tab == _Tab.today, () => setState(() => _tab = _Tab.today)),
            _bottomItem(Icons.event_rounded, 'Завтра',
                _tab == _Tab.tomorrow, () => setState(() => _tab = _Tab.tomorrow)),
            _bottomItem(Icons.tune_rounded, 'Налаштування',
                _tab == _Tab.settings, () => setState(() => _tab = _Tab.settings)),
            _bottomItem(Icons.open_in_new_rounded, 'Сайт', false, _openSite),
          ],
        ),
      ),
    );
  }

  Widget _bottomItem(
      IconData icon, String label, bool selected, VoidCallback onTap) {
    final color = selected ? clrPrimary : clrSubtext;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? clrPrimaryBg : Color(0x00000000),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B6ADE), Color(0xFF9F8FEF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF6C5ECF).withAlpha(70),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚡', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'UZ Hodosivka · Svitlo',
                  style: TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _load,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color(0x30FFFFFF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            color: Color(0xFFFFFFFF),
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded,
                          color: Color(0xFFFFFFFF), size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => setState(() => _tab = _Tab.settings),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Color(0x28FFFFFF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Група $_selectedQueue',
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Settings ──

  Widget _buildSettings() {
    final options = {..._queues, _selectedQueue}.toList()..sort();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, 16 + MediaQuery.paddingOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: clrCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: clrBorder, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Оберіть групу',
              style: TextStyle(
                color: clrText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((q) {
                final isSelected = q == _selectedQueue;
                return GestureDetector(
                  onTap: () => _selectQueue(q),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? clrPrimary : clrPrimaryBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      q,
                      style: TextStyle(
                        color: isSelected ? Color(0xFFFFFFFF) : clrPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Countdown card ──

  Widget _buildCountdownCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _countdownFound && _countdownStatus != null
            ? _countdownActive(_countdownStatus!, _remainingSec)
            : _countdownEmpty(),
      ),
    );
  }

  Widget _countdownEmpty() {
    return Container(
      key: const ValueKey('empty'),
      height: 110,
      decoration: BoxDecoration(
        color: clrCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF000000).withAlpha(12),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: _loading
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    color: clrPrimary, strokeWidth: 2.5))
            : Text('—',
                style: TextStyle(color: clrSubtext, fontSize: 36)),
      ),
    );
  }

  Widget _countdownActive(PowerStatus status, int remaining) {
    final isLight = status == PowerStatus.light;
    final accent = isLight ? clrGreen : clrRed;
    final bgColor = isLight ? clrGreenBg : clrRedBg;
    final label = isLight ? 'Є світло ще' : 'Відключення ще';
    final icon = isLight ? '💡' : '🚫';

    return Container(
      key: ValueKey(status),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent.withAlpha(60),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(30),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          // Timer section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(icon, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  formatDuration(remaining),
                  style: TextStyle(
                    color: accent,
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [const FontFeature.tabularFigures()],
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          // Refresh button
          GestureDetector(
            onTap: _load,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withAlpha(25),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withAlpha(60), width: 1),
              ),
              child: Icon(Icons.refresh_rounded, color: accent, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status bar ──

  Widget _buildStatusBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        _statusText,
        style: const TextStyle(color: clrSubtext, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Schedule list ──

  Widget _buildScheduleList() {
    if (_rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentIdx = _rows.indexWhere((r) => isCurrentTimeInRange(r.hours));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Text(
            'Розклад відключень',
            style: TextStyle(
              color: clrText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: _ScheduleListView(
            rows: _rows,
            selectedQueue: _selectedQueue,
            currentIdx: currentIdx,
          ),
        ),
      ],
    );
  }

  Widget _buildTomorrowList() {
    if (_rows.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_tomorrowRows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 40, 20, 0),
        child: Text(
          'Графік на завтра ще не опубліковано',
          textAlign: TextAlign.center,
          style: TextStyle(color: clrSubtext, fontSize: 15),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Text(
            'Розклад на завтра',
            style: TextStyle(
              color: clrText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: _ScheduleListView(
            rows: _tomorrowRows,
            selectedQueue: _selectedQueue,
            currentIdx: -1,
            highlightCurrent: false,
          ),
        ),
      ],
    );
  }
}

// ─── Schedule list view with auto-scroll ─────────────────────────────────────

class _ScheduleListView extends StatefulWidget {
  final List<ScheduleRow> rows;
  final String selectedQueue;
  final int currentIdx;
  final bool highlightCurrent;

  const _ScheduleListView({
    required this.rows,
    required this.selectedQueue,
    required this.currentIdx,
    this.highlightCurrent = true,
  });

  @override
  State<_ScheduleListView> createState() => _ScheduleListViewState();
}

class _ScheduleListViewState extends State<_ScheduleListView> {
  final ScrollController _scrollCtrl = ScrollController();
  static const double _cardHeight = 76.0;

  @override
  void initState() {
    super.initState();
    _scrollToCurrentSlot();
  }

  @override
  void didUpdateWidget(_ScheduleListView old) {
    super.didUpdateWidget(old);
    if (old.currentIdx != widget.currentIdx ||
        old.rows.length != widget.rows.length) {
      _scrollToCurrentSlot();
    }
  }

  void _scrollToCurrentSlot() {
    if (widget.currentIdx < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          widget.currentIdx * _cardHeight,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollCtrl,
      // Extra bottom padding so the last card isn't hidden by the floating bar.
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.paddingOf(context).bottom),
      itemCount: widget.rows.length,
      itemExtent: _cardHeight,
      itemBuilder: (_, i) {
        final row = widget.rows[i];
        final status = slotStatus(widget.selectedQueue, row.queues);
        final isCurrent =
            widget.highlightCurrent && isCurrentTimeInRange(row.hours);
        return _TimeCard(hours: row.hours, status: status, isCurrent: isCurrent);
      },
    );
  }
}

// ─── Time card widget ─────────────────────────────────────────────────────────

class _TimeCard extends StatelessWidget {
  final String hours;
  final PowerStatus status;
  final bool isCurrent;

  const _TimeCard({
    required this.hours,
    required this.status,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = status == PowerStatus.light;
    final accent = isLight ? clrGreen : clrRed;
    final statusText = isLight ? 'Є світло' : 'Відключення';
    final statusIcon = isLight ? '💡' : '🚫';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: isCurrent
              ? (isLight ? clrGreenBg : clrRedBg)
              : clrCard,
          borderRadius: BorderRadius.circular(16),
          border: isCurrent
              ? Border.all(color: accent.withAlpha(100), width: 1.5)
              : Border.all(color: clrBorder, width: 1),
          boxShadow: isCurrent
              ? [
                  BoxShadow(
                    color: accent.withAlpha(30),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Color(0xFF000000).withAlpha(8),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Left accent pill
            Container(
              width: 5,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Hours
            SizedBox(
              width: 108,
              child: Text(
                hours,
                style: TextStyle(
                  color: clrText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Status
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(statusIcon, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 5),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Dot badge
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withAlpha(80),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
