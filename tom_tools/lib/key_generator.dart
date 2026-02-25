import 'package:pointycastle/asymmetric/api.dart';
import 'package:tom_crypto/tom_crypto.dart';

void main() async {

  var keypair = await RsaKeyHelper.computeRSAKeyPair(RsaKeyHelper.getSecureRandom());

  print("Public Key");
  print(RsaKeyHelper.encodePublicKeyToPemPKCS1(keypair.publicKey as RSAPublicKey));

  print("Private Key");
  print(RsaKeyHelper.encodePrivateKeyToPemPKCS1(keypair.privateKey as RSAPrivateKey));

}