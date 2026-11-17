import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process, ProcessSignal;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/legacy.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'models.dart';
import 'providers.dart';

bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

bool get isWindowsNative => !kIsWeb && Platform.isWindows;

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Hive.initFlutter();
    await Hive.openBox('study_logs_box');
    await Hive.openBox('settings_box');

    if (isDesktopPlatform) {
      // ignore: deprecated_member_use
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1180, 840),
        minimumSize: Size(320, 180),
        center: true,
        backgroundColor: Color(0xFF14181B),
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        title: 'NeuroFlow — Cognitive Interleaver',
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }

    runApp(const ProviderScope(child: FocusTrackerApp()));
  }, (error, stackTrace) {
    debugPrint('Caught error: $error');
  });
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
  ConsumerState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState {
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

  // For Web & Android only (Never initialized on Windows so flutter_windows.dll never crashes!)
  AudioPlayer? _mobileWebPlayer;

  // For Windows: Isolated OS Background Process (Zero C++ DLL threads inside Flutter!)
  Process? _winAudioProcess;
  StreamSubscription? _winStdoutSub;

  bool _isMusicPlaying = false;
  bool _isMusicLoading = false;
  bool _isLoopOne = false;
  bool _isSeeking = false;
  double _volume = 0.6;
  String _selectedStation = 'Lofi Focus Beats';

  var _localPlaylist = [];
  int _currentLocalIndex = 0;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;

  final _directStations = {
    'Lofi Focus Beats': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    'Chillhop Study Groove': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    'Synthwave Coding': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    'Deep Ambient Flow': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
    'Cyberpunk Matrix': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3',
    'Acoustic Guitar Study': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
    'Classical Piano Focus': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-9.mp3',
    'Deep Space Horizon': 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-10.mp3',
    '24/7 Live Lofi Radio': 'https://streams.ilovemusic.de/iloveradio17.mp3',
    'Local Audio Playlist': 'local',
  };

  @override
  void initState() {
    super.initState();
    final settingsBox = Hive.box('settings_box');
    final savedQueue = settingsBox.get('local_audio_queue');
    if (savedQueue is Iterable) {
      for (final item in savedQueue) {
        if (item is Map) {
          final path = item['path']?.toString() ?? '';
          final name = item['name']?.toString() ?? 'Track';
          if (path.isNotEmpty) {
            _localPlaylist.add({'path': path, 'name': name});
          }
        }
      }
    }
  }

  /// Launches a single hidden Windows PresentationCore audio process that communicates via stdin/stdout.
  /// Because it runs outside focus_fatigue_tracker.exe, it can NEVER crash flutter_windows.dll!
  Future _ensureWindowsAudioBridge() async {
    if (_winAudioProcess != null) return;

    const psScript = r'''
Add-Type -AssemblyName PresentationCore
$player = New-Object System.Windows.Media.MediaPlayer
while ($true) {
  $line = [Console]::In.ReadLine()
  if ($null -eq $line) { break }
  $parts = $line.Split('|', 2)
  $cmd = $parts[0]
  $arg = if ($parts.Length -gt 1) { $parts[1] } else { "" }
  try {
    if ($cmd -eq "OPEN") {
      $player.Open([Uri]$arg)
      $player.Play()
      Write-Output "STATE|PLAYING"
    } elseif ($cmd -eq "PAUSE") {
      $player.Pause()
      Write-Output "STATE|PAUSED"
    } elseif ($cmd -eq "RESUME") {
      $player.Play()
      Write-Output "STATE|PLAYING"
    } elseif ($cmd -eq "STOP") {
      $player.Stop()
      Write-Output "STATE|STOPPED"
    } elseif ($cmd -eq "VOL") {
      $player.Volume = [double]$arg
    } elseif ($cmd -eq "SEEK") {
      $player.Position = [TimeSpan]::FromSeconds([int]$arg)
    } elseif ($cmd -eq "POLL") {
      $pos = [int]$player.Position.TotalSeconds
      $dur = if ($player.NaturalDuration.HasTimeSpan) { [int]$player.NaturalDuration.TimeSpan.TotalSeconds } else { 0 }
      Write-Output "TIME|$pos|$dur"
    }
  } catch {}
}
''';

    final proc = await Process.start(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command', psScript],
    );
    _winAudioProcess = proc;

    _winStdoutSub = proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (!mounted) return;
      if (line.startsWith('TIME|')) {
        final parts = line.split('|');
        if (parts.length >= 3) {
          final pos = int.tryParse(parts[1]) ?? 0;
          final dur = int.tryParse(parts[2]) ?? 0;
          if (!_isSeeking) {
            setState(() {
              _audioPosition = Duration(seconds: pos);
              if (dur >= 1) _audioDuration = Duration(seconds: dur);
            });
          }
          if (dur >= 5 && pos >= dur - 1 && !_isLiveRadioStream) {
            if (_isLoopOne) {
              _playCurrentSelection();
            } else {
              _skipTrack(1);
            }
          }
        }
      }
    });

    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _winAudioProcess == null) {
        t.cancel();
        return;
      }
      if (_isMusicPlaying && !_isSeeking) {
        try {
          _winAudioProcess!.stdin.writeln('POLL|');
        } catch (_) {}
      }
    });
  }

  AudioPlayer _ensureWebOrAndroidPlayer() {
    if (_mobileWebPlayer != null) return _mobileWebPlayer!;
    final p = AudioPlayer();
    p.onDurationChanged.listen((d) {
      if (mounted && d.inSeconds >= 1) setState(() => _audioDuration = d);
    });
    p.onPositionChanged.listen((pos) {
      if (mounted && !_isSeeking && pos.inSeconds != _audioPosition.inSeconds) {
        setState(() => _audioPosition = pos);
      }
    });
    p.onPlayerComplete.listen((_) {
      if (!mounted) return;
      if (_isLoopOne) {
        _playCurrentSelection();
      } else {
        _skipTrack(1);
      }
    });
    _mobileWebPlayer = p;
    return p;
  }

  bool get _isLiveRadioStream => _selectedStation == '24/7 Live Lofi Radio';

  String _formatAudioDuration(Duration d) {
    if (d.inSeconds <= 0 || d.inHours >= 24) return '00:00';
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
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

  Future _sendDoubtOrRequest([String? presetPrompt]) async {
    final textToSend = presetPrompt ?? _doubtCtrl.text;
    if (textToSend.trim().isEmpty) return;
    if (presetPrompt == null) _doubtCtrl.clear();
    _scrollToLatestChat();
    await ref.read(aiCoachProvider.notifier).askAssistant(
          userMessage: textToSend,
          currentSubject: _selectedSubject,
        );
    _scrollToLatestChat();
  }

  Future _pickLocalAudioFile() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local file queue is supported on Windows & Android builds.')),
      );
      return;
    }
    const audioGroup = XTypeGroup(
      label: 'Audio Files',
      extensions: ['mp3', 'wav', 'm4a', 'flac', 'ogg', 'aac'],
    );
    final files = await openFiles(acceptedTypeGroups: [audioGroup]);
    if (files.isNotEmpty) {
      final newTracks = files.map((f) => {'path': f.path, 'name': f.name}).toList();
      await Hive.box('settings_box').put('local_audio_queue', newTracks);
      setState(() {
        _localPlaylist = List.from(newTracks);
        _currentLocalIndex = 0;
        _selectedStation = 'Local Audio Playlist';
      });
      await _playCurrentSelection();
    }
  }

  Future _playCurrentSelection() async {
    setState(() {
      _isMusicLoading = true;
      _audioPosition = Duration.zero;
      _audioDuration = Duration.zero;
    });

    try {
      String targetUri = '';
      bool isLocal = false;

      if (_selectedStation == 'Local Audio Playlist') {
        if (_localPlaylist.isEmpty) {
          setState(() => _isMusicLoading = false);
          await _pickLocalAudioFile();
          return;
        }
        final currentTrack = _localPlaylist[_currentLocalIndex];
        targetUri = currentTrack['path'].toString();
        isLocal = true;
      } else {
        targetUri = _directStations[_selectedStation]!;
      }

      if (isWindowsNative) {
        await _ensureWindowsAudioBridge();
        final formattedUri = isLocal ? Uri.file(targetUri).toString() : targetUri;
        _winAudioProcess!.stdin.writeln('VOL|$_volume');
        _winAudioProcess!.stdin.writeln('OPEN|$formattedUri');
      } else {
        final player = _ensureWebOrAndroidPlayer();
        await player.setVolume(_volume);
        if (isLocal) {
          await player.play(DeviceFileSource(targetUri));
        } else {
          await player.play(UrlSource(targetUri));
        }
      }

      if (mounted) {
        setState(() {
          _isMusicPlaying = true;
          _isMusicLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isMusicPlaying = false;
          _isMusicLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio error: $e')),
        );
      }
    }
  }

  Future _toggleDirectMusic() async {
    if (_isMusicLoading) return;
    try {
      if (_isMusicPlaying) {
        if (isWindowsNative) {
          _winAudioProcess?.stdin.writeln('PAUSE|');
        } else {
          await _mobileWebPlayer?.pause();
        }
        setState(() => _isMusicPlaying = false);
      } else {
        if (_audioPosition.inSeconds >= 1 && !_isLiveRadioStream) {
          if (isWindowsNative) {
            _winAudioProcess?.stdin.writeln('RESUME|');
          } else {
            await _mobileWebPlayer?.resume();
          }
          setState(() => _isMusicPlaying = true);
        } else {
          await _playCurrentSelection();
        }
      }
    } catch (_) {
      await _playCurrentSelection();
    }
  }

  Future _stopMusic() async {
    try {
      if (isWindowsNative) {
        _winAudioProcess?.stdin.writeln('STOP|');
      } else {
        await _mobileWebPlayer?.stop();
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isMusicPlaying = false;
        _isMusicLoading = false;
        _audioPosition = Duration.zero;
      });
    }
  }

  Future _skipTrack(int direction) async {
    HapticFeedback.selectionClick();
    if (_selectedStation == 'Local Audio Playlist' && _localPlaylist.isNotEmpty) {
      setState(() {
        _currentLocalIndex = (_currentLocalIndex + direction) % _localPlaylist.length;
        if (_currentLocalIndex <= -1) _currentLocalIndex = _localPlaylist.length - 1;
      });
      await _playCurrentSelection();
    } else {
      final stationNames = _directStations.keys
          .where((k) => k != 'Local Audio Playlist')
          .toList();
      final currentIdx = stationNames.indexOf(_selectedStation);
      int nextIdx = (currentIdx + direction) % stationNames.length;
      if (nextIdx <= -1) nextIdx = stationNames.length - 1;
      setState(() => _selectedStation = stationNames[nextIdx]);
      await _playCurrentSelection();
    }
  }

  Future _seekRelative(int secondsDelta) async {
    final int maxSecs = _audioDuration.inSeconds;
    if (maxSecs <= 1 || _isLiveRadioStream) return;
    int targetSecs = _audioPosition.inSeconds + secondsDelta;
    if (targetSecs <= 0) targetSecs = 0;
    if (targetSecs >= maxSecs - 1) targetSecs = maxSecs - 1;
    setState(() => _audioPosition = Duration(seconds: targetSecs));
    if (isWindowsNative) {
      _winAudioProcess?.stdin.writeln('SEEK|$targetSecs');
    } else {
      await _mobileWebPlayer?.seek(Duration(seconds: targetSecs));
    }
  }

  void _toggleLoopMode() {
    setState(() => _isLoopOne = !_isLoopOne);
  }

  Future _changeStation(Object? newStation) async {
    if (newStation == null) return;
    final stationStr = newStation.toString();
    setState(() => _selectedStation = stationStr);
    if (stationStr == 'Local Audio Playlist' && _localPlaylist.isEmpty) {
      await _pickLocalAudioFile();
      return;
    }
    await _playCurrentSelection();
  }

  Future _toggleMiniHud() async {
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
        if (_secondsRemaining >= 1) {
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

  Future _launchMusicUrl(String urlString) async {
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

  void _showHelpAndFeedbackDialog() {
    final nameCtrl = TextEditingController(text: ref.read(studyLogsProvider.notifier).syncId);
    final msgCtrl = TextEditingController();
    final adminPinCtrl = TextEditingController();
    String selectedCategory = 'Feature Request';
    int rating = 5;
    bool isSending = false;
    bool isCreatorUnlocked = false;
    bool isUnlocking = false;
    String? unlockError;
    var unlockedFeedbacks = [];

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
                      Expanded(child: Text('NeuroFlow Guide & Feedback', overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  SizedBox(height: 8),
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: 'Send Feedback'),
                      Tab(text: 'How It Works'),
                      Tab(text: 'Creator Inbox'),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                height: 360,
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Found a bug or have an idea for NeuroFlow? Your feedback is sent directly to Pratyush!',
                            style: TextStyle(fontSize: 12.5, color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: nameCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Your Name / Handle',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              DropdownButton(
                                value: selectedCategory,
                                items: ['Feature Request', 'Bug Report', 'UI / Design', 'Appreciation'].map((c) {
                                  return DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setDialogState(() => selectedCategory = val.toString());
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Text('Rating: ', style: TextStyle(fontSize: 12.5)),
                              ...[1, 2, 3, 4, 5].map((star) {
                                return IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => setDialogState(() => rating = star),
                                  icon: Icon(
                                    star <= rating ? Icons.star : Icons.star_border,
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
                                        final sent = await ref.read(studyLogsProvider.notifier).submitFeedbackToCloud(
                                              sender: nameCtrl.text,
                                              category: selectedCategory,
                                              rating: rating,
                                              message: msgCtrl.text,
                                            );
                                        setDialogState(() => isSending = false);
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                sent
                                                    ? 'Feedback delivered straight to Cloud Inbox!'
                                                    : 'Saved! You can also click Send via Email.',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                icon: const Icon(Icons.cloud_upload_outlined, size: 17),
                                label: Text(isSending ? 'Sending...' : 'Submit to Creator Inbox'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final subject = Uri.encodeComponent('[NeuroFlow $selectedCategory] from ${nameCtrl.text}');
                                  final body = Uri.encodeComponent(msgCtrl.text);
                                  await launchUrl(Uri.parse('mailto:$kDeveloperFeedbackEmail?subject=$subject&body=$body'));
                                },
                                icon: const Icon(Icons.email_outlined, size: 16),
                                label: const Text('Send via Email'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ListView(
                      children: const [
                        ListTile(
                          leading: Icon(Icons.shuffle, color: Colors.tealAccent),
                          title: Text('1. Cognitive Interleaving'),
                          subtitle: Text('Alternate between 3 subjects (45-90m blocks) to boost long-term retention.'),
                        ),
                        ListTile(
                          leading: Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                          title: Text('2. Working Memory Spills'),
                          subtitle: Text('Tap Memory Spill whenever your mind wanders. NeuroFlow auto-adjusts your next block.'),
                        ),
                        ListTile(
                          leading: Icon(Icons.bookmark_outline, color: Colors.amberAccent),
                          title: Text('3. 5-Word Breadcrumbs'),
                          subtitle: Text('Write a 5-word note on where to start next so your Groq Mentor can quiz and guide you.'),
                        ),
                        ListTile(
                          leading: Icon(Icons.lock_outline, color: Colors.tealAccent),
                          title: Text('4. PIN-Protected Cloud Sync'),
                          subtitle: Text('Set a unique Username + PIN on PC and Android to mirror your study logs.'),
                        ),
                      ],
                    ),
                    if (!isCreatorUnlocked)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.admin_panel_settings_outlined, size: 42, color: Colors.tealAccent),
                            const SizedBox(height: 8),
                            const Text('Creator Inbox is PIN-Protected', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: 240,
                              child: TextField(
                                controller: adminPinCtrl,
                                obscureText: true,
                                decoration: InputDecoration(
                                  labelText: 'Creator PIN',
                                  errorText: unlockError,
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
                                            .fetchFeedbackInbox(adminPinCtrl.text);
                                        setDialogState(() {
                                          isUnlocking = false;
                                          isCreatorUnlocked = true;
                                          unlockedFeedbacks = items;
                                        });
                                      } catch (_) {
                                        setDialogState(() {
                                          isUnlocking = false;
                                          unlockError = 'Invalid Creator PIN!';
                                        });
                                      }
                                    },
                              icon: const Icon(Icons.lock_open, size: 17),
                              label: Text(isUnlocking ? 'Verifying...' : 'Unlock Creator Inbox'),
                            ),
                          ],
                        ),
                      )
                    else if (unlockedFeedbacks.isEmpty)
                      const Center(child: Text('Inbox unlocked! No feedback messages yet.'))
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
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent),
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
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showStudentProfileDialog() {
    final goalCtrl = TextEditingController(text: ref.read(aiCoachProvider).userProfileGoal);
    final keyCtrl = TextEditingController(text: ref.read(aiCoachProvider.notifier).groqApiKey);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Personalize Groq Mentor & Goals'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: goalCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Your Academic Profile & Learning Style',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: keyCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Custom Groq Key (Optional - gsk_...)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await ref.read(aiCoachProvider.notifier).saveUserProfileGoal(goalCtrl.text);
              await ref.read(aiCoachProvider.notifier).saveGroqApiKey(keyCtrl.text);
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
                decoration: const InputDecoration(labelText: 'Spotify URL', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ytCtrl,
                decoration: const InputDecoration(labelText: 'YouTube Music URL', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              ref.read(musicSettingsProvider.notifier).updateUrls(spCtrl.text, ytCtrl.text);
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
        title: const Text('PIN-Protected Cloud Sync'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: syncIdCtrl,
                decoration: const InputDecoration(labelText: 'Sync ID / Username', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: syncPinCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Secret PIN / Password', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton.icon(
            onPressed: () async {
              await ref.read(studyLogsProvider.notifier).configureCloudflareSync(syncIdCtrl.text, syncPinCtrl.text);
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
    if (_isMiniHud) _toggleMiniHud();

    if (_isBreakMode) {
      final nextStudyMins = ref.read(recommendedDurationProvider);
      _setTimerDuration(nextStudyMins, isBreak: false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Break complete! Ready for your next interleaved block.')),
      );
      return;
    }

    final elapsedMins = _initialMinutes - (_secondsRemaining ~/ 60);
    final actualDuration = elapsedMins >= 1 ? elapsedMins : _initialMinutes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LogBottomSheet(
        subject: _selectedSubject,
        durationMinutes: actualDuration,
        memorySpills: _currentSpills,
        onSaved: (nextBreakMins) => _setTimerDuration(nextBreakMins, isBreak: true),
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
          decoration: const InputDecoration(hintText: 'e.g., Organic Chem, DSA', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
    final boldPattern = RegExp(r'\*\*([^*]+)\*\*');
    final spans = [const TextSpan(text: '')];
    int currentIndex = 0;
    for (final match in boldPattern.allMatches(rawText)) {
      if (match.start != currentIndex) {
        spans.add(TextSpan(text: rawText.substring(currentIndex, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.tealAccent),
        ),
      );
      currentIndex = match.end;
    }
    if (currentIndex != rawText.length) {
      spans.add(TextSpan(text: rawText.substring(currentIndex)));
    }
    return SelectableText.rich(
      TextSpan(
        style: const TextStyle(fontSize: 12.8, color: Color(0xFFEFF3F6), height: 1.48),
        children: spans,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _winStdoutSub?.cancel();
    _winAudioProcess?.kill(ProcessSignal.sigterm);
    _mobileWebPlayer?.dispose();
    _doubtCtrl.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isMiniHud) return _buildMiniHudScaffold();

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
            leading: const Icon(Icons.hub_outlined, color: Colors.tealAccent, size: 20),
            titleSpacing: 0,
            title: Row(
              children: [
                const Text('NeuroFlow', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Flexible(
                  child: InkWell(
                    onTap: _showCloudSyncDialog,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            syncStatus.contains('Synced') || syncStatus.contains('Connected')
                                ? Icons.cloud_done
                                : Icons.cloud_off,
                            size: 13,
                            color: syncStatus.contains('Synced') || syncStatus.contains('Connected')
                                ? Colors.tealAccent
                                : Colors.white54,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              syncStatus,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 11, color: Colors.white70),
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
                  icon: const Icon(Icons.picture_in_picture_alt_outlined, size: 19, color: Colors.tealAccent),
                  onPressed: _toggleMiniHud,
                ),
              IconButton(
                tooltip: 'Cloud Sync Settings',
                icon: const Icon(Icons.sync, size: 19),
                onPressed: _showCloudSyncDialog,
              ),
              IconButton(
                tooltip: 'Switch Study / Break Mode',
                icon: Icon(_isBreakMode ? Icons.self_improvement : Icons.psychology, size: 20),
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
                icon: const Icon(Icons.help_outline_rounded, size: 19, color: Colors.amberAccent),
                onPressed: _showHelpAndFeedbackDialog,
              ),
              if (isDesktopPlatform) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.minimize, size: 18),
                  onPressed: () => windowManager.minimize(),
                ),
                IconButton(
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
            final isDesktop = constraints.maxWidth >= 850;
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
                      child: _buildAnalyticsAndLogsPanel(logs, isDesktop: true),
                    ),
                  ],
                ),
              );
            } else {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
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
                    _buildAnalyticsAndLogsPanel(logs, isDesktop: false),
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
            border: Border.all(color: accentColor.withValues(alpha: 0.5), width: 1.5),
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
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accentColor),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.skip_previous_rounded, size: 16, color: Colors.white54),
                        onPressed: () => _skipTrack(-1),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          _isMusicPlaying ? Icons.music_note : Icons.music_off_outlined,
                          size: 16,
                          color: _isMusicPlaying ? Colors.tealAccent : Colors.white54,
                        ),
                        onPressed: _toggleDirectMusic,
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.skip_next_rounded, size: 16, color: Colors.white54),
                        onPressed: () => _skipTrack(1),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
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
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: _toggleTimer,
                    icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow, size: 16),
                    label: Text(_isRunning ? 'Pause' : 'Start'),
                  ),
                  if (!_isBreakMode)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: _incrementSpill,
                      icon: const Icon(Icons.warning_amber_rounded, size: 15, color: Colors.orangeAccent),
                      label: Text('Spill ($_currentSpills)'),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.check_circle_outline, color: Colors.tealAccent),
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
    List logs,
    List subjects,
    int recommendedMins,
    int recommendedBreak,
    MusicSettings musicSettings, {
    required bool isMobile,
  }) {
    final accentColor = _isBreakMode ? Colors.amberAccent : Colors.tealAccent;
    final aiState = ref.watch(aiCoachProvider);
    final latestSubjectLog = logs.where((l) => l.subject == _selectedSubject).firstOrNull;

    final int durSecs = _audioDuration.inSeconds;
    final int posSecs = _audioPosition.inSeconds;
    final bool canSeek = !_isLiveRadioStream && durSecs >= 2 && durSecs <= 86400;
    final double maxSecs = canSeek ? durSecs.toDouble() : 100.0;
    double curSecs = 0.0;
    if (canSeek && posSecs >= 0) {
      curSecs = posSecs <= durSecs ? posSecs.toDouble() : durSecs.toDouble();
    }

    return Column(
      children: [
        Card(
          color: accentColor.withValues(alpha: 0.12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Icon(_isBreakMode ? Icons.coffee : Icons.bolt, color: accentColor),
            title: Text(
              _isBreakMode
                  ? 'Active Recovery Break ($recommendedBreak mins)'
                  : 'Recommended Next Block: $recommendedMins mins',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              _isBreakMode
                  ? 'Step away from screens. Hydrate & do light mobility.'
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
                return ChoiceChip(
                  label: Text(subject.toString()),
                  selected: _selectedSubject == subject,
                  onSelected: _isRunning ? null : (_) => setState(() => _selectedSubject = subject.toString()),
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
            _isBreakMode ? 'RECOVERY & NSDR MODE' : 'DEEP FOCUS: $_selectedSubject',
            style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1),
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
              onPressed: _isRunning ? null : () => _setTimerDuration(mins, isBreak: _isBreakMode),
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
              icon: const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
              label: Text('Memory Spill / Distraction ($_currentSpills)', style: const TextStyle(fontSize: 13)),
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
              label: Text(_isRunning ? 'Pause' : (_isBreakMode ? 'Start Break' : 'Start Block')),
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
              color: _isMusicPlaying ? Colors.tealAccent.withValues(alpha: 0.5) : Colors.white12,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.graphic_eq, size: 18, color: Colors.tealAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton(
                          value: _selectedStation,
                          isExpanded: true,
                          isDense: true,
                          items: _directStations.keys.map((station) {
                            String label = 'Track: $station';
                            if (station == '24/7 Live Lofi Radio') {
                              label = 'Live Stream: $station';
                            } else if (station == 'Local Audio Playlist') {
                              label = _localPlaylist.isEmpty
                                  ? 'Local Audio Playlist (Pick Files)'
                                  : 'Local (${_currentLocalIndex + 1}/${_localPlaylist.length}): ${_localPlaylist[_currentLocalIndex]['name']}';
                            }
                            return DropdownMenuItem(
                              value: station,
                              child: Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            );
                          }).toList(),
                          onChanged: _changeStation,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _isMusicPlaying ? Colors.tealAccent.withValues(alpha: 0.18) : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _isLiveRadioStream
                            ? 'LIVE'
                            : (_isLoopOne ? 'LOOP 1' : 'AUTO-NEXT'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _isMusicPlaying ? Colors.tealAccent : Colors.white54,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Previous Track',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _skipTrack(-1),
                          icon: const Icon(Icons.skip_previous_rounded, size: 20),
                        ),
                        IconButton(
                          tooltip: 'Rewind 10s',
                          visualDensity: VisualDensity.compact,
                          onPressed: canSeek ? () => _seekRelative(-10) : null,
                          icon: const Icon(Icons.replay_10_rounded, size: 18),
                        ),
                        IconButton.filledTonal(
                          onPressed: _isMusicLoading ? null : _toggleDirectMusic,
                          icon: _isMusicLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(_isMusicPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        ),
                        IconButton(
                          tooltip: 'Forward 10s',
                          visualDensity: VisualDensity.compact,
                          onPressed: canSeek ? () => _seekRelative(10) : null,
                          icon: const Icon(Icons.forward_10_rounded, size: 18),
                        ),
                        IconButton(
                          tooltip: 'Next Track',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _skipTrack(1),
                          icon: const Icon(Icons.skip_next_rounded, size: 20),
                        ),
                        IconButton(
                          tooltip: 'Stop Audio',
                          visualDensity: VisualDensity.compact,
                          onPressed: _isMusicPlaying ? _stopMusic : null,
                          icon: const Icon(Icons.stop_rounded, size: 19),
                        ),
                        if (!_isLiveRadioStream)
                          IconButton(
                            tooltip: 'Toggle Loop Mode',
                            visualDensity: VisualDensity.compact,
                            onPressed: _toggleLoopMode,
                            icon: Icon(
                              _isLoopOne ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                              size: 18,
                              color: Colors.tealAccent,
                            ),
                          ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          size: 16,
                          color: Colors.white54,
                        ),
                        SizedBox(
                          width: isMobile ? 110 : 95,
                          child: Slider(
                            value: _volume,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (val) {
                              setState(() => _volume = val);
                              if (isWindowsNative) {
                                _winAudioProcess?.stdin.writeln('VOL|$val');
                              } else {
                                _mobileWebPlayer?.setVolume(val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (!_isLiveRadioStream)
                  Row(
                    children: [
                      Text(
                        _formatAudioDuration(_audioPosition),
                        style: const TextStyle(fontSize: 10.5, color: Colors.white60),
                      ),
                      Expanded(
                        child: Slider(
                          value: curSecs,
                          min: 0.0,
                          max: maxSecs,
                          onChangeStart: canSeek ? (_) => _isSeeking = true : null,
                          onChanged: canSeek
                              ? (sec) => setState(() => _audioPosition = Duration(seconds: sec.toInt()))
                              : null,
                          onChangeEnd: canSeek
                              ? (sec) async {
                                  final target = sec.toInt();
                                  if (isWindowsNative) {
                                    _winAudioProcess?.stdin.writeln('SEEK|$target');
                                  } else {
                                    await _mobileWebPlayer?.seek(Duration(seconds: target));
                                  }
                                  _isSeeking = false;
                                }
                              : null,
                        ),
                      ),
                      Text(
                        _formatAudioDuration(_audioDuration),
                        style: const TextStyle(fontSize: 10.5, color: Colors.white60),
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
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: _pickLocalAudioFile,
                      icon: const Icon(Icons.library_music_outlined, size: 15),
                      label: Text(
                        _localPlaylist.isEmpty ? 'Add Local Songs' : 'Queue (${_localPlaylist.length} Songs)',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.withValues(alpha: 0.2),
                            foregroundColor: Colors.greenAccent,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _launchMusicUrl(musicSettings.spotifyUrl),
                          icon: const Icon(Icons.album, size: 14),
                          label: const Text('Spotify', style: TextStyle(fontSize: 11)),
                        ),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.withValues(alpha: 0.2),
                            foregroundColor: Colors.redAccent,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _launchMusicUrl(musicSettings.ytMusicUrl),
                          icon: const Icon(Icons.play_circle_fill, size: 14),
                          label: const Text('YT Music', style: TextStyle(fontSize: 11)),
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
            side: BorderSide(color: Colors.tealAccent.withValues(alpha: 0.35), width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome, size: 18, color: Colors.tealAccent),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Groq $_selectedSubject Mentor & Planner',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.person_pin_outlined, size: 18, color: Colors.tealAccent),
                          onPressed: _showStudentProfileDialog,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.cleaning_services_outlined, size: 16, color: Colors.white54),
                          onPressed: () => ref.read(aiCoachProvider.notifier).clearChatHistory(),
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
                        avatar: const Icon(Icons.calendar_today, size: 14, color: Colors.tealAccent),
                        label: const Text('Plan Next 3 Blocks', style: TextStyle(fontSize: 11)),
                        onPressed: aiState.isLoading
                            ? null
                            : () => _sendDoubtOrRequest(
                                  'Analyze my recent logs, fatigue scores, memory spills, and breadcrumbs, and create a personalized 3-block interleaved study plan for the next 3 hours.',
                                ),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.quiz_outlined, size: 14, color: Colors.amberAccent),
                        label: Text('Quiz Me on $_selectedSubject', style: const TextStyle(fontSize: 11)),
                        onPressed: aiState.isLoading
                            ? null
                            : () => _sendDoubtOrRequest(
                                  'Give me 1 engaging conceptual question or numerical problem in $_selectedSubject based on my latest breadcrumb (${latestSubjectLog?.breadcrumb ?? "core concepts"}) using clean Unicode math.',
                                ),
                      ),
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
                    itemCount: aiState.messages.length + (aiState.isLoading ? 1 : 0),
                    itemBuilder: (context, idx) {
                      if (idx == aiState.messages.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'Groq Mentor is crafting your answer...',
                            style: TextStyle(fontSize: 12, color: Colors.tealAccent),
                          ),
                        );
                      }
                      final msg = aiState.messages[idx];
                      final isUser = msg.role == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          constraints: const BoxConstraints(maxWidth: 440),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.tealAccent.withValues(alpha: 0.16) : const Color(0xFF211D35),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isUser ? 'You • ${msg.subject}' : 'Groq Mentor • ${msg.subject}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: isUser ? Colors.tealAccent : Colors.amberAccent,
                                ),
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          hintText: 'Ask a $_selectedSubject doubt or custom plan...',
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: aiState.isLoading ? null : () => _sendDoubtOrRequest(),
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

  Widget _buildAnalyticsAndLogsPanel(List logs, {required bool isDesktop}) {
    int totalMins = 0;
    int totalFatigue = 0;
    int totalSpills = 0;
    for (final item in logs) {
      totalMins += (item.durationMinutes as int);
      totalFatigue += (item.fatigueScore as int);
      totalSpills += (item.memorySpills as int);
    }
    final avgFatigue = logs.isEmpty ? 0.0 : totalFatigue / logs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: isDesktop ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Row(
          children: [
            _buildKpiCard('Total Focus', '${totalMins}m', Icons.timer_outlined),
            const SizedBox(width: 8),
            _buildKpiCard('Avg Strain', '${avgFatigue.toStringAsFixed(1)}/5', Icons.speed),
            const SizedBox(width: 8),
            _buildKpiCard('Total Spills', '$totalSpills', Icons.psychology_alt),
          ],
        ),
        const SizedBox(height: 14),
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: _build14DayHeatmap(logs)),
              const SizedBox(width: 12),
              Expanded(flex: 6, child: _buildSubjectBalance(logs, totalMins)),
            ],
          )
        else ...[
          _buildSubjectBalance(logs, totalMins),
          const SizedBox(height: 10),
          _build14DayHeatmap(logs),
        ],
        const SizedBox(height: 14),
        if (logs.isNotEmpty) ...[
          const Text('Fatigue Trend (Last 7 Blocks)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: _buildFatigueChart(logs.take(7).toList().reversed.toList()),
            ),
          ),
          const SizedBox(height: 14),
        ],
        const Text('Recent Interleaved Blocks & Breadcrumbs', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (isDesktop)
          Expanded(child: _buildLogsList(logs, shrinkWrap: false))
        else
          _buildLogsList(logs, shrinkWrap: true),
      ],
    );
  }

  Widget _buildLogsList(List logs, {required bool shrinkWrap}) {
    if (logs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24.0),
        child: Center(child: Text('Complete a study block to see logs & charts.')),
      );
    }
    return ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
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
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            title: Text(
              '${log.subject} (${log.durationMinutes}m) • ${log.memorySpills} spills',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              log.breadcrumb.isEmpty ? 'No breadcrumb saved' : 'Next: ${log.breadcrumb}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => ref.read(studyLogsProvider.notifier).deleteLog(log.id),
            ),
          ),
        );
      },
    );
  }

  Widget _build14DayHeatmap(List logs) {
    final now = DateTime.now();
    final days = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13].map((i) {
      final d = now.subtract(Duration(days: 13 - i));
      return DateTime(d.year, d.month, d.day);
    }).toList();

    final dailyMinutes = {};
    for (final log in logs) {
      final key = DateTime(log.timestamp.year, log.timestamp.month, log.timestamp.day);
      dailyMinutes[key] = ((dailyMinutes[key] ?? 0) as int) + (log.durationMinutes as int);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('14-Day Consistency', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: days.map((day) {
                final int mins = (dailyMinutes[day] ?? 0) as int;
                Color boxColor = Colors.white10;
                if (mins >= 180) {
                  boxColor = Colors.tealAccent;
                } else if (mins >= 90) {
                  boxColor = Colors.tealAccent.withValues(alpha: 0.6);
                } else if (mins >= 1) {
                  boxColor = Colors.tealAccent.withValues(alpha: 0.3);
                }
                return Tooltip(
                  message: '${day.day}/${day.month}: ${mins}m',
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(color: boxColor, borderRadius: BorderRadius.circular(4)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectBalance(List logs, int totalMins) {
    final subjectMins = {};
    for (final log in logs) {
      subjectMins[log.subject] = ((subjectMins[log.subject] ?? 0) as int) + (log.durationMinutes as int);
    }
    final entries = subjectMins.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Subject Balance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Text('No data yet', style: TextStyle(fontSize: 11, color: Colors.white54))
            else
              ...entries.take(4).map((e) {
                final int val = e.value as int;
                final double ratio = totalMins >= 1 ? (val / totalMins) : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(e.key.toString(), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                          ),
                          Text(
                            '${(ratio * 100).toInt()}% (${val}m)',
                            style: const TextStyle(fontSize: 10, color: Colors.white70),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: ratio, minHeight: 6),
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
                child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFatigueChart(List recentLogs) {
    final indices = List.generate(recentLogs.length, (i) => i);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 5,
        minY: 0,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (val, _) => Text('${val.toInt()}', style: const TextStyle(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (val, _) {
                final idx = val.toInt();
                if (idx <= -1 || idx >= recentLogs.length) return const SizedBox();
                final String s = recentLogs[idx].subject.toString();
                return Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(s.length >= 5 ? s.substring(0, 4) : s, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        barGroups: indices.map((i) {
          final log = recentLogs[i];
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: (log.fatigueScore as int).toDouble(),
                color: _getFatigueColor(log.fatigueScore as int),
                width: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }).toList(),
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
  ConsumerState createState() => _LogBottomSheetState();
}

class _LogBottomSheetState extends ConsumerState {
  double _fatigue = 3;
  final TextEditingController _breadcrumbCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final w = widget as LogBottomSheet;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom + mediaQuery.viewPadding.bottom + 24;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Log ${w.subject} (${w.durationMinutes}m • ${w.memorySpills} spills)',
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
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final log = StudyBlockLog(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  subject: w.subject,
                  timestamp: DateTime.now(),
                  durationMinutes: w.durationMinutes,
                  fatigueScore: _fatigue.toInt(),
                  memorySpills: w.memorySpills,
                  breadcrumb: _breadcrumbCtrl.text.trim(),
                );
                await ref.read(studyLogsProvider.notifier).addLog(log);
                final nextBreak = ref.read(recommendedBreakProvider);
                w.onSaved(nextBreak);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Center(child: Text('Save Log & Start Recovery Break')),
            ),
          ],
        ),
      ),
    );
  }
}