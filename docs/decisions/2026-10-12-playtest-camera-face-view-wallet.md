# 2026-10-12: playtest notes: face the view, launch camera, wallet identity, icon

Source: a tester's notes on the dApp Store build.

## Camera: a launch along a swung view turned the camera

`FlightCamera._follow_quat` decided "the flight is already along the view"
against the *frame's* forward, not the view the player had swung to. A launch
down a view swung 90-180° read as a big turn, so the whole frame rotated onto
the flight and the camera ended up looking from the ship's front.

- Picked: measure against `view_heading()` (frame × the player's swing) and,
  when swung, aim the frame at the *shortest* turn that puts that heading on
  the flight (`Quaternion(heading, flight) * ref`). Rejected: only widening
  `BEHIND_NEAR_DEG`: the frame kept creeping toward the flight, which pushed
  the swung view further off it (positive feedback).
- `launch_cam_check.gd` now also launches along views swung 90° and 180°
  (0.9° of camera turn; it was 50° and 147°).

## Ship turns to face the view (`cam_face_view`, on by default)

Swing the camera to the resting sling ship's front and the nose eases onto
`view_heading()` (`MovePilot.face_view`, latched: ≥90° swing, nose ≥90° off,
done within 15°). Only when resting (READY) and in the follow views; the aim
pull, flights and auto-volleys keep the nose. Dial: 🎮 Controls panel.
Rejected: always facing the camera's forward at rest (the ship would turn on
its own after every launch; only a swing to its front should move it).

## Wallet: "identity could not be verified"

The live `https://gunroarcannon.github.io/.well-known/assetlinks.json` listed
`com.critbox.yeetfleet` with the debug key only; the dApp Store APK is signed
with the release key (`49:45:…:E6:D7`). `launch/assetlinks.json` has both: it
has to be copied to the Pages repo and pushed.

## Sign-in / shop

Mainnet Worker answers `/auth/verify` with `misconfigured: SESSION_SECRET is
not set` (checked 2026-10-12), so a mainnet sign-in signs in the wallet but
never opens a session, and the shop asks again. Needs the secret put (see the
Worker README). In the app: the shop says why (it used to say nothing), the
header says "wallet connected, not signed in", and SIGN IN reads CANCEL while
the wallet is open so the request can always be ended.

## Sandbox, icon

- Sandbox flights get a one-line brief on the hint line (2.5 s in).
- Launcher icons: adaptive foreground/background from `launch/icon_512.png`,
  the logo scaled into the 66dp safe circle (`launch/icons/adaptive_*_432.png`,
  `main_192.png`), set on both export presets. No monochrome layer yet.
