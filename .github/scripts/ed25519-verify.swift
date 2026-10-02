// Checks a Sparkle EdDSA (ed25519) signature the way installed copies will: against SUPublicEDKey.
//
//   xcrun swift .github/scripts/ed25519-verify.swift <SUPublicEDKey> <file> <sparkle:edSignature>   → exit 0 when it verifies
//
// Used by make-appcast.sh and the release workflow, so a SPARKLE_PRIVATE_KEY that is not the pair of the public key in
// Packaging/Info.plist fails the release instead of every user's update. Sparkle's keys are plain Ed25519: the public
// key is the base64 of its 32 bytes, the signature the base64 of 64 bytes. Release tooling only; the app has no Swift.
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4,
      let publicKey = Data(base64Encoded: arguments[1]), publicKey.count == 32,
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
      let signature = Data(base64Encoded: arguments[3]), signature.count == 64,
      let data = FileManager.default.contents(atPath: arguments[2]) else {
    FileHandle.standardError.write(Data("usage: ed25519-verify.swift <SUPublicEDKey> <file> <edSignature>\n".utf8))
    exit(2)
}
exit(key.isValidSignature(signature, for: data) ? 0 : 1)
