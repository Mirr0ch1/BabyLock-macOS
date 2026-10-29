# Security Policy

## Supported versions

Security fixes are released for the latest stable version. Users on 1.2.2 or
newer receive signed updates and should keep the app updated.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting:

https://github.com/Mirr0ch1/BabyLock-macOS/security/advisories/new

Do not open a public issue for an undisclosed vulnerability. Include the app
version, macOS version, reproduction steps, and any relevant logs.

## Release integrity

Starting with 1.2.2, every release ships:

- `BabyLock-macOS.zip`
- `BabyLock-macOS.zip.sig` — detached Ed25519 signature over the zip bytes
- `BabyLock-macOS.zip.sha256`

The app pins this Ed25519 public key:

```text
6yX33wBdVhlOYROiJ8V+uonayrn2d3BN5Dm0EZhb714=
```

SHA256 fingerprint of the raw public key:

```text
61b78befec58185522871fd1a9c0279d97af5fc425d50ba1c44f99e5563d0cd0
```

The signature is verified **before** the archive is extracted. A missing or
invalid signature is rejected and the current version is kept. Download URLs
and their redirect targets must be HTTPS on GitHub-controlled hosts.

To verify a release locally:

```bash
./Scripts/verify-release.sh v1.2.2
```

This checks the sidecar SHA256, the Ed25519 signature against the pinned key,
the bundle ID/version/build, and that the binary is universal.

### First hop

1.2.0 and 1.2.1 do not contain the signature verification code. The
1.2.0/1.2.1 → 1.2.2 upgrade therefore still uses the old updater. From 1.2.2
onward, every update requires a valid signature. Users who want the signed
path from the first install can install 1.2.2 manually and verify the SHA256
and `.sig` from the release.

## Release process

See [RELEASING.md](RELEASING.md). In short:

- releases are cut from `main` with an annotated `vX.Y.Z` tag;
- tag builds run on `macos-15-intel`, build universal `arm64 + x86_64`, sign
  ad hoc, sign the zip with Ed25519, and publish the zip/signature/SHA256;
- GitHub Actions are pinned to commit SHAs;
- `contents: read` is the default; only the release job gets `contents: write`;
- the private signing key is kept outside the repository and mirrored into the
  `BABYLOCK_UPDATE_SIGNING_KEY` GitHub secret;
- the key is backed up offline; it is never committed or pasted into chat.

A release created manually without the tag workflow will not have a valid
signature and will be rejected by 1.2.2+ clients.

## Scope and limitations

Baby Lock is a convenience child lock for the keyboard, not a security
boundary against a determined local attacker.

- A hardware long press of the power button (5–10 seconds) still forces a
  shutdown.
- Restarting, force-shutting down, or force-quitting does not restore the lock;
  the lock state is in memory only.
- Other processes in the same user session can kill the app, modify
  preferences, inject events with Accessibility permission, or replace the app
  in a user-writable location.
- Voice Control, Siri, Shortcuts, screen sharing, and MDM remote management are
  outside the app's protection.
- The unlock gesture is shown on the HUD and is not a secret.
- The app is ad-hoc signed, not notarized; Gatekeeper may require the
  documented `xattr` step on first install.
- Force-quitting while locked may leave the cursor hidden or frozen until
  sleep/wake or a new login.

## Privacy

The app has no analytics or telemetry and does not log keystrokes. Its only
network requests are the GitHub release check, the signed archive download,
and the detached signature download.
