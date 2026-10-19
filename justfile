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
build config="release": _icon
    #!/usr/bin/env fish
    swift build -c {{ config }}; or exit 1
    set -l bin (swift build -c {{ config }} --show-bin-path)
    rm -rf "{{ app }}"
    mkdir -p "{{ app }}/Contents/MacOS" "{{ app }}/Contents/Resources"
    cp "$bin/Unifind" "{{ app }}/Contents/MacOS/Unifind"
    cp Support/Info.plist "{{ app }}/Contents/Info.plist"
    cp build/icon/AppIcon.icns "{{ app }}/Contents/Resources/AppIcon.icns"
    test -f build/icon/Assets.car; and cp build/icon/Assets.car "{{ app }}/Contents/Resources/Assets.car"
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
        for attempt in (seq 50)
            pgrep -xq Unifind; or break
            sleep 0.1
        end
    end

# Run the search tests (release, so they're quick)
test:
    swift test -c release -Xswiftc -enable-testing

# The app icon is an Icon Composer document (Support/AppIcon.icon: a gradient fill, a glass
# tile and the star, as SVG layers). actool compiles it into Assets.car, which the Dock uses on
# macOS 26+, plus a fallback AppIcon.icns. If actool can't run (Xcode's first-launch setup not
# done), Icon Composer's ictool renders a static .icns instead.
# Compile the app icon into build/icon when it has changed
[private]
_icon:
    #!/usr/bin/env fish
    set -l icon Support/AppIcon.icon
    if test -f build/icon/AppIcon.icns; and test -z "$(find $icon -newer build/icon/AppIcon.icns)"
        exit 0
    end
    rm -rf build/icon
    mkdir -p build/icon
    if not xcrun actool $icon --compile build/icon --platform macosx --minimum-deployment-target 26.0 \
            --app-icon AppIcon --output-partial-info-plist build/icon/partial.plist >/dev/null 2>build/icon/actool.log
        or not test -f build/icon/Assets.car
        echo "actool failed (see build/icon/actool.log); rendering a static icon with ictool" >&2
        rm -f build/icon/Assets.car
        set -l ictool (xcode-select -p)/../Applications/Icon\ Composer.app/Contents/Executables/ictool
        mkdir -p build/icon/AppIcon.iconset
        for size in 16 32 128 256 512
            for scale in 1 2
                set -l suffix (test $scale = 2; and echo @2x)
                $ictool $icon --export-image --platform macOS --rendition Default \
                    --width $size --height $size --scale $scale \
                    --output-file build/icon/AppIcon.iconset/icon_{$size}x{$size}$suffix.png >/dev/null; or exit 1
            end
        end
        iconutil -c icns build/icon/AppIcon.iconset -o build/icon/AppIcon.icns; or exit 1
    end

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

# Export the character index and themes for the web version (Web/public/data)
web-data:
    #!/usr/bin/env fish
    mkdir -p build/web-export
    swiftc -O -swift-version 6 -o build/web-export/unifind-export \
        Sources/Unifind/CharacterIndex.swift Sources/Unifind/Theme.swift Web/export/main.swift; or exit 1
    ./build/web-export/unifind-export Web/public/data

# Run the web version's dev server
web: _web-deps
    cd Web; and npm run dev

# Build the web version into Web/dist
web-build: _web-deps
    cd Web; and npm run build

# Run the web version's search tests against the exported data
web-test: _web-deps
    cd Web; and npm test

[private]
_web-deps:
    #!/usr/bin/env fish
    cd Web
    if not test -d node_modules; or test package-lock.json -nt node_modules
        npm ci; or exit 1
    end
