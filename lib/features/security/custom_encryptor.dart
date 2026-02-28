import 'package:encrypt_shared_preferences/provider.dart';

/// A custom encryptor implementation using a simple Caesar cipher.
///
/// This class provides basic encryption and decryption functionality
/// suitable for non-sensitive data where high security is not a requirement.
/// The encryption key is interpreted as the shift value for the cipher.
class CustomEncryptor implements IEncryptor {
  /// Determines the shift value for the Caesar cipher based on the provided key.
  ///
  /// Attempts to parse the [key] string as an integer.
  /// If parsing is successful, the parsed integer is used as the shift value.
  /// If parsing fails (e.g., the key is not a valid integer), it defaults to a shift value of 3.
  ///
  /// - Parameter [key]: The encryption key, expected to be a string representation of an integer.
  /// - Returns: The integer shift value to be used in the cipher.
  int _getShift(String key) {
    // Attempt to parse the key as an integer for the shift value.
    // Default to 3 if parsing fails.
    return int.tryParse(key) ?? 3;
  }

  /// Applies the Caesar cipher algorithm to the input text.
  ///
  /// Shifts each alphabetic character in the [text] by the specified [shift] amount.
  /// The direction of the shift is determined by the [encrypt] flag.
  /// Non-alphabetic characters are left unchanged.
  ///
  /// - Parameter [text]: The string to be encrypted or decrypted.
  /// - Parameter [shift]: The number of positions to shift the characters.
  /// - Parameter [encrypt]: If true, performs encryption (positive shift); otherwise, performs decryption (negative shift).
  /// - Returns: The resulting string after applying the Caesar cipher.
  String _caesarCipher(String text, int shift, bool encrypt) {
    StringBuffer result = StringBuffer();
    // Determine the actual shift direction based on whether encrypting or decrypting.
    int actualShift = encrypt ? shift : -shift;

    for (int i = 0; i < text.length; i++) {
      int charCode = text.codeUnitAt(i);

      // Handle uppercase letters (A-Z)
      if (charCode >= 65 && charCode <= 90) {
        int base = 65; // ASCII value of 'A'
        // Apply the shift, wrap around the alphabet using modulo 26
        result.writeCharCode(((charCode - base + actualShift) % 26 + 26) % 26 + base);
      }
      // Handle lowercase letters (a-z)
      else if (charCode >= 97 && charCode <= 122) {
        int base = 97; // ASCII value of 'a'
        // Apply the shift, wrap around the alphabet using modulo 26
        result.writeCharCode(((charCode - base + actualShift) % 26 + 26) % 26 + base);
      } else {
        // Keep non-alphabetic characters unchanged
        result.writeCharCode(charCode);
      }
    }
    return result.toString();
  }

  /// Decrypts the given [encryptedData] using the provided [key].
  ///
  /// It retrieves the shift value from the [key] using [_getShift]
  /// and then applies the Caesar cipher in reverse (decryption mode)
  /// using [_caesarCipher].
  ///
  /// - Parameter [key]: The key used for encryption (determines the shift).
  /// - Parameter [encryptedData]: The data string to be decrypted.
  /// - Returns: The original plain text string.
  @override
  String decrypt(String key, String encryptedData) {
    int shift = _getShift(key);
    // Call _caesarCipher with encrypt=false for decryption
    return _caesarCipher(encryptedData, shift, false);
  }

  /// Encrypts the given [plainText] using the provided [key].
  ///
  /// It retrieves the shift value from the [key] using [_getShift]
  /// and then applies the Caesar cipher in forward (encryption mode)
  /// using [_caesarCipher].
  ///
  /// - Parameter [key]: The key to use for encryption (determines the shift).
  /// - Parameter [plainText]: The data string to be encrypted.
  /// - Returns: The resulting encrypted string.
  @override
  String encrypt(String key, String plainText) {
    int shift = _getShift(key);
    // Call _caesarCipher with encrypt=true for encryption
    return _caesarCipher(plainText, shift, true);
  }
}
