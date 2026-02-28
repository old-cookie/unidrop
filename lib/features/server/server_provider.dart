import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents the state of the server.
class ServerState {
  /// Whether the server is currently running.
  final bool isRunning;

  /// The port the server is listening on. Null if the server is not running.
  final int? port;

  /// An error message if the server failed to start or encountered an error. Null otherwise.
  final String? error;

  /// Creates a new [ServerState].
  const ServerState({this.isRunning = false, this.port, this.error});

  /// Creates a copy of this [ServerState] with the given fields updated.
  ServerState copyWith(
      {bool? isRunning, int? port, String? error, bool clearError = false}) {
    return ServerState(
        isRunning: isRunning ?? this.isRunning,
        port: port ?? this.port,
        error: clearError ? null : error ?? this.error);
  }
}

/// Manages the state of the server.
class ServerStateNotifier extends Notifier<ServerState> {
  /// Creates a new [ServerStateNotifier] with the initial state.
  @override
  ServerState build() => const ServerState();

  /// Sets the server state to running on the specified [port].
  void setRunning(int port) {
    state = state.copyWith(
        isRunning: true, port: port, /* https: https, */ clearError: true);
  }

  /// Sets the server state to stopped.
  void setStopped() {
    state = state.copyWith(
        isRunning: false, port: null, /* https: false, */ clearError: true);
  }

  /// Sets the server state to an error state with the given [error] message.
  void setError(String error) {
    state = state.copyWith(
        isRunning: false, error: error, port: null /* https: false */);
  }
}

/// Provides the [ServerStateNotifier] and its state [ServerState].
final serverStateProvider =
    NotifierProvider<ServerStateNotifier, ServerState>(ServerStateNotifier.new);
