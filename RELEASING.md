# Releasing Unifind

Unifind ships the same way as Lines: a zipped `Unifind.app` attached to a GitHub release, and a
cask in the `zmscode/homebrew-unifind` tap that points at it. Homebrew disables casks whose apps
fail Gatekeeper, so releases should be signed with a Developer ID and notarized.

## One-time setup

1. **Developer ID and notary credentials:** the same as for Lines (see Lines' RELEASING.md).
   Store a notary profile, e.g. `xcrun notarytool store-credentials unifind-notary …`.
2. **Environment** (fish):

    ```fish
    set -gx UNIFIND_SIGN_IDENTITY "Developer ID Application: Your Name (TEAMID)"
    set -gx UNIFIND_NOTARY_PROFILE unifind-notary
    ```

3. **Repositories:** create `zmscode/Unifind` and the tap `zmscode/homebrew-unifind` (which needs
   only a `Casks/` folder). To share Lines' tap instead, set `tap` in the justfile to
   `zmscode/homebrew-lines`; users would then install with `brew install --cask zmscode/lines/unifind`.

## Each release

1. Set the version in `VERSION` and commit.
2. `just release`: builds, signs, notarizes, staples, zips to `build/Unifind-<version>.zip`, and
   writes the version and SHA-256 into `Casks/unifind.rb`. Commit the cask.
3. `just publish`: creates the `v<version>` GitHub release and pushes the cask to the tap.

`UNIFIND_ALLOW_UNSIGNED=1 just release` builds an ad hoc–signed zip for testing the pipeline.
Gatekeeper rejects it on other Macs, which is what the cask's caveat is for.
