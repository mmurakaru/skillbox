APP_NAME = Skillbox
BUNDLE   = $(APP_NAME).app
BIN_DIR  = .build/release

.PHONY: build bundle run install clean

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BIN_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/
	cp Sources/Skillbox/Resources/Info.plist.template $(BUNDLE)/Contents/Info.plist
	codesign --force --sign - $(BUNDLE)
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
