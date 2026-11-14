import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'models.dart';

const String kSelfHostedApiUrl =
    'https://neuroflow-ai-coach.mohantypratyush37.workers.dev/';

const String kDeveloperFeedbackEmail = 'mohantypratyush37@gmail.com';

const String kBuiltInGroqKey = String.fromEnvironment(
  'GROQ_API_KEY',
  defaultValue: '',
);

final syncStatusProvider =
    StateProvider<String>((ref) => 'Offline (Local Hive)');

final studyLogsProvider =
    StateNotifierProvider<StudyLogNotifier, List<StudyBlockLog>>((ref) {
  return StudyLogNotifier(ref);
});

class StudyLogNotifier extends StateNotifier<List<StudyBlockLog>> {
  final Ref ref;
  StudyLogNotifier(this.ref) : super([]) {
    _loadLocalLogs();
    _initCloudSyncIfConfigured();
  }

  final Box _box = Hive.box('study_logs_box');
  final Box _settingsBox = Hive.box('settings_box');

  String get syncId =>
      (_settingsBox.get('cloudflare_sync_id', defaultValue: '') as String)
          .trim();

  String get syncPin =>
      (_settingsBox.get('cloudflare_sync_pin', defaultValue: '') as String)
          .trim();

  void _loadLocalLogs() {
    final data = _box.values
        .whereType()
        .map((e) => StudyBlockLog.fromMap(e))
        .toList();
    data.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    state = data;
  }

  Future<void> _initCloudSyncIfConfigured() async {
    if (syncId.isNotEmpty && syncPin.isNotEmpty) {
      await syncWithCloud();
    }
  }

  Future<bool> configureCloudflareSync(
      String newSyncId, String newSyncPin) async {
    final cleanedId = newSyncId.trim();
    final cleanedPin = newSyncPin.trim();
    await _settingsBox.put('cloudflare_sync_id', cleanedId);
    await _settingsBox.put('cloudflare_sync_pin', cleanedPin);

    if (cleanedId.isEmpty || cleanedPin.isEmpty) {
      ref.read(syncStatusProvider.notifier).state = 'Offline (Local Hive)';
      return false;
    }
    return await syncWithCloud();
  }

  Future<bool> syncWithCloud({List<String> deletedIds = const []}) async {
    final currentSyncId = syncId;
    final currentSyncPin = syncPin;
    if (currentSyncId.isEmpty || currentSyncPin.isEmpty) return false;

    ref.read(syncStatusProvider.notifier).state = 'Syncing...';

    try {
      final localPayload = state.map((log) => log.toMap()).toList();

      final response = await http.post(
        Uri.parse(kSelfHostedApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'sync',
          'syncId': currentSyncId,
          'syncPin': currentSyncPin,
          'logs': localPayload,
          'deletedIds': deletedIds,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['logs'] is List) {
        final List<dynamic> remoteLogs = data['logs'];
        await _box.clear();
        for (final row in remoteLogs) {
          if (row is Map) {
            final log = StudyBlockLog.fromMap(row);
            await _box.put(log.id, log.toMap());
          }
        }
        _loadLocalLogs();
        ref.read(syncStatusProvider.notifier).state =
            'Synced ($currentSyncId)';
        return true;
      } else {
        final err = data['error']?.toString() ?? 'HTTP ${response.statusCode}';
        ref.read(syncStatusProvider.notifier).state = err;
        return false;
      }
    } catch (e) {
      ref.read(syncStatusProvider.notifier).state =
          'Offline (Saved Locally)';
      return false;
    }
  }

  Future<void> addLog(StudyBlockLog log) async {
    await _box.put(log.id, log.toMap());
    state = [log, ...state];

    if (syncId.isNotEmpty && syncPin.isNotEmpty) {
      await syncWithCloud();
    }
  }

  Future<void> deleteLog(String id) async {
    await _box.delete(id);
    state = state.where((log) => log.id != id).toList();

    if (syncId.isNotEmpty && syncPin.isNotEmpty) {
      await syncWithCloud(deletedIds: [id]);
    }
  }

  Future<bool> submitFeedbackToCloud({
    required String sender,
    required String category,
    required int rating,
    required String message,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(kSelfHostedApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'submit_feedback',
          'sender': sender.trim().isEmpty ? 'Anonymous User' : sender.trim(),
          'category': category,
          'rating': rating,
          'message': message.trim(),
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['ok'] == true;
      }
    } catch (_) {}
    return false;
  }

  /// Requires your secret Creator PIN to unlock and read feedback messages
  Future<List<FeedbackItem>> fetchFeedbackInbox(String adminPin) async {
    final res = await http.post(
      Uri.parse(kSelfHostedApiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'get_feedback',
        'adminPin': adminPin.trim(),
      }),
    );

    final data = jsonDecode(res.body);
    if (res.statusCode == 200) {
      final rawList = data['feedbacks'];
      if (rawList is List) {
        return rawList
            .whereType()
            .map((m) => FeedbackItem.fromMap(m))
            .toList();
      }
      return <FeedbackItem>[];
    } else {
      throw Exception(data['error']?.toString() ?? 'Invalid Creator PIN');
    }
  }
}

final subjectsProvider =
    StateNotifierProvider<SubjectsNotifier, List<String>>((ref) {
  return SubjectsNotifier();
});

class SubjectsNotifier extends StateNotifier<List<String>> {
  SubjectsNotifier()
      : super(['Physics', 'Mathematics', 'Chemistry', 'Python / AI']) {
    _loadSubjects();
  }

  final Box _settingsBox = Hive.box('settings_box');

  void _loadSubjects() {
    final saved = _settingsBox.get('custom_subjects');
    if (saved != null && saved is List && saved.isNotEmpty) {
      state = saved.map((e) => e.toString()).toList();
    }
  }

  Future<void> addSubject(String newSubject) async {
    final trimmed = newSubject.trim();
    if (trimmed.isEmpty || state.contains(trimmed)) return;
    final updated = [...state, trimmed];
    await _settingsBox.put('custom_subjects', updated);
    state = updated;
  }
}

class MusicSettings {
  final String spotifyUrl;
  final String ytMusicUrl;

  MusicSettings({required this.spotifyUrl, required this.ytMusicUrl});
}

final musicSettingsProvider =
    StateNotifierProvider<MusicSettingsNotifier, MusicSettings>((ref) {
  return MusicSettingsNotifier();
});

class MusicSettingsNotifier extends StateNotifier<MusicSettings> {
  final Box _settingsBox = Hive.box('settings_box');

  MusicSettingsNotifier()
      : super(
          MusicSettings(
            spotifyUrl:
                'https://open.spotify.com/playlist/37i9dQZF1DWZeKCadgRdKQ',
            ytMusicUrl:
                'https://music.youtube.com/search?q=deep+focus+instrumental+study',
          ),
        ) {
    _load();
  }

  void _load() {
    final sp = _settingsBox.get('spotify_url') as String?;
    final yt = _settingsBox.get('yt_music_url') as String?;
    state = MusicSettings(
      spotifyUrl: (sp != null && sp.isNotEmpty) ? sp : state.spotifyUrl,
      ytMusicUrl: (yt != null && yt.isNotEmpty) ? yt : state.ytMusicUrl,
    );
  }

  Future<void> updateUrls(String spotify, String ytMusic) async {
    final spTrimmed = spotify.trim();
    final ytTrimmed = ytMusic.trim();
    await _settingsBox.put('spotify_url', spTrimmed);
    await _settingsBox.put('yt_music_url', ytTrimmed);
    state = MusicSettings(spotifyUrl: spTrimmed, ytMusicUrl: ytTrimmed);
  }
}

class AiChatMessage {
  final String role;
  final String text;
  final String subject;
  final DateTime timestamp;

  AiChatMessage({
    required this.role,
    required this.text,
    required this.subject,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'role': role,
        'text': text,
        'subject': subject,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AiChatMessage.fromMap(Map<dynamic, dynamic> map) {
    return AiChatMessage(
      role: map['role']?.toString() ?? 'assistant',
      text: map['text']?.toString() ?? '',
      subject: map['subject']?.toString() ?? 'General',
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class AiCoachState {
  final bool isLoading;
  final List<AiChatMessage> messages;
  final String userProfileGoal;

  AiCoachState({
    this.isLoading = false,
    this.messages = const [],
    this.userProfileGoal = '',
  });
}

final aiCoachProvider =
    StateNotifierProvider<AiCoachNotifier, AiCoachState>((ref) {
  return AiCoachNotifier(ref);
});

class AiCoachNotifier extends StateNotifier<AiCoachState> {
  final Ref ref;
  final Box _settingsBox = Hive.box('settings_box');

  AiCoachNotifier(this.ref) : super(AiCoachState()) {
    _loadSavedChatAndProfile();
  }

  void _loadSavedChatAndProfile() {
    final savedGoal = _settingsBox.get(
      'user_profile_goal',
      defaultValue:
          'Class 11 PCM + Computer Science student preparing for JEE & SAT. Prefers clear, conversational intuition, clean Unicode formulas, and practical study plans.',
    ) as String;

    final rawMessages = _settingsBox.get('ai_chat_history');
    List<AiChatMessage> loadedMessages = [];

    if (rawMessages is List && rawMessages.isNotEmpty) {
      loadedMessages = rawMessages
          .whereType()
          .map((m) => AiChatMessage.fromMap(m))
          .toList();
    } else {
      loadedMessages = [
        AiChatMessage(
          role: 'assistant',
          subject: 'Groq AI Mentor',
          timestamp: DateTime.now(),
          text:
              '👋 **Hey! I am your Personal Subject Mentor & Study Planner.**\n'
              '• Pick any subject chip above and ask me **doubts, concepts, or problem-solving tricks**.\n'
              '• Tap **Plan Next 3 Blocks** whenever you want a custom schedule built around your latest breadcrumbs!',
        ),
      ];
    }

    state = AiCoachState(
      isLoading: false,
      messages: loadedMessages,
      userProfileGoal: savedGoal,
    );
  }

  String get groqApiKey {
    final userSavedKey = _cleanKey(
      _settingsBox.get('groq_api_key', defaultValue: '') as String,
    );
    if (userSavedKey.isNotEmpty) return userSavedKey;
    return _cleanKey(kBuiltInGroqKey);
  }

  String _cleanKey(String raw) {
    return raw.replaceAll(RegExp(r'[\s"' "'" r']'), '');
  }

  Future<void> saveGroqApiKey(String key) async {
    final cleaned = _cleanKey(key);
    await _settingsBox.put('groq_api_key', cleaned);
  }

  Future<void> saveUserProfileGoal(String newGoal) async {
    final trimmed = newGoal.trim();
    await _settingsBox.put('user_profile_goal', trimmed);
    state = AiCoachState(
      isLoading: state.isLoading,
      messages: state.messages,
      userProfileGoal: trimmed,
    );
  }

  Future<void> clearChatHistory() async {
    final welcome = AiChatMessage(
      role: 'assistant',
      subject: 'Groq AI Mentor',
      timestamp: DateTime.now(),
      text:
          '✨ **Fresh start!** Ask me any doubt in your selected subject, or tap **Plan Next 3 Blocks** below.',
    );
    await _settingsBox.put('ai_chat_history', [welcome.toMap()]);
    state = AiCoachState(
      isLoading: false,
      messages: [welcome],
      userProfileGoal: state.userProfileGoal,
    );
  }

  String _prettifyMathAndFormatting(String raw) {
    String out = raw;
    out = out.replaceAll(r'\(', '').replaceAll(r'\)', '');
    out = out.replaceAll(r'\[', '').replaceAll(r'\]', '');
    out = out.replaceAll(r'$$', '');

    out = out.replaceAll(r'\frac12', '½').replaceAll(r'\frac{1}{2}', '½');
    out = out.replaceAll(r'\frac13', '⅓').replaceAll(r'\frac{1}{3}', '⅓');
    out = out.replaceAll(r'\frac14', '¼').replaceAll(r'\frac{1}{4}', '¼');
    out = out.replaceAllMapped(
      RegExp(r'\\frac\{([^}]+)\}\{([^}]+)\}'),
      (m) => '(${m.group(1)})/(${m.group(2)})',
    );

    const replacements = {
      r'\theta': 'θ',
      r'\alpha': 'α',
      r'\beta': 'β',
      r'\gamma': 'γ',
      r'\delta': 'Δ',
      r'\Delta': 'Δ',
      r'\pi': 'π',
      r'\omega': 'ω',
      r'\Omega': 'Ω',
      r'\mu': 'μ',
      r'\lambda': 'λ',
      r'\sigma': 'σ',
      r'\tau': 'τ',
      r'\phi': 'φ',
      r'\infty': '∞',
      r'\approx': '≈',
      r'\neq': '≠',
      r'\leq': '≤',
      r'\geq': '≥',
      r'\times': '×',
      r'\cdot': '·',
      r'\pm': '±',
      r'\rightarrow': '→',
      r'\Rightarrow': '⇒',
      r'\sqrt': '√',
      r'\cos': 'cos',
      r'\sin': 'sin',
      r'\tan': 'tan',
      r'\log': 'log',
      r'\ln': 'ln',
      '^2': '²',
      '^3': '³',
      '_0': '₀',
      '_1': '₁',
      '_2': '₂',
    };
    replacements.forEach((latex, unicode) {
      out = out.replaceAll(latex, unicode);
    });

    out = out.replaceAllMapped(
      RegExp(r'\{([a-zA-Z0-9²³]+)\}'),
      (m) => m.group(1)!,
    );
    return out.trim();
  }

  Future<void> askAssistant({
    required String userMessage,
    required String currentSubject,
  }) async {
    final trimmedQuery = userMessage.trim();
    if (trimmedQuery.isEmpty) return;

    final userChatMsg = AiChatMessage(
      role: 'user',
      subject: currentSubject,
      text: trimmedQuery,
      timestamp: DateTime.now(),
    );

    final updatedHistory = [...state.messages, userChatMsg];
    state = AiCoachState(
      isLoading: true,
      messages: updatedHistory,
      userProfileGoal: state.userProfileGoal,
    );

    final logs = ref.read(studyLogsProvider).take(10).toList();
    final subjects = ref.read(subjectsProvider);

    final logsSummary = logs.isEmpty
        ? 'No study blocks logged yet.'
        : logs
            .map((l) =>
                '- ${l.subject}: ${l.durationMinutes}m, Fatigue ${l.fatigueScore}/5, Spills: ${l.memorySpills}, Breadcrumb: "${l.breadcrumb}"')
            .join('\n');

    final recentConvo = updatedHistory
        .skip(updatedHistory.length > 5 ? updatedHistory.length - 5 : 0)
        .take(4)
        .map((m) => '${m.role.toUpperCase()} (${m.subject}): ${m.text}')
        .join('\n');

    final prompt = '''
You are NeuroFlow Mentor — a warm, sharp, friendly senior mentor and subject coach.
Speak naturally like a helpful older brother / IITian friend—NEVER sound robotic or like a dry textbook script.

STUDENT PROFILE:
${state.userProfileGoal}

ACTIVE SUBJECT: $currentSubject
ALL SUBJECTS: ${subjects.join(', ')}

RECENT STUDY LOGS & BREADCRUMBS:
$logsSummary

RECENT CHAT:
$recentConvo

STUDENT'S MESSAGE ($currentSubject):
"$trimmedQuery"

STRICT FORMATTING RULES (CRITICAL):
1. NEVER use LaTeX slashes like \\frac, \\(, \\), \\theta, or \\cos! Instead, always write clean Unicode math symbols directly: θ, π, Δ, √, ½, x², v², ×, ÷, →, ≥, ≤.
2. Structure your answer with short, scannable sections using emojis and **Bold Headings** (e.g., 🎯 **Core Intuition**, ⚡ **Step-by-Step**, 💡 **Pro Tip**).
3. Use simple bullet points (•) and keep explanations crystal clear, relatable, and under 160 words.
''';

    final key = groqApiKey;
    String replyText = '';

    try {
      if (key.isNotEmpty) {
        final directReply = await _callGroqDirect(key, prompt);
        replyText = _prettifyMathAndFormatting(directReply);
      } else {
        final workerReply = await _callSelfHostedGroqWorker(prompt);
        replyText = _prettifyMathAndFormatting(workerReply);
      }
    } catch (e) {
      try {
        final workerReply = await _callSelfHostedGroqWorker(prompt);
        replyText = _prettifyMathAndFormatting(workerReply);
      } catch (workerErr) {
        replyText = 'Groq Connection Error: $workerErr';
      }
    }

    final botMsg = AiChatMessage(
      role: 'assistant',
      subject: currentSubject,
      text: replyText,
      timestamp: DateTime.now(),
    );

    final finalMessages = [...updatedHistory, botMsg];
    final toSave = finalMessages
        .skip(finalMessages.length > 20 ? finalMessages.length - 20 : 0)
        .map((m) => m.toMap())
        .toList();
    await _settingsBox.put('ai_chat_history', toSave);

    state = AiCoachState(
      isLoading: false,
      messages: finalMessages,
      userProfileGoal: state.userProfileGoal,
    );
  }

  Future<void> generateInterleavingPlan(
      {String currentSubject = 'General'}) async {
    await askAssistant(
      userMessage:
          'Build my personalized 3-block study plan for the next 3 hours using my fatigue scores, spills, and breadcrumbs.',
      currentSubject: currentSubject,
    );
  }

  Future<String> _callSelfHostedGroqWorker(String prompt) async {
    final response = await http.post(
      Uri.parse(kSelfHostedApiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'prompt': prompt}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      final text = data['advice']?.toString() ?? '';
      if (text.isNotEmpty) return text;
    }
    throw Exception(
      data['error']?.toString() ??
          'HTTP ${response.statusCode}: ${response.body}',
    );
  }

  Future<String> _callGroqDirect(String apiKey, String prompt) async {
    final List<String> candidateModels = [
      'openai/gpt-oss-120b',
      'openai/gpt-oss-20b',
      'groq/compound-mini',
      'groq/compound',
      'qwen/qwen3.6-27b',
      'minimaxai/minimax-m2.7',
    ];

    try {
      final modelsRes = await http.get(
        Uri.parse('https://api.groq.com/openai/v1/models'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      if (modelsRes.statusCode == 200) {
        final decoded = jsonDecode(modelsRes.body);
        final List<dynamic> dataList = decoded['data'] ?? [];
        for (final item in dataList) {
          final id = item['id']?.toString() ?? '';
          if (id.isNotEmpty &&
              !id.contains('whisper') &&
              !id.contains('orpheus') &&
              !id.contains('guard') &&
              !id.contains('safeguard') &&
              !candidateModels.contains(id)) {
            candidateModels.add(id);
          }
        }
      }
    } catch (_) {}

    String lastError = 'No compatible Groq model found';
    for (final model in candidateModels) {
      try {
        final response = await http.post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'max_tokens': 450,
          }),
        );

        final data = jsonDecode(response.body);
        if (response.statusCode == 200) {
          final reply =
              data['choices']?[0]?['message']?['content']?.toString() ?? '';
          if (reply.isNotEmpty) return reply;
        } else {
          lastError = data['error']?['message']?.toString() ??
              'HTTP ${response.statusCode}';
        }
      } catch (e) {
        lastError = e.toString();
      }
    }
    throw Exception(lastError);
  }
}

final recommendedDurationProvider = Provider<int>((ref) {
  final logs = ref.watch(studyLogsProvider);
  if (logs.isEmpty) return 75;

  final last = logs.first;
  if (last.fatigueScore >= 4 || last.memorySpills >= 5) {
    return 45;
  } else if (last.fatigueScore <= 2 && last.memorySpills <= 1) {
    return 90;
  }
  return 75;
});

final recommendedBreakProvider = Provider<int>((ref) {
  final logs = ref.watch(studyLogsProvider);
  if (logs.isEmpty) return 15;
  return logs.first.fatigueScore >= 4 ? 25 : 15;
});