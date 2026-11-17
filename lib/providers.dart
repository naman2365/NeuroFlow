import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'models.dart';

const String kDeveloperFeedbackEmail = 'pratyush.mohanty@example.com';
const String kDefaultCloudflareWorkerUrl =
    'https://neuroflow-sync.pratyush-mohanty.workers.dev';

final syncStatusProvider = StateProvider((ref) => 'Offline (Local Hive)');

final subjectsProvider =
    StateNotifierProvider<SubjectsNotifier, List<String>>((ref) {
  return SubjectsNotifier();
});

class SubjectsNotifier extends StateNotifier<List<String>> {
  SubjectsNotifier()
      : super(['Physics', 'Mathematics', 'Chemistry', 'Python / AI']) {
    _loadSubjects();
  }

  void _loadSubjects() {
    final box = Hive.box('settings_box');
    final saved = box.get('subjects_list');
    if (saved is Iterable && saved.isNotEmpty) {
      state = saved.map((e) => e.toString()).toList();
    }
  }

  void addSubject(String newSubject) {
    final trimmed = newSubject.trim();
    if (trimmed.isEmpty || state.contains(trimmed)) return;
    state = [...state, trimmed];
    Hive.box('settings_box').put('subjects_list', state);
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
  MusicSettingsNotifier()
      : super(
          MusicSettings(
            spotifyUrl: 'https://open.spotify.com/search/lofi%20study%20beats',
            ytMusicUrl: 'https://music.youtube.com/search?q=lofi+focus+beats',
          ),
        ) {
    final box = Hive.box('settings_box');
    final sp = box.get('spotify_url')?.toString() ?? state.spotifyUrl;
    final yt = box.get('yt_music_url')?.toString() ?? state.ytMusicUrl;
    state = MusicSettings(spotifyUrl: sp, ytMusicUrl: yt);
  }

  void updateUrls(String spUrl, String ytUrl) {
    final box = Hive.box('settings_box');
    final cleanSp = spUrl.trim().isEmpty ? state.spotifyUrl : spUrl.trim();
    final cleanYt = ytUrl.trim().isEmpty ? state.ytMusicUrl : ytUrl.trim();
    box.put('spotify_url', cleanSp);
    box.put('yt_music_url', cleanYt);
    state = MusicSettings(spotifyUrl: cleanSp, ytMusicUrl: cleanYt);
  }
}

final studyLogsProvider =
    StateNotifierProvider<StudyLogsNotifier, List<StudyBlockLog>>((ref) {
  return StudyLogsNotifier(ref);
});

class StudyLogsNotifier extends StateNotifier<List<StudyBlockLog>> {
  final Ref ref;
  String syncId = '';
  String syncPin = '';

  StudyLogsNotifier(this.ref) : super([]) {
    _loadFromHive();
  }

  void _loadFromHive() {
    final settings = Hive.box('settings_box');
    syncId = settings.get('sync_id')?.toString() ?? '';
    syncPin = settings.get('sync_pin')?.toString() ?? '';

    final box = Hive.box('study_logs_box');
    final List<StudyBlockLog> loaded = [];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) {
        loaded.add(
          StudyBlockLog.fromMap(Map<String, dynamic>.from(raw)),
        );
      }
    }
    loaded.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    state = loaded;

    if (syncId.isNotEmpty && syncPin.isNotEmpty) {
      Future.microtask(() => configureCloudflareSync(syncId, syncPin));
    }
  }

  Future<void> addLog(StudyBlockLog log) async {
    final box = Hive.box('study_logs_box');
    await box.put(log.id, log.toMap());
    state = [log, ...state];
    await _pushToCloud();
  }

  Future<void> deleteLog(String id) async {
    final box = Hive.box('study_logs_box');
    await box.delete(id);
    state = state.where((l) => l.id != id).toList();
    await _pushToCloud();
  }

  Future<void> configureCloudflareSync(String id, String pin) async {
    final cleanId = id.trim();
    final cleanPin = pin.trim();
    if (cleanId.isEmpty || cleanPin.isEmpty) return;

    syncId = cleanId;
    syncPin = cleanPin;
    final settings = Hive.box('settings_box');
    await settings.put('sync_id', syncId);
    await settings.put('sync_pin', syncPin);

    ref.read(syncStatusProvider.notifier).state = 'Syncing...';

    try {
      final uri = Uri.parse(
        '$kDefaultCloudflareWorkerUrl/sync?id=${Uri.encodeComponent(syncId)}&pin=${Uri.encodeComponent(syncPin)}',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['logs'] is Iterable) {
          final remoteLogs = (data['logs'] as Iterable)
              .whereType()
              .map((m) => StudyBlockLog.fromMap(Map<String, dynamic>.from(m)))
              .toList();

          final Map<String, StudyBlockLog> merged = {
            for (final l in state) l.id: l,
            for (final r in remoteLogs) r.id: r,
          };
          final sorted = merged.values.toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

          final box = Hive.box('study_logs_box');
          for (final item in sorted) {
            await box.put(item.id, item.toMap());
          }
          state = sorted;
        }
        await _pushToCloud();
        ref.read(syncStatusProvider.notifier).state = 'Synced ($syncId)';
      } else {
        ref.read(syncStatusProvider.notifier).state = 'Local ($syncId)';
      }
    } catch (_) {
      ref.read(syncStatusProvider.notifier).state = 'Offline ($syncId)';
    }
  }

  Future<void> _pushToCloud() async {
    if (syncId.isEmpty || syncPin.isEmpty) return;
    try {
      final uri = Uri.parse('$kDefaultCloudflareWorkerUrl/sync');
      await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': syncId,
              'pin': syncPin,
              'logs': state.map((e) => e.toMap()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 8));
      ref.read(syncStatusProvider.notifier).state = 'Synced ($syncId)';
    } catch (_) {}
  }

  Future<bool> submitFeedbackToCloud({
    required String sender,
    required String category,
    required int rating,
    required String message,
  }) async {
    try {
      final uri = Uri.parse('$kDefaultCloudflareWorkerUrl/feedback');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'sender': sender.trim().isEmpty ? 'Anonymous' : sender.trim(),
              'category': category,
              'rating': rating,
              'message': message.trim(),
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 8));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<FeedbackItem>> fetchFeedbackInbox(String creatorPin) async {
    final uri = Uri.parse(
      '$kDefaultCloudflareWorkerUrl/feedback?pin=${Uri.encodeComponent(creatorPin.trim())}',
    );
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw Exception('Invalid PIN');
    }
    final data = jsonDecode(resp.body);
    if (data is Map && data['items'] is Iterable) {
      return (data['items'] as Iterable)
          .whereType()
          .map((m) => FeedbackItem.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }
    return [];
  }
}

final recommendedDurationProvider = Provider<int>((ref) {
  final logs = ref.watch(studyLogsProvider);
  if (logs.isEmpty) return 75;
  final latest = logs.first;
  if (latest.fatigueScore >= 4 || latest.memorySpills >= 4) return 45;
  if (latest.fatigueScore <= 2 && latest.memorySpills <= 1) return 90;
  return 75;
});

final recommendedBreakProvider = Provider<int>((ref) {
  final logs = ref.watch(studyLogsProvider);
  if (logs.isEmpty) return 15;
  final latest = logs.first;
  if (latest.fatigueScore >= 4 || latest.memorySpills >= 4) return 25;
  if (latest.fatigueScore <= 2) return 10;
  return 15;
});

class ChatMessage {
  final String role;
  final String subject;
  final String text;

  ChatMessage({
    required this.role,
    required this.subject,
    required this.text,
  });
}

class AiCoachState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String userProfileGoal;

  AiCoachState({
    required this.messages,
    required this.isLoading,
    required this.userProfileGoal,
  });

  AiCoachState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? userProfileGoal,
  }) {
    return AiCoachState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      userProfileGoal: userProfileGoal ?? this.userProfileGoal,
    );
  }
}

final aiCoachProvider =
    StateNotifierProvider<AiCoachNotifier, AiCoachState>((ref) {
  return AiCoachNotifier(ref);
});

class AiCoachNotifier extends StateNotifier<AiCoachState> {
  final Ref ref;
  String groqApiKey = '';

  AiCoachNotifier(this.ref)
      : super(
          AiCoachState(
            messages: [
              ChatMessage(
                role: 'assistant',
                subject: 'Groq AI Mentor',
                text:
                    '👋 **Hey! I am your Personal Subject Mentor & Study Planner.**\n• Pick any subject chip above and ask me **doubts, concepts, or problem-solving tricks**.\n• Tap **Plan Next 3 Blocks** whenever you want a custom schedule built around your latest breadcrumbs!',
              ),
            ],
            isLoading: false,
            userProfileGoal:
                'Class 11 Science (PCM) student preparing for JEE & SAT. Explain concepts clearly with step-by-step intuition.',
          ),
        ) {
    final box = Hive.box('settings_box');
    final savedGoal = box.get('user_profile_goal')?.toString();
    groqApiKey = box.get('groq_api_key')?.toString() ?? '';
    if (savedGoal != null && savedGoal.isNotEmpty) {
      state = state.copyWith(userProfileGoal: savedGoal);
    }
  }

  Future<void> saveUserProfileGoal(String goal) async {
    final clean = goal.trim();
    if (clean.isEmpty) return;
    await Hive.box('settings_box').put('user_profile_goal', clean);
    state = state.copyWith(userProfileGoal: clean);
  }

  Future<void> saveGroqApiKey(String key) async {
    groqApiKey = key.trim();
    await Hive.box('settings_box').put('groq_api_key', groqApiKey);
  }

  void clearChatHistory() {
    state = state.copyWith(
      messages: [
        ChatMessage(
          role: 'assistant',
          subject: 'Groq AI Mentor',
          text:
              'Chat cleared! Ready for your next doubt or study plan.',
        ),
      ],
    );
  }

  Future<void> askAssistant({
    required String userMessage,
    required String currentSubject,
  }) async {
    final userMsg = ChatMessage(
      role: 'user',
      subject: currentSubject,
      text: userMessage.trim(),
    );
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
    );

    try {
      final logs = ref.read(studyLogsProvider);
      final recentSummary = logs
          .take(5)
          .map((l) =>
              '${l.subject} (${l.durationMinutes}m, fatigue ${l.fatigueScore}/5, spills ${l.memorySpills}, breadcrumb: "${l.breadcrumb}")')
          .join('; ');

      String replyText = '';

      if (groqApiKey.isNotEmpty) {
        final resp = await http
            .post(
              Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
              headers: {
                'Authorization': 'Bearer $groqApiKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'model': 'llama-3.3-70b-versatile',
                'messages': [
                  {
                    'role': 'system',
                    'content':
                        'You are NeuroFlow Groq Mentor. Student profile: ${state.userProfileGoal}. Current subject: $currentSubject. Recent study blocks: $recentSummary. Use clean Unicode math and concise bullet points.',
                  },
                  {'role': 'user', 'content': userMessage},
                ],
                'temperature': 0.6,
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          replyText = data['choices']?[0]?['message']?['content']?.toString() ?? '';
        }
      }

      if (replyText.isEmpty) {
        final workerResp = await http
            .post(
              Uri.parse('$kDefaultCloudflareWorkerUrl/mentor'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'subject': currentSubject,
                'profile': state.userProfileGoal,
                'recentLogs': recentSummary,
                'prompt': userMessage,
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (workerResp.statusCode == 200) {
          final data = jsonDecode(workerResp.body);
          replyText = data['reply']?.toString() ?? '';
        }
      }

      if (replyText.isEmpty) {
        replyText =
            '**Quick Interleaving Tip for $currentSubject:**\n• Focus on active problem-solving for the first 45 minutes.\n• If you hit 3+ memory spills, switch subjects or take a 10m walk.\n• *(Tip: Click the Profile icon above to add your free `gsk_...` Groq API key for instant direct AI responses!)*';
      }

      state = state.copyWith(
        messages: [
          ...state.messages,
          ChatMessage(
            role: 'assistant',
            subject: currentSubject,
            text: replyText,
          ),
        ],
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        messages: [
          ...state.messages,
          ChatMessage(
            role: 'assistant',
            subject: currentSubject,
            text:
                'Could not reach Groq Cloud right now ($e). Check your internet connection or custom Groq API key in Profile settings!',
          ),
        ],
        isLoading: false,
      );
    }
  }
}