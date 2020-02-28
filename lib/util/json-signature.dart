import 'dart:convert';
import '../crypto/signature.dart';

/// Sign the given body using privateKey. Returns an hex-encoded string with the signature.
Future<String> signJsonPayload(Map<String, dynamic> body, String privateKey,
    {int chainId}) {
  // Ensure alphabetically ordered key names
  final sortedBody = sortMapFields(body);
  final strBody = jsonEncode(sortedBody);

  return signString(strBody, privateKey, chainId: chainId);
}

/// Check whether the given signature matches the given body and publicKey.
/// Returns true if no publicKey is given
Future<bool> isValidJsonSignature(
    String signature, Map<String, dynamic> body, String publicKey,
    {int chainId}) {
  if (signature == null || body == null)
    throw Exception("Invalid parameters");
  else if (publicKey == null || publicKey == "") return Future.value(true);

  // Ensure alphabetically ordered key names
  final sortedBody = sortMapFields(body);
  final strBody = jsonEncode(sortedBody);

  return verifySignature(signature, strBody, publicKey, chainId: chainId);
}

// ----------------------------------------------------------------------------
// Helper functions
// ----------------------------------------------------------------------------

/// Signatures need to be computed over objects that can be 100% reproduceable.
/// Since the ordering is not guaranteed, this function returns a recursively
/// ordered map
Map<String, dynamic> sortMapFields(Map<String, dynamic> data) {
  List<String> keys = [];
  Map<String, dynamic> result = Map<String, dynamic>();

  data.forEach((k, v) {
    keys.add(k);
  });
  keys.sort((String a, String b) => a.compareTo(b));
  keys.forEach((k) {
    if (data[k] is Map) {
      result[k] = sortMapFields(data[k]);
    } else {
      result[k] = data[k];
    }
  });
  return result;
}
