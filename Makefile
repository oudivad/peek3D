# Peek3D — building without Xcode.
#
# A Quick Look extension is nothing more than a bundle filed in the right place
# inside an application. Nothing requires Xcode to produce one: the Command Line
# Tools provide the compiler, the SDK and the signing tools. The project
# therefore builds anywhere, continuous integration included, without depending
# on ten gigabytes of IDE.

APP          := Peek3D
VERSION      ?= 1.0.0
BUNDLE_ID    ?= io.github.oudivad.Peek3D
# An OpenCASCADE built by scripts/build-occt.sh leaves a marker naming the macOS
# version it targets. When that marker is present we use that build, which is
# how a release is made. Otherwise we fall back to the Homebrew package, which
# is compiled for the current machine's macOS — handy for development, unfit for
# distribution.
VENDORED     := $(wildcard vendor/occt/.macos-min)
MACOS_MIN    ?= $(if $(VENDORED),$(shell cat $(VENDORED)),$(shell sw_vers -productVersion | cut -d. -f1).0)
ARCH         ?= arm64

# Ad-hoc signature by default, which is enough locally. For a release, pass the
# Developer ID identity (see the README).
CODESIGN_ID  ?= -

# The hardened runtime requires every loaded library to carry the same Team ID
# as the executable. An ad-hoc signature has none, so enabling it on a local
# build stops the application from starting at all. It only makes sense — and is
# then mandatory — with a real Developer ID certificate, for notarization.
CODESIGN_OPTS := $(if $(filter-out -,$(CODESIGN_ID)),-o runtime,)

OCCT_PREFIX  ?= $(if $(VENDORED),$(CURDIR)/vendor/occt,$(shell brew --prefix opencascade 2>/dev/null || echo /opt/homebrew/opt/opencascade))
BREW_PREFIX  ?= $(shell brew --prefix 2>/dev/null || echo /opt/homebrew)

INSTALL_DIR  ?= /Applications
BUILD        := build
OBJ          := $(BUILD)/obj
APP_DIR      := $(BUILD)/$(APP).app
CONTENTS     := $(APP_DIR)/Contents
FRAMEWORKS   := $(CONTENTS)/Frameworks
PLUGINS      := $(CONTENTS)/PlugIns
QL_DIR       := $(PLUGINS)/Peek3DQuickLook.appex
TH_DIR       := $(PLUGINS)/Peek3DThumbnail.appex

KIT_SOURCES  := $(wildcard Sources/Peek3DKit/*.swift)
APP_SOURCES  := $(wildcard Sources/Peek3DApp/*.swift)
QL_SOURCES   := $(wildcard Sources/QuickLookExtension/*.swift)
TH_SOURCES   := $(wildcard Sources/ThumbnailExtension/*.swift)

TARGET       := $(ARCH)-apple-macos$(MACOS_MIN)
SWIFTFLAGS   := -O -swift-version 6 -target $(TARGET) -I Sources/OCCTBridge/include

# Every OpenCASCADE library is offered to the linker, and -dead_strip_dylibs
# keeps only those actually used. That beats maintaining a list by hand which
# would change with every OpenCASCADE release — 7.9, for instance, folded TKSTEP
# into TKDESTEP.
OCCT_LIBS    := $(patsubst $(OCCT_PREFIX)/lib/lib%.dylib,-l%,$(filter-out %.7.9.dylib %.7.9.3.dylib,$(wildcard $(OCCT_PREFIX)/lib/libTK*.dylib)))
LINKFLAGS    := -L $(OCCT_PREFIX)/lib $(OCCT_LIBS) -lc++ -Xlinker -dead_strip_dylibs

SUBST        := sed -e 's|@VERSION@|$(VERSION)|g' -e 's|@BUNDLE_ID@|$(BUNDLE_ID)|g' -e 's|@MACOS_MIN@|$(MACOS_MIN)|g'

.PHONY: all app install uninstall clean test reset-quicklook icon dmg which help

all: app

help:
	@echo "make app        build $(APP_DIR)"
	@echo "make install    install into /Applications and register the extensions"
	@echo "make test       check the loaders against Tests/fixtures"
	@echo "make dmg        build the distribution disk image"
	@echo "make which FILE=… which extension serves this file"
	@echo "make clean      remove build/"
	@echo ""
	@echo "Variables: VERSION BUNDLE_ID MACOS_MIN CODESIGN_ID OCCT_PREFIX"

# --- C++ bridge to OpenCASCADE ------------------------------------------------

$(OBJ)/occt_bridge.o: Sources/OCCTBridge/occt_bridge.cpp Sources/OCCTBridge/include/occt_bridge.h
	@mkdir -p $(OBJ)
	clang++ -std=c++17 -O2 -fvisibility=hidden -target $(TARGET) -Wno-deprecated-declarations \
		-I Sources/OCCTBridge/include -I $(OCCT_PREFIX)/include/opencascade \
		-c $< -o $@

# --- Application --------------------------------------------------------------

app: $(APP_DIR)
	@echo "✓ $(APP_DIR) ($$(du -sh $(APP_DIR) | cut -f1))"

$(APP_DIR): $(OBJ)/occt_bridge.o $(KIT_SOURCES) $(APP_SOURCES) $(QL_SOURCES) $(TH_SOURCES) \
            Resources/App-Info.plist Resources/QuickLook-Info.plist Resources/Thumbnail-Info.plist \
            $(wildcard Resources/*.lproj/Localizable.strings) $(wildcard Resources/AppIcon.icns)
	@rm -rf $(APP_DIR)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources $(FRAMEWORKS) $(QL_DIR)/Contents/MacOS $(TH_DIR)/Contents/MacOS

	@echo "→ application"
	@swiftc $(SWIFTFLAGS) -parse-as-library -module-name Peek3D \
		-o $(CONTENTS)/MacOS/$(APP) \
		$(KIT_SOURCES) $(APP_SOURCES) $(OBJ)/occt_bridge.o \
		$(LINKFLAGS) -Xlinker -rpath -Xlinker @executable_path/../Frameworks

	@echo "→ preview extension"
	@swiftc $(SWIFTFLAGS) -parse-as-library -application-extension -module-name Peek3DQuickLook \
		-o $(QL_DIR)/Contents/MacOS/Peek3DQuickLook \
		$(KIT_SOURCES) $(QL_SOURCES) $(OBJ)/occt_bridge.o \
		$(LINKFLAGS) -Xlinker -e -Xlinker _NSExtensionMain \
		-Xlinker -rpath -Xlinker @executable_path/../../../../Frameworks

	@echo "→ thumbnail extension"
	@swiftc $(SWIFTFLAGS) -parse-as-library -application-extension -module-name Peek3DThumbnail \
		-o $(TH_DIR)/Contents/MacOS/Peek3DThumbnail \
		$(KIT_SOURCES) $(TH_SOURCES) $(OBJ)/occt_bridge.o \
		$(LINKFLAGS) -Xlinker -e -Xlinker _NSExtensionMain \
		-Xlinker -rpath -Xlinker @executable_path/../../../../Frameworks

	@$(SUBST) Resources/App-Info.plist       > $(CONTENTS)/Info.plist
	@$(SUBST) Resources/QuickLook-Info.plist > $(QL_DIR)/Contents/Info.plist
	@$(SUBST) Resources/Thumbnail-Info.plist > $(TH_DIR)/Contents/Info.plist
	@[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns $(CONTENTS)/Resources/ || true

	@# Every bundle carries its own copy of the strings table: inside an
	@# extension, Bundle.main is the extension, not the app containing it.
	@for dir in $(CONTENTS) $(QL_DIR)/Contents $(TH_DIR)/Contents; do \
		mkdir -p $$dir/Resources; \
		cp -R Resources/*.lproj $$dir/Resources/; \
	done

	@echo "→ OpenCASCADE libraries"
	@./scripts/bundle-libs.sh $(CONTENTS)/MacOS/$(APP) $(FRAMEWORKS) \
		$(OCCT_PREFIX)/lib $(BREW_PREFIX)/lib
	@./scripts/bundle-libs.sh $(QL_DIR)/Contents/MacOS/Peek3DQuickLook $(FRAMEWORKS) \
		$(OCCT_PREFIX)/lib $(BREW_PREFIX)/lib
	@./scripts/bundle-libs.sh $(TH_DIR)/Contents/MacOS/Peek3DThumbnail $(FRAMEWORKS) \
		$(OCCT_PREFIX)/lib $(BREW_PREFIX)/lib

	@echo "→ signing"
	@# Order matters: a bundle's signature covers its contents, so sign from
	@# the inside out.
	@for lib in $(FRAMEWORKS)/*.dylib; do codesign -f -s "$(CODESIGN_ID)" $(CODESIGN_OPTS) --timestamp=none "$$lib" 2>/dev/null; done
	@codesign -f -s "$(CODESIGN_ID)" --entitlements Resources/Extension.entitlements $(CODESIGN_OPTS) --timestamp=none $(QL_DIR)
	@codesign -f -s "$(CODESIGN_ID)" --entitlements Resources/Extension.entitlements $(CODESIGN_OPTS) --timestamp=none $(TH_DIR)
	@codesign -f -s "$(CODESIGN_ID)" $(CODESIGN_OPTS) --timestamp=none $(APP_DIR)
	@codesign --verify --deep --strict $(APP_DIR) && echo "  signature verified"

# --- Installation -------------------------------------------------------------

install: app
	@# Since macOS 14, App Management protection stops a program from altering
	@# an already-installed application. A plain `rm -rf` is the wrong probe:
	@# it deletes the contents, then fails on the directory itself, leaving an
	@# empty bundle behind. Renaming is atomic — it either works or changes
	@# nothing — so that is what tests the ground before anything is removed.
	@if [ -e $(INSTALL_DIR)/$(APP).app ]; then \
		if mv $(INSTALL_DIR)/$(APP).app $(INSTALL_DIR)/.$(APP).app.previous 2>/dev/null; then \
			rm -rf $(INSTALL_DIR)/.$(APP).app.previous; \
		else \
			echo "✗ Cannot replace $(INSTALL_DIR)/$(APP).app — nothing was changed."; \
			echo ""; \
			echo "  macOS protects installed applications from changes made in a"; \
			echo "  terminal. To stop this coming back, allow your terminal under"; \
			echo "  System Settings > Privacy & Security > App Management."; \
			echo ""; \
			echo "  Or, just this once: drag $(APP) from $(INSTALL_DIR) to the"; \
			echo "  Trash in the Finder, then run make install again."; \
			exit 1; \
		fi; \
	fi
	@cp -R $(APP_DIR) $(INSTALL_DIR)/
	@# macOS only discovers extensions when it registers the bundle containing
	@# them; without this, nothing happens in the Finder.
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-f $(INSTALL_DIR)/$(APP).app
	@echo "✓ installed in $(INSTALL_DIR)"
	@echo "  Launch the application once: that is when macOS discovers its"
	@echo "  preview extension."

uninstall:
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-u $(INSTALL_DIR)/$(APP).app 2>/dev/null || true
	@rm -rf $(INSTALL_DIR)/$(APP).app 2>/dev/null \
		|| echo "✗ drag $(APP) from $(INSTALL_DIR) to the Trash in the Finder"
	@[ -e $(INSTALL_DIR)/$(APP).app ] || echo "✓ uninstalled"

# Quick Look caches previews eagerly, which makes this essential while
# developing: without it you keep seeing the previous render.
# `qlmanage` hangs regularly, so it is never waited on; stopping the daemons is
# what actually makes the change take effect.
reset-quicklook:
	@(qlmanage -r cache >/dev/null 2>&1 &) ; (qlmanage -r >/dev/null 2>&1 &)
	@killall -9 QuickLookUIService quicklookd 2>/dev/null || true
	@killall Finder 2>/dev/null || true
	@echo "✓ Quick Look cache cleared — reopen your previews"

# --- Tests --------------------------------------------------------------------

test: $(OBJ)/occt_bridge.o
	@mkdir -p $(BUILD)
	@# For a bare executable, Bundle.main is the directory holding it, so the
	@# translations have to sit there for the tests to see them.
	@cp -R Resources/*.lproj $(BUILD)/
	@swiftc $(SWIFTFLAGS) -parse-as-library -module-name Peek3DTests \
		-o $(BUILD)/peek3d-test $(KIT_SOURCES) Tests/LoaderTests.swift \
		$(OBJ)/occt_bridge.o $(LINKFLAGS) \
		-Xlinker -rpath -Xlinker $(OCCT_PREFIX)/lib
	@$(BUILD)/peek3d-test Tests/fixtures

# --- Icon ---------------------------------------------------------------------

# The icon is built from a source that lives in the repository, on demand,
# rather than committed as an opaque binary with nothing to regenerate it.
icon: $(OBJ)/occt_bridge.o
	@mkdir -p $(BUILD)
	@swiftc $(SWIFTFLAGS) -parse-as-library -module-name Peek3DIcon \
		-o $(BUILD)/make-icon $(KIT_SOURCES) Sources/Tools/MakeIcon.swift \
		$(OBJ)/occt_bridge.o $(LINKFLAGS) \
		-Xlinker -rpath -Xlinker $(OCCT_PREFIX)/lib
	@# A hand-drawn image wins; failing that, the icon is rendered from a model
	@# by the application's own engine.
	@if [ -f Resources/AppIcon-source.png ]; then \
		$(BUILD)/make-icon Resources/AppIcon-source.png Resources/AppIcon.icns; \
	else \
		$(BUILD)/make-icon Tests/fixtures/bracket.step Resources/AppIcon.icns; \
	fi

# --- Distribution disk image ---------------------------------------------------

dmg: app
	@rm -f $(BUILD)/$(APP)-$(VERSION).dmg
	@rm -rf $(BUILD)/dmg && mkdir -p $(BUILD)/dmg
	@cp -R $(APP_DIR) $(BUILD)/dmg/
	@# The /Applications shortcut turns the mounted window into its own
	@# instruction: drag the icon on the left onto the one on the right.
	@ln -s /Applications $(BUILD)/dmg/Applications
	@cp README.md LICENSE $(BUILD)/dmg/ 2>/dev/null || true
	@# Sample files in the image: without them a tester's first task is to go
	@# find a 3D model, and many stop right there.
	@mkdir -p $(BUILD)/dmg/Samples
	@cp Tests/fixtures/manifold.step Tests/fixtures/bracket.step \
	    Tests/fixtures/sphere.stl Tests/fixtures/cube.3mf \
	    Tests/fixtures/cube.obj Tests/fixtures/cube_bin.ply \
	    $(BUILD)/dmg/Samples/ 2>/dev/null || true
	@[ -f TESTING.md ] && cp TESTING.md $(BUILD)/dmg/ || true
	@hdiutil create -quiet -volname "$(APP) $(VERSION)" -srcfolder $(BUILD)/dmg \
		-ov -format UDZO $(BUILD)/$(APP)-$(VERSION).dmg
	@rm -rf $(BUILD)/dmg
	@echo "✓ $(BUILD)/$(APP)-$(VERSION).dmg ($$(du -h $(BUILD)/$(APP)-$(VERSION).dmg | cut -f1))"

# --- Diagnostics ----------------------------------------------------------------

# Which extension actually serves a file? Nothing on screen says so, and a
# preview served from cache is indistinguishable from a freshly rendered one.
#   make which FILE=Tests/fixtures/sphere.stl
which:
	@./scripts/which-extension.sh "$(FILE)"

clean:
	rm -rf $(BUILD)
