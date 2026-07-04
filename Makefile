APP_NAME       = Skillbox
BUNDLE         = $(APP_NAME).app
BIN_DIR        = .build/release
# Sparkle.framework lives next to the binary in SPM's release output.
SPARKLE_SRC    = $(BIN_DIR)/Sparkle.framework
FRAMEWORKS_DIR = $(BUNDLE)/Contents/Frameworks
SPARKLE_DST    = $(FRAMEWORKS_DIR)/Sparkle.framework
SIGN_IDENTITY  = -

.PHONY: build bundle run install clean

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources $(FRAMEWORKS_DIR)
	cp $(BIN_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/
	cp Sources/Skillbox/Resources/Info.plist.template $(BUNDLE)/Contents/Info.plist
	@# SPM links with rpath=@loader_path; add @executable_path/../Frameworks
	@# so dyld finds Sparkle.framework after we move it into Contents/Frameworks.
	install_name_tool -add_rpath @executable_path/../Frameworks $(BUNDLE)/Contents/MacOS/$(APP_NAME) 2>/dev/null || true
	@if [ ! -d "$(SPARKLE_SRC)" ]; then \
		echo "ERROR: $(SPARKLE_SRC) missing. Run 'swift build -c release' first."; exit 1; \
	fi
	cp -R $(SPARKLE_SRC) $(FRAMEWORKS_DIR)/
	@# Re-sign Sparkle's inner components inside-out (Sparkle docs require this).
	@# Each component is signed before the framework that contains it.
	codesign --force --sign $(SIGN_IDENTITY) --timestamp=none "$(SPARKLE_DST)/Versions/B/XPCServices/Downloader.xpc"
	codesign --force --sign $(SIGN_IDENTITY) --timestamp=none "$(SPARKLE_DST)/Versions/B/XPCServices/Installer.xpc"
	codesign --force --sign $(SIGN_IDENTITY) --timestamp=none "$(SPARKLE_DST)/Versions/B/Updater.app"
	codesign --force --sign $(SIGN_IDENTITY) --timestamp=none "$(SPARKLE_DST)/Versions/B/Autoupdate"
	codesign --force --sign $(SIGN_IDENTITY) --timestamp=none "$(SPARKLE_DST)"
	@# Finally sign the outer app (deep-sign so any leftover unsigned blob is caught).
	codesign --force --sign $(SIGN_IDENTITY) --timestamp=none --deep $(BUNDLE)
	@echo "Built $(BUNDLE)"

install: bundle
	rm -rf /Applications/$(BUNDLE)
	cp -R $(BUNDLE) /Applications/
	@echo "Installed to /Applications/$(BUNDLE)"

run: bundle
	pkill -x $(APP_NAME) 2>/dev/null || true
	open $(BUNDLE)

clean:
	rm -rf .build $(BUNDLE)
