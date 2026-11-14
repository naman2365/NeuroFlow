import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'models.dart';
import 'providers.dart';

bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('study_logs_box');
  await Hive.openBox('settings_box');

  if (isDesktopPlatform) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1180, 840),
      minimumSize: Size(320, 180),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'NeuroFlow — Cognitive Interleaver',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const ProviderScope(child: FocusTrackerApp()));
}

class FocusTrackerApp extends StatelessWidget {
  const FocusTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroFlow — Cognitive Interleaver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.tealAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _selectedSubject = 'Physics';
  Timer? _timer;
  int _secondsRemaining = 75 * 60;
  int _initialMinutes = 75;
  int _currentSpills = 0;
  bool _isRunning = false;
  bool _isBreakMode = false;
  bool _isMiniHud = false;

  final TextEditingController _doubtCtrl = TextEditingController();
  final ScrollController _chatScrollCtrl = ScrollController();

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isMusicPlaying = false;
  bool _isMusicLoading = false;
  double _volume = 0.6;
  String _selectedStation = 'Lofi Focus Beats';
  String? _localFilePath;
  String? _localFileName;

  final Map<String, String> _directStations = {
    'Lofi Focus Beats': 'https://streams.ilovemusic.de/iloveradio17.mp3',
    'Deep Ambient Drone': 'https://ice2.somafm.com/dronezone-128-mp3',
    'Synthwave Coding': 'https://ice2.somafm.com/spacestation-128-mp3',
    'Classical Study': 'https://live.musopen.org:8085/streamvbr0',
    'Local Audio File': 'local',
  };

  @override
  void initState() {
    super.initState();
    _audioPlayer.setReleaseMode(ReleaseMode.loop);

    final settingsBox = Hive.box('settings_box');
    _localFilePath = settingsBox.get('local_audio_path') as String?;
    _localFileName = settingsBox.get('local_audio_name') as String?;
  }

  void _scrollToLatestChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(
          _chatScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendDoubtOrRequest([String? presetPrompt]) async {
    final textToSend = presetPrompt ?? _doubtCtrl.text;
    if (textToSend.trim().isEmpty) return;

    if (presetPrompt == null) {
      _doubtCtrl.clear();
    }
    _scrollToLatestChat();

    await ref.read(aiCoachProvider.notifier).askAssistant(
          userMessage: textToSend,
          currentSubject: _selectedSubject,
        );
    _scrollToLatestChat();
  }

  Future<void> _pickLocalAudioFile() async {
    const XTypeGroup audioTypeGroup = XTypeGroup(
      label: 'Audio Files',
      extensions: <String>['mp3', 'wav', 'm4a', 'flac', 'ogg', 'aac'],
    );

    final XFile? file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[audioTypeGroup],
    );

    if (file != null) {
      final String path = file.path;
      final String name = file.name;

      final settingsBox = Hive.box('settings_box');
      await settingsBox.put('local_audio_path', path);
      await settingsBox.put('local_audio_name', name);

      setState(() {
        _localFilePath = path;
        _localFileName = name;
        _selectedStation = 'Local Audio File';
        _isMusicLoading = true;
      });

      try {
        await _audioPlayer.stop();
        await _audioPlayer.setVolume(_volume);
        await _audioPlayer.play(DeviceFileSource(path));
        setState(() {
          _isMusicPlaying = true;
          _isMusicLoading = false;
        });
      } catch (e) {
        setState(() => _isMusicLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not play local file: $e')),
          );
        }
      }
    }
  }

  Future<void> _toggleDirectMusic() async {
    if (_isMusicPlaying) {
      await _audioPlayer.pause();
      setState(() => _isMusicPlaying = false);
    } else {
      if (_selectedStation == 'Local Audio File') {
        if (_localFilePath == null) {
          await _pickLocalAudioFile();
          return;
        }
        setState(() => _isMusicLoading = true);
        try {
          await _audioPlayer.setVolume(_volume);
          await _audioPlayer.play(DeviceFileSource(_localFilePath!));
          setState(() {
            _isMusicPlaying = true;
            _isMusicLoading = false;
          });
        } catch (e) {
          setState(() => _isMusicLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Local file error: $e')),
            );
          }
        }
      } else {
        setState(() => _isMusicLoading = true);
        try {
          final streamUrl = _directStations[_selectedStation]!;
          await _audioPlayer.setVolume(_volume);
          await _audioPlayer.play(UrlSource(streamUrl));
          setState(() {
            _isMusicPlaying = true;
            _isMusicLoading = false;
          });
        } catch (e) {
          setState(() => _isMusicLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Stream error: $e')),
            );
          }
        }
      }
    }
  }

  Future<void> _changeStation(String? newStation) async {
    if (newStation == null) return;
    setState(() => _selectedStation = newStation);

    if (newStation == 'Local Audio File') {
      if (_localFilePath == null) {
        await _pickLocalAudioFile();
        return;
      }
      if (_isMusicPlaying) {
        setState(() => _isMusicLoading = true);
        await _audioPlayer.stop();
        await _audioPlayer.play(DeviceFileSource(_localFilePath!));
        setState(() => _isMusicLoading = false);
      }
      return;
    }

    if (_isMusicPlaying) {
      setState(() => _isMusicLoading = true);
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(_directStations[newStation]!));
      setState(() => _isMusicLoading = false);
    }
  }

  Future<void> _toggleMiniHud() async {
    if (!isDesktopPlatform) return;
    if (!_isMiniHud) {
      setState(() => _isMiniHud = true);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setMinimumSize(const Size(330, 195));
      await windowManager.setSize(const Size(330, 195));
    } else {
      setState(() => _isMiniHud = false);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMinimumSize(const Size(600, 650));
      await windowManager.setSize(const Size(1180, 840));
      await windowManager.center();
    }
  }

  void _setTimerDuration(int minutes, {bool isBreak = false}) {
    if (_isRunning) return;
    HapticFeedback.selectionClick();
    setState(() {
      _isBreakMode = isBreak;
      _initialMinutes = minutes;
      _secondsRemaining = minutes * 60;
      if (!isBreak) _currentSpills = 0;
    });
  }

  void _toggleTimer() {
    HapticFeedback.mediumImpact();
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
    } else {
      setState(() => _isRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsRemaining > 0) {
          setState(() => _secondsRemaining--);
        } else {
          _completeSession();
        }
      });
    }
  }

  void _incrementSpill() {
    HapticFeedback.lightImpact();
    setState(() => _currentSpills++);
  }

  Future<void> _launchMusicUrl(String urlString) async {
    final uri = Uri.tryParse(urlString);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $urlString')),
        );
      }
    }
  }

  /// Help & Direct-to-Developer Feedback Dialog (With PIN-Locked Creator Inbox)
  void _showHelpAndFeedbackDialog() {
    final nameCtrl = TextEditingController(
      text: ref.read(studyLogsProvider.notifier).syncId,
    );
    final msgCtrl = TextEditingController();
    final adminPinCtrl = TextEditingController();

    String selectedCategory = 'Feature Request';
    int rating = 5;
    bool isSending = false;

    bool isCreatorUnlocked = false;
    bool isUnlocking = false;
    String? unlockError;
    List<FeedbackItem> unlockedFeedbacks = <FeedbackItem>[];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return DefaultTabController(
            length: 3,
            child: AlertDialog(
              title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_outline, color: Colors.tealAccent),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'NeuroFlow Guide & Feedback',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: 'Send Feedback'),
                      Tab(text: 'How It Works'),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_outline, size: 14),
                            SizedBox(width: 4),
                            Text('Creator Inbox'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                height: 360,
                child: TabBarView(
                  children: [
                    // TAB 1: SEND FEEDBACK TO PRATYUSH
                    SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Found a bug or have an idea for NeuroFlow? Your feedback is sent directly to Pratyush\'s Creator Inbox!',
                            style:
                                TextStyle(fontSize: 12.5, color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: nameCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Your Name / Handle',
                                    hintText: 'e.g., Rahul',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              DropdownButton<String>(
                                value: selectedCategory,
                                items: [
                                  'Feature Request',
                                  'Bug Report',
                                  'UI / Design',
                                  'Appreciation',
                                ].map((c) {
                                  return DropdownMenuItem(
                                    value: c,
                                    child: Text(
                                      c,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => selectedCategory = val);
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Text(
                                'Rating: ',
                                style: TextStyle(fontSize: 12.5),
                              ),
                              ...List.generate(5, (i) {
                                return IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () =>
                                      setDialogState(() => rating = i + 1),
                                  icon: Icon(
                                    i < rating
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: Colors.amberAccent,
                                    size: 20,
                                  ),
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: msgCtrl,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Your Feedback or Suggestion',
                              hintText:
                                  'Tell me what you love or what we should add next...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: isSending
                                    ? null
                                    : () async {
                                        if (msgCtrl.text.trim().isEmpty) return;
                                        setDialogState(() => isSending = true);
                                        final sent = await ref
                                            .read(studyLogsProvider.notifier)
                                            .submitFeedbackToCloud(
                                              sender: nameCtrl.text,
                                              category: selectedCategory,
                                              rating: rating,
                                              message: msgCtrl.text,
                                            );
                                        setDialogState(() => isSending = false);
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                sent
                                                    ? '🎉 Feedback delivered straight to Pratyush\'s Cloud Inbox!'
                                                    : 'Saved! You can also click "Send via Email" to notify Pratyush.',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                icon: const Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 17,
                                ),
                                label: Text(
                                  isSending
                                      ? 'Sending...'
                                      : 'Submit to Creator Inbox',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final subject = Uri.encodeComponent(
                                    '[NeuroFlow $selectedCategory] from ${nameCtrl.text.isEmpty ? "User" : nameCtrl.text} ($rating/5 ★)',
                                  );
                                  final body =
                                      Uri.encodeComponent(msgCtrl.text);
                                  final mailUri = Uri.parse(
                                    'mailto:$kDeveloperFeedbackEmail?subject=$subject&body=$body',
                                  );
                                  await launchUrl(mailUri);
                                },
                                icon:
                                    const Icon(Icons.email_outlined, size: 16),
                                label: const Text('Send via Email'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // TAB 2: QUICK GUIDE FOR FRIENDS / USERS
                    ListView(
                      children: const [
                        ListTile(
                          leading:
                              Icon(Icons.shuffle, color: Colors.tealAccent),
                          title: Text('1. Cognitive Interleaving'),
                          subtitle: Text(
                            'Instead of grinding one subject for 6 hours, alternate between 3 subjects (45–90m blocks) to boost long-term retention.',
                          ),
                        ),
                        ListTile(
                          leading: Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orangeAccent,
                          ),
                          title: Text('2. Working Memory Spills'),
                          subtitle: Text(
                            'Tap the "Memory Spill" button whenever you catch your mind wandering or checking your phone. NeuroFlow auto-adjusts your next block duration.',
                          ),
                        ),
                        ListTile(
                          leading: Icon(
                            Icons.bookmark_outline,
                            color: Colors.amberAccent,
                          ),
                          title: Text('3. 5-Word Breadcrumbs'),
                          subtitle: Text(
                            'When finishing a block, write a 5-word note on where to start next (e.g. "Start Q15 rotational dynamics"). Your Groq Mentor uses this to quiz and guide you!',
                          ),
                        ),
                        ListTile(
                          leading: Icon(
                            Icons.lock_outline,
                            color: Colors.tealAccent,
                          ),
                          title: Text('4. PIN-Protected Cloud Sync'),
                          subtitle: Text(
                            'Click the Cloud Sync icon in the top bar and set a unique Username + PIN on both your PC and Android phone to keep your logs mirrored.',
                          ),
                        ),
                      ],
                    ),

                    // TAB 3: PIN-LOCKED CREATOR INBOX (ONLY PRATYUSH CAN UNLOCK)
                    if (!isCreatorUnlocked)
                      Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.admin_panel_settings_outlined,
                                size: 44,
                                color: Colors.tealAccent,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Creator Inbox is PIN-Protected',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Restricted to the creator (Pratyush). Enter your secret Creator PIN to read user feedback.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white60,
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: 260,
                                child: TextField(
                                  controller: adminPinCtrl,
                                  obscureText: true,
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    labelText: 'Creator PIN',
                                    errorText: unlockError,
                                    prefixIcon: const Icon(
                                      Icons.key,
                                      color: Colors.tealAccent,
                                    ),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: isUnlocking
                                    ? null
                                    : () async {
                                        setDialogState(() {
                                          isUnlocking = true;
                                          unlockError = null;
                                        });
                                        try {
                                          final items = await ref
                                              .read(studyLogsProvider.notifier)
                                              .fetchFeedbackInbox(
                                                adminPinCtrl.text,
                                              );
                                          setDialogState(() {
                                            isUnlocking = false;
                                            isCreatorUnlocked = true;
                                            unlockedFeedbacks = items;
                                          });
                                        } catch (e) {
                                          setDialogState(() {
                                            isUnlocking = false;
                                            unlockError =
                                                'Invalid Creator PIN!';
                                          });
                                        }
                                      },
                                icon: const Icon(Icons.lock_open, size: 17),
                                label: Text(
                                  isUnlocking
                                      ? 'Verifying...'
                                      : 'Unlock Creator Inbox',
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (unlockedFeedbacks.isEmpty)
                      const Center(
                        child: Text(
                          'Inbox unlocked! No feedback messages submitted yet.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    else
                      ListView.builder(
                        itemCount: unlockedFeedbacks.length,
                        itemBuilder: (context, i) {
                          final fb = unlockedFeedbacks[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                '${fb.sender} • ${fb.category} (${fb.rating}★)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.tealAccent,
                                ),
                              ),
                              subtitle: Text(fb.message),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showStudentProfileDialog() {
    final currentGoal = ref.read(aiCoachProvider).userProfileGoal;
    final goalCtrl = TextEditingController(text: currentGoal);
    final keyCtrl = TextEditingController(
      text: ref.read(aiCoachProvider.notifier).groqApiKey,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.psychology, color: Colors.tealAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Personalize Groq Mentor & Goals',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tell your Groq Mentor your grade, target exams, and preferred learning style so every doubt explanation and study plan is tailored to you:',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: goalCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Your Academic Profile & Learning Style',
                    hintText:
                        'e.g., Class 11 PCM + CS student preparing for JEE 2028 & SAT. Explain concepts from first principles.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: keyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Custom Groq Key (Optional - gsk_...)',
                    hintText: 'Leave empty to use default NeuroFlow Groq Cloud',
                    prefixIcon: Icon(Icons.vpn_key_outlined, size: 18),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await ref
                  .read(aiCoachProvider.notifier)
                  .saveUserProfileGoal(goalCtrl.text);
              await ref
                  .read(aiCoachProvider.notifier)
                  .saveGroqApiKey(keyCtrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save Profile'),
          ),
        ],
      ),
    );
  }

  void _showMusicSettingsDialog() {
    final currentMusic = ref.read(musicSettingsProvider);
    final spCtrl = TextEditingController(text: currentMusic.spotifyUrl);
    final ytCtrl = TextEditingController(text: currentMusic.ytMusicUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Customize External Shortcuts'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: spCtrl,
                decoration: const InputDecoration(
                  labelText: 'Spotify Playlist / Track URL',
                  prefixIcon: Icon(Icons.album, color: Colors.greenAccent),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ytCtrl,
                decoration: const InputDecoration(
                  labelText: 'YouTube Music Playlist / Search URL',
                  prefixIcon:
                      Icon(Icons.play_circle_fill, color: Colors.redAccent),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(musicSettingsProvider.notifier)
                  .updateUrls(spCtrl.text, ytCtrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save Links'),
          ),
        ],
      ),
    );
  }

  void _showCloudSyncDialog() {
    final notifier = ref.read(studyLogsProvider.notifier);
    final syncIdCtrl = TextEditingController(text: notifier.syncId);
    final syncPinCtrl = TextEditingController(text: notifier.syncPin);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.tealAccent),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'PIN-Protected Cloud Sync',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your Sync ID is locked to the first PIN/Password you set. Nobody can view or overwrite your logs without your PIN.',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: syncIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Sync ID / Username',
                  hintText: 'e.g., pratyush',
                  prefixIcon:
                      Icon(Icons.person_outline, color: Colors.tealAccent),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: syncPinCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Secret PIN / Password',
                  hintText: 'Enter a 4+ digit PIN or password',
                  prefixIcon: Icon(Icons.password, color: Colors.tealAccent),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await ref
                  .read(studyLogsProvider.notifier)
                  .configureCloudflareSync(syncIdCtrl.text, syncPinCtrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            icon: const Icon(Icons.sync_lock, size: 18),
            label: const Text('Lock & Sync Now'),
          ),
        ],
      ),
    );
  }

  void _completeSession() {
    _timer?.cancel();
    HapticFeedback.heavyImpact();
    setState(() => _isRunning = false);

    if (_isMiniHud) {
      _toggleMiniHud();
    }

    if (_isBreakMode) {
      final nextStudyMins = ref.read(recommendedDurationProvider);
      _setTimerDuration(nextStudyMins, isBreak: false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Break complete! Ready for your next interleaved block.'),
        ),
      );
      return;
    }

    final elapsedMins = _initialMinutes - (_secondsRemaining ~/ 60);
    final actualDuration = elapsedMins > 0 ? elapsedMins : _initialMinutes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => LogBottomSheet(
        subject: _selectedSubject,
        durationMinutes: actualDuration,
        memorySpills: _currentSpills,
        onSaved: (nextBreakMins) {
          _setTimerDuration(nextBreakMins, isBreak: true);
        },
      ),
    );
  }

  void _showAddSubjectDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Interleaving Subject'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g., Kalaripayattu, Organic Chem, DSA',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                ref.read(subjectsProvider.notifier).addSubject(ctrl.text);
                setState(() => _selectedSubject = ctrl.text.trim());
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Widget _buildFormattedMessageText(String rawText) {
    final RegExp boldPattern = RegExp(r'\*\*([^*]+)\*\*');
    final List<TextSpan> spans = [];
    int currentIndex = 0;

    for (final match in boldPattern.allMatches(rawText)) {
      if (match.start > currentIndex) {
        spans.add(
          TextSpan(text: rawText.substring(currentIndex, match.start)),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.tealAccent,
          ),
        ),
      );
      currentIndex = match.end;
    }

    if (currentIndex < rawText.length) {
      spans.add(TextSpan(text: rawText.substring(currentIndex)));
    }

    return SelectableText.rich(
      TextSpan(
        style: const TextStyle(
          fontSize: 12.8,
          color: Color(0xFFEFF3F6),
          height: 1.48,
        ),
        children: spans,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    _doubtCtrl.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isMiniHud) {
      return _buildMiniHudScaffold();
    }

    final logs = ref.watch(studyLogsProvider);
    final subjects = ref.watch(subjectsProvider);
    final recommendedMins = ref.watch(recommendedDurationProvider);
    final recommendedBreak = ref.watch(recommendedBreakProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final musicSettings = ref.watch(musicSettingsProvider);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: GestureDetector(
          onPanStart: (_) {
            if (isDesktopPlatform) windowManager.startDragging();
          },
          onDoubleTap: () async {
            if (isDesktopPlatform) {
              if (await windowManager.isMaximized()) {
                windowManager.unmaximize();
              } else {
                windowManager.maximize();
              }
            }
          },
          child: AppBar(
            backgroundColor: const Color(0xFF14181B),
            elevation: 0,
            leading: const Icon(
              Icons.hub_outlined,
              color: Colors.tealAccent,
              size: 20,
            ),
            titleSpacing: 0,
            title: Row(
              children: [
                const Text(
                  'NeuroFlow',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: InkWell(
                    onTap: _showCloudSyncDialog,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            syncStatus.contains('Synced') ||
                                    syncStatus.contains('Connected')
                                ? Icons.cloud_done
                                : Icons.cloud_off,
                            size: 13,
                            color: syncStatus.contains('Synced') ||
                                    syncStatus.contains('Connected')
                                ? Colors.tealAccent
                                : Colors.white54,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              syncStatus,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (isDesktopPlatform)
                IconButton(
                  tooltip: 'Pin Always-On-Top Mini HUD',
                  icon: const Icon(
                    Icons.picture_in_picture_alt_outlined,
                    size: 19,
                    color: Colors.tealAccent,
                  ),
                  onPressed: _toggleMiniHud,
                ),
              IconButton(
                tooltip: 'Cloud Sync Settings',
                icon: const Icon(Icons.sync, size: 19),
                onPressed: _showCloudSyncDialog,
              ),
              IconButton(
                tooltip: 'Switch Study / Break Mode',
                icon: Icon(
                  _isBreakMode ? Icons.self_improvement : Icons.psychology,
                  size: 20,
                ),
                onPressed: _isRunning
                    ? null
                    : () {
                        if (_isBreakMode) {
                          _setTimerDuration(recommendedMins, isBreak: false);
                        } else {
                          _setTimerDuration(recommendedBreak, isBreak: true);
                        }
                      },
              ),
              IconButton(
                tooltip: 'Help & Send Feedback',
                icon: const Icon(
                  Icons.help_outline_rounded,
                  size: 19,
                  color: Colors.amberAccent,
                ),
                onPressed: _showHelpAndFeedbackDialog,
              ),
              if (isDesktopPlatform) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Minimize',
                  icon: const Icon(Icons.minimize, size: 18),
                  onPressed: () => windowManager.minimize(),
                ),
                IconButton(
                  tooltip: 'Maximize / Restore',
                  icon: const Icon(Icons.crop_square, size: 16),
                  onPressed: () async {
                    if (await windowManager.isMaximized()) {
                      windowManager.unmaximize();
                    } else {
                      windowManager.maximize();
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Close',
                  hoverColor: Colors.redAccent,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => windowManager.close(),
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 850;
            if (isDesktop) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        child: _buildTimerPanel(
                          logs,
                          subjects,
                          recommendedMins,
                          recommendedBreak,
                          musicSettings,
                          isMobile: false,
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 32),
                    Expanded(
                      flex: 6,
                      child: _buildAnalyticsAndLogsPanel(
                        logs,
                        isDesktop: true,
                      ),
                    ),
                  ],
                ),
              );
            } else {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 14.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTimerPanel(
                      logs,
                      subjects,
                      recommendedMins,
                      recommendedBreak,
                      musicSettings,
                      isMobile: true,
                    ),
                    const Divider(height: 36),
                    _buildAnalyticsAndLogsPanel(
                      logs,
                      isDesktop: false,
                    ),
                  ],
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildMiniHudScaffold() {
    final accentColor = _isBreakMode ? Colors.amberAccent : Colors.tealAccent;
    return Scaffold(
      backgroundColor: const Color(0xFF101417),
      body: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: accentColor.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.push_pin, size: 14, color: accentColor),
                      const SizedBox(width: 6),
                      Text(
                        _isBreakMode ? 'RECOVERY BREAK' : _selectedSubject,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Toggle Focus Music',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          _isMusicPlaying
                              ? Icons.music_note
                              : Icons.music_off_outlined,
                          size: 16,
                          color: _isMusicPlaying
                              ? Colors.tealAccent
                              : Colors.white54,
                        ),
                        onPressed: _toggleDirectMusic,
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: 'Expand Full Workstation',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.open_in_full, size: 16),
                        onPressed: _toggleMiniHud,
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                _formatTime(_secondsRemaining),
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: _isBreakMode ? Colors.amberAccent : Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _toggleTimer,
                    icon: Icon(
                      _isRunning ? Icons.pause : Icons.play_arrow,
                      size: 16,
                    ),
                    label: Text(_isRunning ? 'Pause' : 'Start'),
                  ),
                  if (!_isBreakMode)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _incrementSpill,
                      icon: const Icon(
                        Icons.warning_amber_rounded,
                        size: 15,
                        color: Colors.orangeAccent,
                      ),
                      label: Text('Spill ($_currentSpills)'),
                    ),
                  IconButton(
                    tooltip: 'Finish & Log',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.check_circle_outline,
                      color: Colors.tealAccent,
                    ),
                    onPressed: _completeSession,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimerPanel(
    List<StudyBlockLog> logs,
    List<String> subjects,
    int recommendedMins,
    int recommendedBreak,
    MusicSettings musicSettings, {
    required bool isMobile,
  }) {
    final accentColor = _isBreakMode ? Colors.amberAccent : Colors.tealAccent;
    final aiState = ref.watch(aiCoachProvider);

    final latestSubjectLog =
        logs.where((l) => l.subject == _selectedSubject).firstOrNull;

    return Column(
      children: [
        Card(
          color: accentColor.withValues(alpha: 0.12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            leading: Icon(
              _isBreakMode ? Icons.coffee : Icons.bolt,
              color: accentColor,
            ),
            title: Text(
              _isBreakMode
                  ? 'Active Recovery Break ($recommendedBreak mins)'
                  : 'Recommended Next Block: $recommendedMins mins',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              _isBreakMode
                  ? (recommendedBreak >= 25
                      ? 'High strain: Perform 20m NSDR or take a zero-screen walk.'
                      : 'Step away from screens. Hydrate & do light mobility.')
                  : (logs.isEmpty
                      ? 'No blocks logged yet today.'
                      : 'Last fatigue: ${logs.first.fatigueScore}/5 (${logs.first.subject}) • Spills: ${logs.first.memorySpills}'),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: TextButton(
              onPressed: () => _setTimerDuration(
                _isBreakMode ? recommendedBreak : recommendedMins,
                isBreak: _isBreakMode,
              ),
              child: const Text('Apply'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!_isBreakMode)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ...subjects.map((subject) {
                final isSelected = _selectedSubject == subject;
                return ChoiceChip(
                  label: Text(subject),
                  selected: isSelected,
                  onSelected: _isRunning
                      ? null
                      : (_) => setState(() => _selectedSubject = subject),
                );
              }),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: _isRunning ? null : _showAddSubjectDialog,
              ),
            ],
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _isBreakMode
                ? 'RECOVERY & NSDR MODE'
                : 'DEEP FOCUS: $_selectedSubject',
            style: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _formatTime(_secondsRemaining),
            style: TextStyle(
              fontSize: isMobile ? 56 : 64,
              fontWeight: FontWeight.bold,
              color: _isBreakMode ? Colors.amberAccent : Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: (_isBreakMode ? [10, 15, 25] : [45, 75, 90]).map((mins) {
            return OutlinedButton(
              onPressed: _isRunning
                  ? null
                  : () => _setTimerDuration(mins, isBreak: _isBreakMode),
              child: Text('${mins}m'),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        if (!_isBreakMode)
          Padding(
            padding: const EdgeInsets.only(bottom: 10.0),
            child: OutlinedButton.icon(
              onPressed: _incrementSpill,
              icon: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orangeAccent,
                size: 18,
              ),
              label: Text(
                'Memory Spill / Distraction ($_currentSpills)',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _toggleTimer,
              icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
              label: Text(
                _isRunning
                    ? 'Pause'
                    : (_isBreakMode ? 'Start Break' : 'Start Block'),
              ),
            ),
            TextButton.icon(
              onPressed: _completeSession,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(_isBreakMode ? 'Skip Break' : 'Finish & Log Now'),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Card(
          color: Colors.white.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: _isMusicPlaying
                  ? Colors.tealAccent.withValues(alpha: 0.5)
                  : Colors.white12,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: _isMusicLoading ? null : _toggleDirectMusic,
                      icon: _isMusicLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _isMusicPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedStation,
                          isExpanded: true,
                          isDense: true,
                          items: _directStations.keys.map((station) {
                            final label = (station == 'Local Audio File' &&
                                    _localFileName != null)
                                ? 'Local: $_localFileName'
                                : 'In-App: $station';
                            return DropdownMenuItem(
                              value: station,
                              child: Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: _changeStation,
                        ),
                      ),
                    ),
                    if (!isMobile) ...[
                      const Icon(
                        Icons.volume_down,
                        size: 16,
                        color: Colors.white54,
                      ),
                      SizedBox(
                        width: 85,
                        child: Slider(
                          value: _volume,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (val) {
                            setState(() => _volume = val);
                            _audioPlayer.setVolume(val);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                if (isMobile)
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.volume_down,
                        size: 16,
                        color: Colors.white54,
                      ),
                      Expanded(
                        child: Slider(
                          value: _volume,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (val) {
                            setState(() => _volume = val);
                            _audioPlayer.setVolume(val);
                          },
                        ),
                      ),
                    ],
                  ),
                const Divider(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _pickLocalAudioFile,
                      icon: const Icon(Icons.folder_open, size: 15),
                      label: const Text(
                        'Local File',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Colors.green.withValues(alpha: 0.2),
                            foregroundColor: Colors.greenAccent,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () =>
                              _launchMusicUrl(musicSettings.spotifyUrl),
                          icon: const Icon(Icons.album, size: 14),
                          label: const Text(
                            'Spotify',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.withValues(alpha: 0.2),
                            foregroundColor: Colors.redAccent,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () =>
                              _launchMusicUrl(musicSettings.ytMusicUrl),
                          icon: const Icon(Icons.play_circle_fill, size: 14),
                          label: const Text(
                            'YT Music',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Customize Playlist Links',
                          icon: const Icon(Icons.tune, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: _showMusicSettingsDialog,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          color: const Color(0xFF1A162B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Colors.tealAccent.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: Colors.tealAccent,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Groq $_selectedSubject Mentor & Planner',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Personalize Student Profile & Groq Key',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.person_pin_outlined,
                            size: 18,
                            color: Colors.tealAccent,
                          ),
                          onPressed: _showStudentProfileDialog,
                        ),
                        IconButton(
                          tooltip: 'Clear Chat History',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.cleaning_services_outlined,
                            size: 16,
                            color: Colors.white54,
                          ),
                          onPressed: () => ref
                              .read(aiCoachProvider.notifier)
                              .clearChatHistory(),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: Colors.tealAccent,
                        ),
                        label: const Text(
                          'Plan Next 3 Blocks',
                          style: TextStyle(fontSize: 11),
                        ),
                        onPressed: aiState.isLoading
                            ? null
                            : () => _sendDoubtOrRequest(
                                  'Analyze my recent logs, fatigue scores, memory spills, and breadcrumbs, and create a personalized 3-block interleaved study plan for the next 3 hours.',
                                ),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(
                          Icons.quiz_outlined,
                          size: 14,
                          color: Colors.amberAccent,
                        ),
                        label: Text(
                          'Quiz Me on $_selectedSubject',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: aiState.isLoading
                            ? null
                            : () => _sendDoubtOrRequest(
                                  'Give me 1 engaging conceptual question or numerical problem in $_selectedSubject based on my latest breadcrumb (${latestSubjectLog?.breadcrumb ?? "core concepts"}) using clean Unicode math.',
                                ),
                      ),
                      if (latestSubjectLog != null &&
                          latestSubjectLog.breadcrumb.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(
                            Icons.lightbulb_outline,
                            size: 14,
                            color: Colors.orangeAccent,
                          ),
                          label: const Text(
                            'Resume My Breadcrumb',
                            style: TextStyle(fontSize: 11),
                          ),
                          onPressed: aiState.isLoading
                              ? null
                              : () => _sendDoubtOrRequest(
                                    'My last breadcrumb in $_selectedSubject was "${latestSubjectLog.breadcrumb}". Give me a quick, friendly 3-bullet refresher so I can jump right back in.',
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                Container(
                  height: 215,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF110E1C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: ListView.builder(
                    controller: _chatScrollCtrl,
                    itemCount:
                        aiState.messages.length + (aiState.isLoading ? 1 : 0),
                    itemBuilder: (context, idx) {
                      if (idx == aiState.messages.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.tealAccent,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Groq Mentor is crafting your answer...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.tealAccent,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final msg = aiState.messages[idx];
                      final isUser = msg.role == 'user';

                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          constraints: const BoxConstraints(maxWidth: 440),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Colors.tealAccent.withValues(alpha: 0.16)
                                : const Color(0xFF211D35),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isUser
                                  ? Colors.tealAccent.withValues(alpha: 0.35)
                                  : Colors.white10,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isUser
                                        ? Icons.person_outline
                                        : Icons.school_outlined,
                                    size: 12,
                                    color: isUser
                                        ? Colors.tealAccent
                                        : Colors.amberAccent,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isUser
                                        ? 'You • ${msg.subject}'
                                        : 'Groq Mentor • ${msg.subject}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: isUser
                                          ? Colors.tealAccent
                                          : Colors.amberAccent,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              _buildFormattedMessageText(msg.text),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _doubtCtrl,
                        onSubmitted: (_) => _sendDoubtOrRequest(),
                        style: const TextStyle(fontSize: 12.5),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          hintText:
                              'Ask a $_selectedSubject doubt or custom plan...',
                          hintStyle: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed:
                          aiState.isLoading ? null : () => _sendDoubtOrRequest(),
                      icon: const Icon(Icons.send_rounded, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsAndLogsPanel(
    List<StudyBlockLog> logs, {
    required bool isDesktop,
  }) {
    final totalMins =
        logs.fold<int>(0, (sum, item) => sum + item.durationMinutes);
    final avgFatigue = logs.isEmpty
        ? 0.0
        : logs.fold<int>(0, (sum, item) => sum + item.fatigueScore) /
            logs.length;
    final totalSpills =
        logs.fold<int>(0, (sum, item) => sum + item.memorySpills);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: isDesktop ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Row(
          children: [
            _buildKpiCard('Total Focus', '${totalMins}m', Icons.timer_outlined),
            const SizedBox(width: 8),
            _buildKpiCard(
              'Avg Strain',
              '${avgFatigue.toStringAsFixed(1)}/5',
              Icons.speed,
            ),
            const SizedBox(width: 8),
            _buildKpiCard(
              'Total Spills',
              '$totalSpills',
              Icons.psychology_alt,
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _build14DayHeatmap(logs),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: _buildSubjectBalance(logs, totalMins),
              ),
            ],
          )
        else ...[
          _buildSubjectBalance(logs, totalMins),
          const SizedBox(height: 10),
          _build14DayHeatmap(logs),
        ],
        const SizedBox(height: 14),
        if (logs.isNotEmpty) ...[
          const Text(
            'Fatigue Trend (Last 7 Blocks)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: _buildFatigueChart(
                logs.take(7).toList().reversed.toList(),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        const Text(
          'Recent Interleaved Blocks & Breadcrumbs',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (isDesktop)
          Expanded(
            child: _buildLogsList(logs, shrinkWrap: false),
          )
        else
          _buildLogsList(logs, shrinkWrap: true),
      ],
    );
  }

  Widget _buildLogsList(List<StudyBlockLog> logs, {required bool shrinkWrap}) {
    if (logs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24.0),
        child: Center(
          child: Text('Complete a study block to see logs & charts.'),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: _getFatigueColor(log.fatigueScore),
              child: Text(
                '${log.fatigueScore}',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            title: Text(
              '${log.subject} (${log.durationMinutes}m) • ${log.memorySpills} spills',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              log.breadcrumb.isEmpty
                  ? 'No breadcrumb saved'
                  : 'Next: ${log.breadcrumb}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () =>
                  ref.read(studyLogsProvider.notifier).deleteLog(log.id),
            ),
          ),
        );
      },
    );
  }

  Widget _build14DayHeatmap(List<StudyBlockLog> logs) {
    final now = DateTime.now();
    final days = List.generate(14, (i) {
      final d = now.subtract(Duration(days: 13 - i));
      return DateTime(d.year, d.month, d.day);
    });

    final Map<DateTime, int> dailyMinutes = {};
    for (final log in logs) {
      final key = DateTime(
        log.timestamp.year,
        log.timestamp.month,
        log.timestamp.day,
      );
      dailyMinutes[key] = (dailyMinutes[key] ?? 0) + log.durationMinutes;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '14-Day Consistency',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: days.map((day) {
                final mins = dailyMinutes[day] ?? 0;
                Color boxColor = Colors.white10;
                if (mins >= 180) {
                  boxColor = Colors.tealAccent;
                } else if (mins >= 90) {
                  boxColor = Colors.tealAccent.withValues(alpha: 0.6);
                } else if (mins > 0) {
                  boxColor = Colors.tealAccent.withValues(alpha: 0.3);
                }
                return Tooltip(
                  message: '${day.day}/${day.month}: ${mins}m',
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: boxColor,
                      borderRadius: BorderRadius.circular(4),
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

  Widget _buildSubjectBalance(List<StudyBlockLog> logs, int totalMins) {
    final Map<String, int> subjectMins = {};
    for (final log in logs) {
      subjectMins[log.subject] =
          (subjectMins[log.subject] ?? 0) + log.durationMinutes;
    }

    final entries = subjectMins.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Subject Balance',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Text(
                'No data yet',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              )
            else
              ...entries.take(4).map((e) {
                final ratio =
                    (totalMins > 0 ? e.value / totalMins : 0.0).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.key,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(ratio * 100).toInt()}% (${e.value}m)',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, size: 18, color: Colors.tealAccent),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFatigueChart(List<StudyBlockLog> recentLogs) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 5,
        minY: 0,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (val, _) => Text(
                '${val.toInt()}',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (val, _) {
                final idx = val.toInt();
                if (idx < 0 || idx >= recentLogs.length) {
                  return const SizedBox();
                }
                final shortName = recentLogs[idx].subject.length > 4
                    ? recentLogs[idx].subject.substring(0, 4)
                    : recentLogs[idx].subject;
                return Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(shortName, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(recentLogs.length, (index) {
          final log = recentLogs[index];
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: log.fatigueScore.toDouble(),
                color: _getFatigueColor(log.fatigueScore),
                width: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
      ),
    );
  }

  Color _getFatigueColor(int score) {
    if (score <= 2) return Colors.greenAccent;
    if (score == 3) return Colors.amberAccent;
    return Colors.redAccent;
  }
}

class LogBottomSheet extends ConsumerStatefulWidget {
  final String subject;
  final int durationMinutes;
  final int memorySpills;
  final Function(int nextBreakMinutes) onSaved;

  const LogBottomSheet({
    super.key,
    required this.subject,
    required this.durationMinutes,
    required this.memorySpills,
    required this.onSaved,
  });

  @override
  ConsumerState<LogBottomSheet> createState() => _LogBottomSheetState();
}

class _LogBottomSheetState extends ConsumerState<LogBottomSheet> {
  double _fatigue = 3;
  final TextEditingController _breadcrumbCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Log ${widget.subject} (${widget.durationMinutes}m • ${widget.memorySpills} spills)',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text('Cognitive Fatigue Score: ${_fatigue.toInt()} / 5'),
          Slider(
            value: _fatigue,
            min: 1,
            max: 5,
            divisions: 4,
            label: '${_fatigue.toInt()}',
            onChanged: (val) => setState(() => _fatigue = val),
          ),
          TextField(
            controller: _breadcrumbCtrl,
            decoration: const InputDecoration(
              labelText: '5-Word Breadcrumb (Where to pick up next?)',
              hintText: 'e.g., Completed Q14, start integration by parts',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final log = StudyBlockLog(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                subject: widget.subject,
                timestamp: DateTime.now(),
                durationMinutes: widget.durationMinutes,
                fatigueScore: _fatigue.toInt(),
                memorySpills: widget.memorySpills,
                breadcrumb: _breadcrumbCtrl.text.trim(),
              );
              await ref.read(studyLogsProvider.notifier).addLog(log);
              final nextBreak = ref.read(recommendedBreakProvider);
              widget.onSaved(nextBreak);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Center(
              child: Text('Save Log & Start Recovery Break'),
            ),
          ),
        ],
      ),
    );
  }
}