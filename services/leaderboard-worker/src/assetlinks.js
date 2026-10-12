// The Digital Asset Links statement list for the game's APK, served at
// /.well-known/assetlinks.json. A wallet (Phantom) verifies a dApp's identity by
// fetching this from the identity URI's origin, and its verifier only accepts a
// Content-Type of exactly "application/json": GitHub Pages sends
// "application/json; charset=utf-8", which can never verify. The game's identity
// is therefore this Worker's own origin (modules/chain/scripts/chain.gd).

/** SHA-256 of the signing certificates: Godot's debug key, and the release key. */
export const CERT_FINGERPRINTS = [
  "4B:08:DB:CC:74:60:1D:D6:86:DE:AD:7E:31:21:6C:AB:F6:B1:D8:65:D6:5E:C0:9A:8E:30:88:43:9D:FD:E5:21",
  "49:45:C4:6E:23:0E:C3:52:49:E6:00:DE:F8:9F:B0:70:67:E8:37:17:B0:B7:A8:79:AA:16:7B:3D:24:56:E6:D7",
];

export const PACKAGE_NAME = "com.critbox.yeetfleet";

/** The statement list. */
export function assetLinks() {
  return [{
    relation: ["delegate_permission/common.handle_all_urls"],
    target: {
      namespace: "android_app",
      package_name: PACKAGE_NAME,
      sha256_cert_fingerprints: CERT_FINGERPRINTS,
    },
  }];
}
