import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/chat_repository.dart';

final chatRepoProvider = Provider<ChatRepository>((ref) => ChatRepository());

final messagesProvider = StreamProvider.family((ref, String chatId) =>
    ref.watch(chatRepoProvider).messagesStream(chatId));

final inboxProvider = StreamProvider.family((ref, String uid) =>
    ref.watch(chatRepoProvider).inboxStream(uid));
