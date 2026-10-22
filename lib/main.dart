import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MafiaApp());
}

enum Role { mafia, doctor, detective, citizen }

enum Phase {
  setup,
  revealCard,
  nightHandoff,
  nightAction,
  detectiveResult,
  nightReport,
  discussion,
  votingHandoff,
  voting,
  voteResult,
  finished,
}

String roleName(Role role) {
  switch (role) {
    case Role.mafia:
      return 'مافيا';
    case Role.doctor:
      return 'طبيب';
    case Role.detective:
      return 'محقق';
    case Role.citizen:
      return 'مواطن';
  }
}

class Player {
  Player({
    required this.name,
    this.role = Role.citizen,
    this.alive = true,
  });

  final String name;
  Role role;
  bool alive;
}

class MafiaApp extends StatelessWidget {
  const MafiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFE11D2E);
    return MaterialApp(
      title: 'Mafia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: red,
          brightness: Brightness.dark,
        ).copyWith(
          primary: red,
          secondary: const Color(0xFFFF3B4E),
          surface: const Color(0xFF141418),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0A0C),
          elevation: 0,
          centerTitle: true,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF17171C),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: red, width: 1.4),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: red,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xFFE6E6EA)),
        ),
      ),
      home: const MafiaHome(),
    );
  }
}

class MafiaHome extends StatefulWidget {
  const MafiaHome({super.key});

  @override
  State<MafiaHome> createState() => _MafiaHomeState();
}

class _MafiaHomeState extends State<MafiaHome> with TickerProviderStateMixin {
  Phase phase = Phase.setup;

  final TextEditingController namesController = TextEditingController();

  List<Player> players = [];
  final Map<String, List<String>> savedGroups = {};

  int mafiaCount = 1;
  int doctorCount = 1;
  int detectiveCount = 1;

  bool allowDoctorSelfProtection = false;
  bool useDiscussionTimer = false;
  int discussionSeconds = 60;

  int revealIndex = 0;
  int nightActorIndex = 0;
  int voterIndex = 0;
  int dayNumber = 1;
  int votingRound = 1;

  List<Player> nightActors = [];
  List<Player> votingCandidates = [];
  List<Player> voters = [];

  final Map<String, String> mafiaVotes = {};
  final Map<String, String> nightShots = {};
  final Map<String, String> doctorProtections = {};
  final Map<String, String> detectiveChecks = {};
  final Map<String, String> lastAccusers = {};
  final Map<String, String> dayVotes = {};

  String? detectiveResultText;
  String? nightReportText;
  String? voteResultText;
  String? winnerText;

  Timer? discussionTimer;
  int remainingSeconds = 60;

  bool cardFlipped = false;
  AnimationController? _cardController;
  Animation<double>? _cardAnimation;

  @override
  void initState() {
    super.initState();
    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _cardAnimation =
        CurvedAnimation(parent: _cardController!, curve: Curves.easeInOut);
    _loadGroups();
  }

  @override
  void dispose() {
    discussionTimer?.cancel();
    _cardController?.dispose();
    namesController.dispose();
    super.dispose();
  }

  Future<void> _saveGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final lines = savedGroups.entries.map((e) {
      final encodedPlayers = e.value.map(Uri.encodeComponent).join(',');
      return '${Uri.encodeComponent(e.key)}|$encodedPlayers';
    }).toList();
    await prefs.setStringList('mafia_saved_groups', lines);
  }

  Future<void> _loadGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final lines = prefs.getStringList('mafia_saved_groups') ?? [];
    for (final l in lines) {
      final i = l.indexOf('|');
      if (i < 0) continue;
      final n = Uri.decodeComponent(l.substring(0, i));
      final p = l.substring(i + 1);
      savedGroups[n] = p.isEmpty
          ? <String>[]
          : p.split(',').map(Uri.decodeComponent).toList();
    }
    if (mounted) setState(() {});
  }

  void _showMessage(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  void _hapticLight() => HapticFeedback.lightImpact();

  List<String> get enteredNames => namesController.text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  void _startGame() {
    final names = enteredNames;
    final uniq = names.toSet();
    if (names.length < 4 || names.length > 20) {
      _showMessage('عدد اللاعبين لازم من 4 إلى 20.');
      return;
    }
    if (uniq.length != names.length) {
      _showMessage('توجد أسماء مكررة.');
      return;
    }
    if (mafiaCount < 1) {
      _showMessage('لازم مافيا واحدة على الأقل.');
      return;
    }
    if (mafiaCount + doctorCount + detectiveCount >= names.length) {
      _showMessage('لازم يبقى مواطن واحد على الأقل.');
      return;
    }

    final roles = <Role>[
      ...List.filled(mafiaCount, Role.mafia),
      ...List.filled(doctorCount, Role.doctor),
      ...List.filled(detectiveCount, Role.detective),
      ...List.filled(
        names.length - mafiaCount - doctorCount - detectiveCount,
        Role.citizen,
      ),
    ];

    // توزيع عشوائي بحت
    final rng = Random.secure();
    roles.shuffle(rng);
    final shuffledNames = List<String>.from(names)..shuffle(rng);

    players = List.generate(
      shuffledNames.length,
      (i) => Player(name: shuffledNames[i], role: roles[i]),
    );

    revealIndex = 0;
    nightActorIndex = 0;
    voterIndex = 0;
    dayNumber = 1;
    votingRound = 1;
    winnerText = null;
    lastAccusers.clear();
    dayVotes.clear();
    mafiaVotes.clear();
    nightShots.clear();
    doctorProtections.clear();
    detectiveChecks.clear();
    cardFlipped = false;
    _cardController?.reset();
    phase = Phase.revealCard;
    setState(() {});
  }

  Player get revealPlayer => players[revealIndex];

  List<Player> _livingAllies(Player p) => players
      .where((x) => x.alive && x.role == p.role && x.name != p.name)
      .toList();

  void _flipCard() {
    if (cardFlipped) return;
    _hapticLight();
    _cardController?.forward();
    setState(() => cardFlipped = true);
  }

  void _nextRevealPlayer() {
    if (revealIndex < players.length - 1) {
      _cardController?.reset();
      setState(() {
        revealIndex++;
        cardFlipped = false;
      });
    } else {
      _beginNight();
    }
  }

  // ---------------- Night ----------------
  /// ترتيب إجراءات الليل: كل الأحياء بترتيب عشوائي بحت.
  /// كل لاعب يصوّت "شك" ليلي. المافيا شكّها = قرار القتل.
  /// الطبيب يحمي والمحقق يفحص بعد شكّهم.
  void _beginNight() {
    discussionTimer?.cancel();

    mafiaVotes.clear();
    nightShots.clear();
    doctorProtections.clear();
    detectiveChecks.clear();
    detectiveResultText = null;
    nightReportText = null;

    final living = players.where((p) => p.alive).toList();
    final rng = Random.secure();
    living.shuffle(rng);

    nightActors = living;
    nightActorIndex = 0;
    setState(() => phase = Phase.nightHandoff);
  }

  Player get currentNightActor => nightActors[nightActorIndex];

  void _confirmNightActorIdentity() {
    _hapticLight();
    setState(() => phase = Phase.nightAction);
  }

  void _advanceNightActor() {
    if (nightActorIndex < nightActors.length - 1) {
      nightActorIndex++;
      phase = Phase.nightHandoff;
      setState(() {});
    } else {
      _resolveNight();
    }
  }

  /// تصويت الشك الليلي (كل اللاعبين)
  void _submitNightShot(String targetName) {
    final actor = currentNightActor;

    nightShots[actor.name] = targetName;
    lastAccusers[targetName] = actor.name;

    // المافيا: صوتها = قرار القتل
    if (actor.role == Role.mafia) {
      mafiaVotes[actor.name] = targetName;
    }

    // إجراء إضافي خاص بالطبيب/المحقق بعد الشك
    if (actor.role == Role.doctor || actor.role == Role.detective) {
      setState(() {});
    } else {
      _advanceNightActor();
    }
  }

  void _submitDoctorProtection(String targetName) {
    doctorProtections[currentNightActor.name] = targetName;
    _advanceNightActor();
  }

  void _submitDetectiveCheck(String targetName) {
    detectiveChecks[currentNightActor.name] = targetName;
    final target = players.firstWhere((p) => p.name == targetName);
    detectiveResultText = 'دور $targetName هو: ${roleName(target.role)}.';
    setState(() => phase = Phase.detectiveResult);
  }

  void _closeDetectiveResult() {
    _advanceNightActor();
  }

  String? _resolveMafiaTarget() {
    if (mafiaVotes.isEmpty) return null;
    for (final m in players) {
      if (m.alive && m.role == Role.mafia) {
        final v = mafiaVotes[m.name];
        if (v != null) return v;
      }
    }
    return mafiaVotes.values.first;
  }

  String? _resolveDoctorTarget() {
    if (doctorProtections.isEmpty) return null;
    for (final d in players) {
      if (d.alive && d.role == Role.doctor) {
        final t = doctorProtections[d.name];
        if (t != null) return t;
      }
    }
    return doctorProtections.values.first;
  }

  void _resolveNight() {
    String report = 'انتهى الليل.';
    final mafiaTarget = _resolveMafiaTarget();
    final doctorTarget = _resolveDoctorTarget();

    if (mafiaTarget != null) {
      final victim = players.firstWhere((p) => p.name == mafiaTarget);

      if (doctorTarget == mafiaTarget) {
        report = 'حاولت المافيا استهداف $mafiaTarget، لكن الطبيب أنقذه.';
      } else {
        victim.alive = false;
        final accuser = lastAccusers[mafiaTarget];
        final showAccuser = accuser != null && victim.role != Role.mafia;
        report = 'قُتل $mafiaTarget — كان ${roleName(victim.role)}.'
            '${showAccuser ? '\nآخر شخص شك فيه قبل خروجه كان $accuser.' : ''}';
      }
    }

    nightReportText = report;

    final winner = _checkWinner();
    setState(() {
      if (winner != null) {
        winnerText = winner;
        phase = Phase.finished;
      } else {
        phase = Phase.nightReport;
      }
    });
  }

  String? _checkWinner() {
    final mafiaAlive =
        players.where((p) => p.alive && p.role == Role.mafia).length;
    final nonMafiaAlive =
        players.where((p) => p.alive && p.role != Role.mafia).length;
    if (mafiaAlive == 0) return 'فاز المواطنون!';
    if (nonMafiaAlive <= mafiaAlive) return 'فازت المافيا!';
    return null;
  }

  // ---------------- Discussion & voting ----------------
  void _startDiscussion() {
    remainingSeconds = discussionSeconds;
    setState(() => phase = Phase.discussion);

    discussionTimer?.cancel();
    if (useDiscussionTimer) {
      discussionTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (remainingSeconds <= 1) {
          t.cancel();
          setState(() => remainingSeconds = 0);
        } else {
          setState(() => remainingSeconds--);
        }
      });
    }
  }

  void _startVoting({List<Player>? candidates}) {
    discussionTimer?.cancel();

    votingCandidates = candidates ?? players.where((p) => p.alive).toList();
    voters = players.where((p) => p.alive).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    voterIndex = 0;
    dayVotes.clear();
    setState(() => phase = Phase.votingHandoff);
  }

  Player get currentVoter => voters[voterIndex];

  void _confirmVoterIdentity() {
    _hapticLight();
    setState(() => phase = Phase.voting);
  }

  void _submitDayVote(String? targetName) {
    final v = currentVoter.name;
    if (targetName == null) {
      dayVotes.remove(v);
    } else {
      dayVotes[v] = targetName;
      lastAccusers[targetName] = v;
    }

    if (voterIndex < voters.length - 1) {
      voterIndex++;
      setState(() => phase = Phase.votingHandoff);
    } else {
      _finishVoting();
    }
  }

  void _finishVoting() {
    final counts = <String, int>{};
    for (final t in dayVotes.values) {
      counts[t] = (counts[t] ?? 0) + 1;
    }

    if (counts.isEmpty) {
      voteResultText = 'لم يصوّت أحد. لم يخرج أحد.';
      setState(() => phase = Phase.voteResult);
      return;
    }

    final maxV = counts.values.reduce(max);
    final tied = counts.entries
        .where((e) => e.value == maxV)
        .map((e) => e.key)
        .toList();

    if (tied.length > 1) {
      if (votingRound == 1) {
        votingRound = 2;
        final alive = players.where((p) => p.alive).toList();
        if (alive.length < 2) {
          voteResultText = 'تعادل. لم يخرج أحد.';
          setState(() => phase = Phase.voteResult);
        } else {
          voteResultText =
              'تعادل بين: ${tied.join('، ')}.\nإعادة تصويت بين كل الأحياء.';
          _showTieAndRevote(alive);
        }
      } else {
        voteResultText = 'استمر التعادل. لم يخرج أحد.';
        setState(() => phase = Phase.voteResult);
      }
      return;
    }

    final out = tied.first;
    final el = players.firstWhere((p) => p.name == out);
    el.alive = false;
    final accuser = lastAccusers[out];
    final showAccuser = accuser != null && el.role != Role.mafia;
    voteResultText = 'خرج $out — كان ${roleName(el.role)}.'
        '${showAccuser ? '\nآخر شخص شك فيه قبل خروجه كان $accuser.' : ''}';

    final winner = _checkWinner();
    setState(() {
      if (winner != null) {
        winnerText = winner;
        phase = Phase.finished;
      } else {
        phase = Phase.voteResult;
      }
    });
  }

  void _showTieAndRevote(List<Player> alive) {
    setState(() => phase = Phase.voteResult);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17171C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('تعادل'),
        content: const Text('إعادة تصويت بين كل الأحياء.'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startVoting(
                candidates: players.where((p) => p.alive).toList(),
              );
            },
            child: const Text('إعادة التصويت'),
          ),
        ],
      ),
    );
  }

  void _continueAfterVote() {
    votingRound = 1;
    dayNumber++;
    _beginNight();
  }

  Future<void> _saveCurrentGroup() async {
    final names = enteredNames;
    if (names.isEmpty) {
      _showMessage('اكتب أسماء أولًا.');
      return;
    }

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF17171C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('حفظ المجموعة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم المجموعة'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    setState(() => savedGroups[name] = names);
    await _saveGroups();
    _showMessage('تم الحفظ.');
  }

  Future<void> _deleteGroup(String name) async {
    setState(() => savedGroups.remove(name));
    await _saveGroups();
  }

  void _loadGroupIntoNames(String name) {
    final list = savedGroups[name];
    if (list == null) return;
    namesController.text = list.join('\n');
    setState(() {});
  }

  void _restartGame() {
    discussionTimer?.cancel();
    players = [];
    nightActors = [];
    voters = [];
    revealIndex = 0;
    nightActorIndex = 0;
    voterIndex = 0;
    dayNumber = 1;
    votingRound = 1;
    mafiaVotes.clear();
    nightShots.clear();
    doctorProtections.clear();
    detectiveChecks.clear();
    lastAccusers.clear();
    dayVotes.clear();
    detectiveResultText = null;
    nightReportText = null;
    voteResultText = null;
    winnerText = null;
    cardFlipped = false;
    _cardController?.reset();
    setState(() => phase = Phase.setup);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'M A F I A',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
              fontSize: 18,
            ),
          ),
          actions: [
            if (phase != Phase.setup)
              IconButton(
                onPressed: _restartGame,
                icon: const Icon(Icons.restart_alt),
              ),
          ],
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _buildCurrentPage(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentPage() {
    switch (phase) {
      case Phase.setup:
        return _buildSetup();
      case Phase.revealCard:
        return _buildRevealCard();
      case Phase.nightHandoff:
        return _buildNightHandoff();
      case Phase.nightAction:
        return _buildNightAction();
      case Phase.detectiveResult:
        return _buildDetectiveResult();
      case Phase.nightReport:
        return _buildNightReport();
      case Phase.discussion:
        return _buildDiscussion();
      case Phase.votingHandoff:
        return _buildVotingHandoff();
      case Phase.voting:
        return _buildVoting();
      case Phase.voteResult:
        return _buildVoteResult();
      case Phase.finished:
        return _buildFinished();
    }
  }

  Widget _page({required Widget child}) => SingleChildScrollView(
        key: ValueKey(phase),
        padding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Center(child: child),
        ),
      );

  Widget _panel({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF17171C), Color(0xFF101014)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: child,
      );

  Widget _primaryButton({
    required String label,
    required VoidCallback? onPressed,
    IconData icon = Icons.arrow_forward,
  }) =>
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _fingerprint({
    required String playerName,
    required VoidCallback onVerified,
  }) {
    return _page(
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Icon(
            Icons.phonelink_lock,
            size: 64,
            color: Color(0xFFE11D2E),
          ),
          const SizedBox(height: 20),
          Text(
            'سلّم الهاتف إلى $playerName',
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          const Text(
            'اضغط البصمة للتأكيد',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () {
              _hapticLight();
              onVerified();
            },
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFFE11D2E), Color(0xFF5A0A13)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE11D2E).withOpacity(0.5),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.fingerprint,
                size: 80,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetup() {
    return _page(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE11D2E), Color(0xFF6D0813)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Column(
              children: [
                Icon(Icons.masks, size: 64, color: Colors.white),
                SizedBox(height: 8),
                Text(
                  'M A F I A',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('أسماء اللاعبين',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                TextField(
                  controller: namesController,
                  minLines: 4,
                  maxLines: 10,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'اسم واحد بكل سطر...',
                  ),
                ),
                const SizedBox(height: 8),
                Text('العدد: ${enteredNames.length}',
                    style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _saveCurrentGroup,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ المجموعة'),
                ),
                if (savedGroups.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...savedGroups.keys.map(
                    (n) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(n),
                      subtitle: Text('${savedGroups[n]?.length ?? 0} لاعبين'),
                      leading: const Icon(Icons.groups_2),
                      onTap: () => _loadGroupIntoNames(n),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteGroup(n),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _panel(
            child: Column(
              children: [
                _counter('مافيا', mafiaCount, (v) => setState(() => mafiaCount = v),
                    min: 1, color: const Color(0xFFE11D2E)),
                _counter('أطباء', doctorCount,
                    (v) => setState(() => doctorCount = v),
                    min: 0, color: Colors.lightBlueAccent),
                _counter('محققون', detectiveCount,
                    (v) => setState(() => detectiveCount = v),
                    min: 0, color: Colors.amber),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('الطبيب يحمي نفسه'),
                  value: allowDoctorSelfProtection,
                  onChanged: (v) =>
                      setState(() => allowDoctorSelfProtection = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('مؤقت النقاش'),
                  value: useDiscussionTimer,
                  onChanged: (v) => setState(() => useDiscussionTimer = v),
                ),
                if (useDiscussionTimer)
                  Slider(
                    value: discussionSeconds.toDouble(),
                    min: 30,
                    max: 300,
                    divisions: 18,
                    label: '$discussionSeconds ث',
                    onChanged: (v) =>
                        setState(() => discussionSeconds = v.round()),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _primaryButton(
            label: 'ابدأ اللعبة',
            icon: Icons.play_arrow_rounded,
            onPressed: _startGame,
          ),
        ],
      ),
    );
  }

  Widget _counter(String t, int v, ValueChanged<int> onChanged,
      {required int min, required Color color}) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(t)),
        IconButton(
          onPressed: v > min ? () => onChanged(v - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 28,
          child: Text('$v',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        IconButton(
          onPressed: v < 20 ? () => onChanged(v + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  Widget _buildRevealCard() {
    final player = revealPlayer;
    final allies = _livingAllies(player);
    final extra = player.role == Role.citizen
        ? 'حاول اكتشاف المافيا.'
        : allies.isEmpty
            ? 'أنت الوحيد بهذا الدور.'
            : 'رفاقك:\n${allies.map((p) => '• ${p.name}').join('\n')}';

    return _page(
      child: Column(
        children: [
          Text(
            'دور ${player.name}',
            style:
                const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          Text(
            '${revealIndex + 1} / ${players.length}',
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _flipCard,
            child: AnimatedBuilder(
              animation: _cardAnimation ?? const AlwaysStoppedAnimation(0),
              builder: (_, __) {
                final angle = (_cardAnimation?.value ?? 0) * pi;
                final back = angle >= pi / 2;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(angle),
                  child: back
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(pi),
                          child: _roleCard(player, extra),
                        )
                      : _cardBack(),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          if (cardFlipped)
            _primaryButton(
              label: revealIndex < players.length - 1
                  ? 'اللاعب التالي'
                  : 'ابدأ الليل',
              onPressed: _nextRevealPlayer,
            )
          else
            const Text(
              'اضغط البطاقة لقلبها',
              style: TextStyle(color: Colors.white60),
            ),
        ],
      ),
    );
  }

  Widget _cardBack() => Container(
        width: 260,
        height: 360,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A20), Color(0xFF0E0E12)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
              color: const Color(0xFFE11D2E).withOpacity(0.5), width: 2),
        ),
        child: const Center(
          child: Icon(
            Icons.help_outline_rounded,
            size: 100,
            color: Color(0xFFE11D2E),
          ),
        ),
      );

  Widget _roleCard(Player p, String extra) {
    final mafia = p.role == Role.mafia;
    return Container(
      width: 260,
      height: 360,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: mafia
              ? const [Color(0xFFE11D2E), Color(0xFF4A050C)]
              : const [Color(0xFF232330), Color(0xFF12121A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            mafia
                ? Icons.local_fire_department
                : p.role == Role.doctor
                    ? Icons.health_and_safety
                    : p.role == Role.detective
                        ? Icons.manage_search
                        : Icons.person,
            size: 64,
            color: Colors.white,
          ),
          const SizedBox(height: 14),
          Text(
            roleName(p.role),
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            extra,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNightHandoff() {
    return _fingerprint(
      playerName: currentNightActor.name,
      onVerified: _confirmNightActorIdentity,
    );
  }

  Widget _buildNightAction() {
    final actor = currentNightActor;
    final hasShot = nightShots.containsKey(actor.name);

    if (hasShot && actor.role == Role.doctor) {
      return _doctorExtra(actor);
    }
    if (hasShot && actor.role == Role.detective) {
      return _detectiveExtra(actor);
    }

    return _page(
      child: Column(
        children: [
          const Icon(Icons.nightlight_round,
              size: 56, color: Color(0xFFE11D2E)),
          const SizedBox(height: 12),
          const Text('تصويت الشك الليلي',
              style:
                  TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('اللاعب: ${actor.name}',
              style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 20),
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'اختر لاعبًا تشك فيه هذه الليلة. سرّي بالكامل.',
                  style: TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 12),
                ..._eligibleNightTargets(actor).map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _targetButton(
                      t.name,
                      () => _submitNightShot(t.name),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Player> _eligibleNightTargets(Player actor) {
    return players.where((p) {
      if (!p.alive) return false;
      if (p.name == actor.name) return false;
      if (actor.role == Role.citizen) return true;
      return p.role != actor.role;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Widget _doctorExtra(Player actor) {
    final targets = players.where((p) {
      if (!p.alive) return false;
      if (!allowDoctorSelfProtection && p.name == actor.name) return false;
      return p.role != Role.doctor || p.name == actor.name;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return _page(
      child: Column(
        children: [
          const Icon(Icons.health_and_safety,
              size: 56, color: Colors.lightBlueAccent),
          const SizedBox(height: 12),
          const Text('إجراء الطبيب',
              style:
                  TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 20),
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('اختر لاعبًا لحمايته هذه الليلة.'),
                const SizedBox(height: 12),
                ...targets.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _targetButton(
                      t.name,
                      () => _submitDoctorProtection(t.name),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detectiveExtra(Player actor) {
    final targets = _eligibleNightTargets(actor);
    return _page(
      child: Column(
        children: [
          const Icon(Icons.manage_search, size: 56, color: Colors.amber),
          const SizedBox(height: 12),
          const Text('إجراء المحقق',
              style:
                  TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 20),
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('افحص لاعبًا. النتيجة سرية.'),
                const SizedBox(height: 12),
                ...targets.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _targetButton(
                      t.name,
                      () => _submitDetectiveCheck(t.name),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectiveResult() => _page(
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Icon(Icons.search, size: 60, color: Colors.amber),
            const SizedBox(height: 16),
            const Text('نتيجة الفحص',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            _panel(
              child: Text(
                detectiveResultText ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 20),
            _primaryButton(
              label: 'متابعة',
              icon: Icons.lock,
              onPressed: _closeDetectiveResult,
            ),
          ],
        ),
      );

  Widget _buildNightReport() => _page(
        child: Column(
          children: [
            const SizedBox(height: 30),
            const Icon(Icons.nights_stay,
                size: 60, color: Colors.indigoAccent),
            const SizedBox(height: 16),
            const Text('انتهى الليل',
                style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 18),
            _panel(
              child: Text(
                nightReportText ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19),
              ),
            ),
            const SizedBox(height: 22),
            _primaryButton(
              label: 'ابدأ النقاش',
              icon: Icons.forum_outlined,
              onPressed: _startDiscussion,
            ),
          ],
        ),
      );

  Widget _buildDiscussion() {
    final sorted = players.where((p) => p.alive).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return _page(
      child: Column(
        children: [
          const Icon(Icons.forum, size: 56, color: Colors.lightBlueAccent),
          const SizedBox(height: 12),
          Text('النقاش — اليوم $dayNumber',
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          if (useDiscussionTimer)
            _panel(
              child: Column(
                children: [
                  const Text('الوقت',
                      style: TextStyle(color: Colors.white60)),
                  Text(
                    '${remainingSeconds ~/ 60}:${(remainingSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontSize: 40, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            )
          else
            _panel(
              child: const Text(
                'ناقشوا، ثم انتقلوا للتصويت النهاري على من يخرج.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ),
          const SizedBox(height: 16),
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('الأحياء',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                ...sorted.map(
                  (p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(p.name),
                    trailing: const Icon(Icons.circle,
                        size: 9, color: Colors.greenAccent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _primaryButton(
            label: 'ابدأ التصويت النهاري',
            icon: Icons.how_to_vote,
            onPressed: () => _startVoting(),
          ),
        ],
      ),
    );
  }

  Widget _buildVotingHandoff() {
    if (voters.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finishVoting();
      });
      return _page(child: const Text('لا يوجد ناخبون.'));
    }
    return _fingerprint(
      playerName: currentVoter.name,
      onVerified: _confirmVoterIdentity,
    );
  }

  Widget _buildVoting() {
    if (voters.isEmpty || voterIndex >= voters.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finishVoting();
      });
      return _page(child: const Text('انتهى التصويت.'));
    }

    final v = currentVoter;
    final eligible = votingCandidates
        .where((p) => p.alive && p.name != v.name)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return _page(
      child: Column(
        children: [
          const Icon(Icons.lock, size: 52, color: Colors.amber),
          const SizedBox(height: 10),
          Text('تصويت ${v.name} — من يخرج؟',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...eligible.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _targetButton(
                      t.name,
                      () => _submitDayVote(t.name),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _submitDayVote(null),
                  icon: const Icon(Icons.block),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('امتناع'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoteResult() => _page(
        child: Column(
          children: [
            const SizedBox(height: 30),
            const Icon(Icons.how_to_vote, size: 60, color: Colors.amber),
            const SizedBox(height: 16),
            const Text('نتيجة التصويت',
                style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 18),
            _panel(
              child: Text(
                voteResultText ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19),
              ),
            ),
            const SizedBox(height: 22),
            _primaryButton(
              label: 'الليل التالي',
              icon: Icons.nights_stay,
              onPressed: _continueAfterVote,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _restartGame,
              icon: const Icon(Icons.restart_alt),
              label: const Text('إنهاء اللعبة'),
            ),
          ],
        ),
      );

  Widget _buildFinished() => _page(
        child: Column(
          children: [
            const SizedBox(height: 50),
            const Icon(Icons.emoji_events, size: 86, color: Colors.amber),
            const SizedBox(height: 20),
            Text(
              winnerText ?? 'انتهت',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 20),
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('الأدوار النهائية',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  ...players.map(
                    (p) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        p.alive ? Icons.person : Icons.person_off,
                        color:
                            p.alive ? Colors.greenAccent : Colors.white38,
                      ),
                      title: Text(p.name),
                      subtitle: Text(roleName(p.role)),
                      trailing: Text(p.alive ? 'باقٍ' : 'خرج'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _primaryButton(
              label: 'لعبة جديدة',
              icon: Icons.refresh,
              onPressed: _restartGame,
            ),
          ],
        ),
      );

  Widget _targetButton(String name, VoidCallback onPressed) => SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            alignment: Alignment.centerRight,
            side: BorderSide(color: Colors.white.withOpacity(0.14)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_outline),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name, style: const TextStyle(fontSize: 15)),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      );
}