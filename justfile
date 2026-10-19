# Unifind — common tasks. `just` lists them. Recipes run in fish.

set shell := ["fish", "-c"]

app := "build/Unifind.app"
bundle_id := "com.zms.Unifind"
version := trim(read("VERSION"))
# Where releases are published, and the Homebrew tap that installs them.
github := "zmscode/Unifind"
tap := "zmscode/homebrew-unifind"
lsregister := "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

alias b := build
alias r := run
alias i := install
alias t := test

# List the recipes
default:
    @just --list

# Build build/Unifind.app (release by default; `just build debug` for debug)
build config="release":
    #!/usr/bin/env fish
    swift build -c {{ config }}; or exit 1
    set -l bin (swift build -c {{ config }} --show-bin-path)
    rm -rf "{{ app }}"
    mkdir -p "{{ app }}/Contents/MacOS" "{{ app }}/Contents/Resources"
    cp "$bin/Unifind" "{{ app }}/Contents/MacOS/Unifind"
    cp Support/Info.plist "{{ app }}/Contents/Info.plist"
    cp Support/AppIcon.icns "{{ app }}/Contents/Resources/AppIcon.icns"
    # The version from VERSION; the build number counts commits.
    set -l build_number (git rev-list --count HEAD 2>/dev/null; or echo 1)
    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleShortVersionString {{ version }}" \
        -c "Set :CFBundleVersion $build_number" \
        "{{ app }}/Contents/Info.plist"
    # Extended attributes would travel in the zip as ._ files and break the signature.
    xattr -cr "{{ app }}"
    # Developer ID (with the hardened runtime notarization needs) when
    # UNIFIND_SIGN_IDENTITY names one; otherwise ad hoc, to run on this Mac.
    if set -q UNIFIND_SIGN_IDENTITY
        codesign --force --options runtime --timestamp --sign "$UNIFIND_SIGN_IDENTITY" "{{ app }}"; or exit 1
    else
        codesign --force --sign - "{{ app }}"; or exit 1
    end
    # Finder and the Dock cache icons by bundle; re-registering picks up a new one.
    touch "{{ app }}"
    {{ lsregister }} -f "{{ app }}" >/dev/null 2>&1
    echo "Built {{ app }} ({{ version }} build $build_number)"

# Build, quit any running copy, and open the fresh build
run config="release": (build config)
    #!/usr/bin/env fish
    just _quit
    open "{{ app }}"

# Build and install to /Applications, replacing any older copy
install: build
    #!/usr/bin/env fish
    just _quit
    rm -rf /Applications/Unifind.app
    ditto "{{ app }}" /Applications/Unifind.app; or exit 1
    {{ lsregister }} -f /Applications/Unifind.app >/dev/null 2>&1
    echo "Installed /Applications/Unifind.app"

# Remove the copy in /Applications
uninstall:
    #!/usr/bin/env fish
    just _quit
    rm -rf /Applications/Unifind.app
    echo "Removed /Applications/Unifind.app"

[private]
_quit:
    #!/usr/bin/env fish
    if pgrep -xq Unifind
        osascript -e 'tell application id "{{ bundle_id }}" to quit' >/dev/null 2>&1
        for _ in (seq 50)
            pgrep -xq Unifind; or break
            sleep 0.1
        end
    end

# Run the search tests (release, so they're quick)
test:
    swift test -c release -Xswiftc -enable-testing

# Re-render the app icon (Design/RenderIcons.swift) into Support/AppIcon.icns
icon:
    #!/usr/bin/env fish
    set -l work (mktemp -d)
    swiftc -parse-as-library -O Design/RenderIcons.swift -o $work/render-icons; or exit 1
    $work/render-icons Design/icons app-icon; or exit 1
    mkdir -p $work/AppIcon.iconset
    for size in 16 32 128 256 512
        sips -z $size $size Design/icons/app-icon.png --out $work/AppIcon.iconset/icon_{$size}x{$size}.png >/dev/null
        set -l double (math $size \* 2)
        sips -z $double $double Design/icons/app-icon.png --out $work/AppIcon.iconset/icon_{$size}x{$size}@2x.png >/dev/null
    end
    iconutil -c icns $work/AppIcon.iconset -o Support/AppIcon.icns; or exit 1
    rm -rf $work
    echo "Wrote Support/AppIcon.icns"

# Build, sign, notarize and zip a release, and point the cask at it
release:
    #!/usr/bin/env fish
    if not set -q UNIFIND_SIGN_IDENTITY; and not set -q UNIFIND_ALLOW_UNSIGNED
        echo "Set UNIFIND_SIGN_IDENTITY to a Developer ID Application identity (see RELEASING.md)." >&2
        echo "Homebrew disables casks that fail Gatekeeper; UNIFIND_ALLOW_UNSIGNED=1 builds one anyway, for testing." >&2
        exit 1
    end
    just build release; or exit 1
    codesign --verify --strict --deep "{{ app }}"; or exit 1
    set -l zip "build/Unifind-{{ version }}.zip"
    rm -f $zip
    ditto -c -k --norsrc --noextattr --noacl --keepParent "{{ app }}" $zip; or exit 1
    if set -q UNIFIND_NOTARY_PROFILE
        xcrun notarytool submit $zip --keychain-profile "$UNIFIND_NOTARY_PROFILE" --wait; or exit 1
        xcrun stapler staple "{{ app }}"; or exit 1
        spctl --assess --type execute --verbose "{{ app }}"; or exit 1
        # Zip again, so the download carries the stapled ticket.
        rm -f $zip
        ditto -c -k --norsrc --noextattr --noacl --keepParent "{{ app }}" $zip; or exit 1
    else if set -q UNIFIND_SIGN_IDENTITY
        echo "Not notarized: set UNIFIND_NOTARY_PROFILE (see RELEASING.md)." >&2
    end
    # Unpack as Homebrew does (unzip, not ditto) and check the signature survives.
    set -l check (mktemp -d)
    unzip -q $zip -d $check
    codesign --verify --strict $check/Unifind.app; or exit 1
    rm -rf $check
    set -l sha (shasum -a 256 $zip | string split ' ')[1]
    sed -i '' -E \
        -e "s/^  version \".*\"/  version \"{{ version }}\"/" \
        -e "s/^  sha256 .*/  sha256 \"$sha\"/" \
        Casks/unifind.rb
    echo "Built $zip ($sha)"
    echo "Casks/unifind.rb now points at {{ version }}. Next: just publish"

# Publish the release on GitHub and update the tap (run after `just release`)
publish:
    #!/usr/bin/env fish
    set -l zip "build/Unifind-{{ version }}.zip"
    test -f $zip; or begin; echo "No $zip: run just release first." >&2; exit 1; end
    gh release create "v{{ version }}" $zip --repo "{{ github }}" --title "Unifind {{ version }}" --generate-notes; or exit 1
    set -l tapdir (mktemp -d)
    gh repo clone "{{ tap }}" $tapdir -- --depth 1; or exit 1
    mkdir -p $tapdir/Casks
    cp Casks/unifind.rb $tapdir/Casks/unifind.rb
    git -C $tapdir add Casks/unifind.rb
    git -C $tapdir commit -m "unifind {{ version }}"
    git -C $tapdir push origin HEAD; or exit 1
    rm -rf $tapdir
    echo "Published. Install with: brew install --cask {{ replace(tap, "homebrew-", "") }}/unifind"

# Check the cask's style and syntax with Homebrew's own rules
cask-check:
    brew style Casks/unifind.rb

# Remove build products
clean:
    rm -rf build .build
