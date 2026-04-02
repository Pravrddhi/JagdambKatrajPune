/// Stub implementation for non-web platforms
void initializeWebFcmBridge(
  Future<void> Function(String title, String body) onMessage,
) {
  // No-op on non-web platforms
}
