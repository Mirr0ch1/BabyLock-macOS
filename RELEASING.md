# Releasing Baby Lock

All code, tags, and release work happen in this repository:

```text
/home/mirro/coding/BabyLock-macOS
```

The private signing key is **not** in this repository. It lives outside the
working tree and is mirrored into the GitHub Actions secret
`BABYLOCK_UPDATE_SIGNING_KEY`.

## One-time setup

| Item | Location |
|---|---|
| Signing private key | `~/.config/babylock/update-signing-key` (mode `600`) |
| Local backup | `~/.config/babylock/backups/` (mode `600`) |
| GitHub secret | `BABYLOCK_UPDATE_SIGNING_KEY` |
| Pinned public key | `BabyLock/Managers/UpdateSigning.swift` |
| Public key fingerprint | `61b78befec58185522871fd1a9c0279d97af5fc425d50ba1c44f99e5563d0cd0` |
| Release artifacts (local) | `dist/<tag>/` (gitignored) |

Never commit, paste into a chat, or upload the private key. The key is only
needed by CI and by an offline backup.

## Release checklist

### 1. Prepare

Work on a branch and validate with an unsigned manual build:

```bash
cd /home/mirro/coding/BabyLock-macOS
git switch -c fix/1.2.3-something
# edit code
git push -u origin fix/1.2.3-something
gh workflow run build.yml --ref fix/1.2.3-something
```

A `workflow_dispatch` build does not publish a release. Merge only after the
build is green.

### 2. Bump the version

```bash
git switch main
git pull --ff-only
Scripts/bump-version.sh 1.2.3 5
```

This updates the Xcode project, the debug build script, and the settings
version fallback. It does **not** commit.

### 3. Update docs and notes

- README files describe the **current** feature set only. Do not add a
  “What's new” changelog section.
- Put the version-specific release notes in a temporary file, for example
  `/tmp/release-notes-1.2.3.md`. They will be written to the GitHub Release.
- Mention any first-hop caveat, known limitations, and the SHA256/signature
  once the release is built.

### 4. Commit and merge

```bash
git add -A
git commit -m "Release 1.2.3"
git push origin main
```

Wait for the `main` build to finish with `success`. `Scripts/release.sh`
refuses to continue otherwise.

### 5. Tag and publish

```bash
Scripts/release.sh 1.2.3 /tmp/release-notes-1.2.3.md
```

The script:

1. Verifies the working tree is clean, on `main`, and equal to `origin/main`.
2. Verifies the version/build in the project, debug script, and settings.
3. Refuses an existing local/remote tag or release.
4. Refuses if the latest `main` build is not successful.
5. Creates and pushes the annotated `v1.2.3` tag.
6. Waits for the tag workflow on `macos-15-intel`.
7. Runs `Scripts/verify-release.sh v1.2.3`:
   - downloads the zip, `.sig`, and `.sha256` into `dist/v1.2.3/`;
   - checks the SHA256 sidecar;
   - verifies the Ed25519 signature against the pinned public key;
   - checks bundle ID, version, build, minimum macOS, single-instance key;
   - checks the binary is universal `arm64 + x86_64`.
8. If a notes file was passed, replaces the generated release notes.

### 6. Final check

```bash
gh release view v1.2.3 --json url,isDraft,isPrerelease,assets
```

- The release must be **latest** and **not** a prerelease for a stable version.
- The assets must be `BabyLock-macOS.zip`, `BabyLock-macOS.zip.sig`, and
  `BabyLock-macOS.zip.sha256`.
- Do not delete or move a published tag. If the release is bad, publish a
  higher patch version.

## Tag workflow

The tag build uses `macos-15-intel` to avoid unreliable arm64 runner capacity.
`main`/PR builds stay on `macos-15`. The workflow:

- pins every action to a commit SHA;
- runs with `contents: read` by default;
- gives only the `release` job `contents: write`;
- signs the zip with `BABYLOCK_UPDATE_SIGNING_KEY` on tag builds;
- publishes the zip, signature, and SHA256.

A release published manually through the GitHub UI **will not have a valid
signature** and is rejected by 1.2.2 and newer clients. Always use the tag
workflow.

## Key management

### Backups

Keep at least two copies of the private key outside the repository:

1. The local file at `~/.config/babylock/update-signing-key`.
2. An encrypted offline copy (password manager or encrypted USB).

A copy on the same laptop is not a backup against disk loss. The GitHub secret
is the operational copy used by CI, but GitHub secrets cannot be read back, so
the local/offline copy is the only way to rotate or recover.

### Rotation

If the key is compromised:

1. Build and publish a **bridge release** signed with the old key that embeds
   the new public key.
2. Ask users to install the bridge release manually.
3. Replace the GitHub secret with the new private key.
4. Publish subsequent releases signed with the new key.

If the key is lost, 1.2.2+ clients cannot auto-update to a new key; users must
install a new build manually. Keep the backups.

### What the signature covers

The Ed25519 signature covers the exact `BabyLock-macOS.zip` bytes. The app
also checks the bundle ID, version, minimum macOS, and code signature after
extraction. The signature does **not** replace Apple notarization; the build is
still ad-hoc signed, so Gatekeeper may require the `xattr` step on first
install.

## Failure handling

- **Tag build fails:** tags are protected against deletion and force-push.
  Fix the issue on a new commit and cut the next patch version. Do not try to
  move or delete the tag.
- **Release published but wrong:** publish a higher patch version. Do not
  overwrite the asset.
- **Signature verification fails:** stop. Do not publish. Check that the
  `BABYLOCK_UPDATE_SIGNING_KEY` secret matches the pinned public key.
- **Lost key:** see the rotation/recovery section above.

## Useful commands

```bash
Scripts/bump-version.sh 1.2.3 5
Scripts/release.sh 1.2.3 /tmp/release-notes-1.2.3.md
Scripts/verify-release.sh v1.2.3
git status --short
gh run list --workflow=build.yml --limit 10
```
