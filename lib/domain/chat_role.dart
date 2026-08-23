/// Who produced a message.
///
/// The wire values are the strings llama.cpp's chat templates expect, so they are also what
/// goes into the database and into `lc_chat_apply_template`. Do not rename them.
enum ChatRole {
  system('system'),
  user('user'),
  assistant('assistant');

  const ChatRole(this.wireValue);

  final String wireValue;

  static ChatRole fromWireValue(String value) {
    return ChatRole.values.firstWhere(
      (role) => role.wireValue == value,
      orElse: () => ChatRole.user,
    );
  }
}
