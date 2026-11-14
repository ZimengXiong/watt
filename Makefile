.PHONY: all setup build test run clean install release help

PROJECT_NAME = Watt
SCHEME = Watt
BUILD_DIR = build
DERIVED_DATA = $(BUILD_DIR)/DerivedData
APP_PATH = $(DERIVED_DATA)/Build/Products/Debug/$(PROJECT_NAME).app
RELEASE_APP_PATH = $(DERIVED_DATA)/Build/Products/Release/$(PROJECT_NAME).app
EXECUTABLE = $(APP_PATH)/Contents/MacOS/$(PROJECT_NAME)
RELEASE_EXECUTABLE = $(RELEASE_APP_PATH)/Contents/MacOS/$(PROJECT_NAME)

# Code signing (Apple Development cert)
TEAM_ID = W9C2P3N7Q2
SIGN_IDENTITY = Apple Development: zxzimeng@gmail.com (4F7GA4MB42)
SIGN_FLAGS = CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=$(TEAM_ID) "CODE_SIGN_IDENTITY=$(SIGN_IDENTITY)"

all: build

setup:
	@xcodegen generate

build: setup
	@echo "Building $(PROJECT_NAME)..."
	@mkdir -p $(BUILD_DIR)
	@xcodebuild -project $(PROJECT_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		-quiet \
		$(SIGN_FLAGS) \
		build
	@echo "Build completed: $(APP_PATH)"

release: setup
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "Error: Working directory has uncommitted changes. Commit or stash them first."; \
		exit 1; \
	fi
	@echo "Pushing to origin..."
	@git push origin
	@mkdir -p $(BUILD_DIR)
	@xcodebuild -project $(PROJECT_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		-quiet \
		$(SIGN_FLAGS) \
		build
	@echo "Release build completed: $(RELEASE_APP_PATH)"
	@echo "Packaging for distribution..."
	@mkdir -p $(BUILD_DIR)/release
	@cd $(DERIVED_DATA)/Build/Products/Release && zip -rq $(PROJECT_NAME).app.zip $(PROJECT_NAME).app
	@mv $(DERIVED_DATA)/Build/Products/Release/$(PROJECT_NAME).app.zip $(BUILD_DIR)/release/
	@echo "Package: $(BUILD_DIR)/release/$(PROJECT_NAME).app.zip"
	@VERSION=$$(grep 'MARKETING_VERSION:' project.yml | sed 's/.*: //') && \
		SHA=$$(shasum -a 256 $(BUILD_DIR)/release/$(PROJECT_NAME).app.zip | cut -d' ' -f1) && \
		echo "Version: $$VERSION" && \
		echo "SHA256: $$SHA" && \
		echo "Creating git tag v$$VERSION..." && \
		git tag -a "v$$VERSION" -m "Release v$$VERSION" -f && \
		git push origin "v$$VERSION" -f && \
		echo "Creating GitHub release v$$VERSION..." && \
		gh release create "v$$VERSION" $(BUILD_DIR)/release/$(PROJECT_NAME).app.zip \
			--title "Watt v$$VERSION" \
			--generate-notes && \
		echo "GitHub release created: v$$VERSION" && \
		sed -i '' "s/version \".*\"/version \"$$VERSION\"/" homebrew/Casks/watt.rb && \
		sed -i '' "s/sha256 \".*\"/sha256 \"$$SHA\"/" homebrew/Casks/watt.rb && \
		echo "Updated homebrew/Casks/watt.rb" && \
		cd homebrew && \
		git add Casks/watt.rb && \
		git commit -m "Update to v$$VERSION" && \
		git push -f && \
		echo "Pushed homebrew update to remote"

# xcodebuild buries the verdict in a wall of log, so the tail is what a human reads.
# The status has to survive that deliberately: Apple's /usr/bin/make is a GNU Make
# 3.81 that ignores .SHELLFLAGS and invokes the shell as `-c <recipe>` (measured by
# pointing SHELL at a logging wrapper), so `xcodebuild test | tail` reports the
# status of tail and exits 0 on a red suite. Captured by hand instead.
#
# The second check is not decoration either: `xcodebuild -only-testing:<nothing>`
# prints "Executed 0 tests", then "** TEST SUCCEEDED **", and exits 0. A renamed
# test target would therefore delete coverage silently, on any make, in any CI.
# TEST_FILTER is overridable so that guard is itself exercisable.
TEST_FILTER ?= $(PROJECT_NAME)Tests

test: setup
	@echo "Running tests..."
	@mkdir -p $(BUILD_DIR)
	@xcodebuild -project $(PROJECT_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		-destination "platform=macOS,arch=arm64" \
		-only-testing:$(TEST_FILTER) \
		test > $(BUILD_DIR)/test.log 2>&1; \
	status=$$?; \
	tail -n 30 $(BUILD_DIR)/test.log; \
	if [ $$status -ne 0 ]; then \
		echo "test: xcodebuild exited $$status - full log at $(BUILD_DIR)/test.log"; \
		exit $$status; \
	fi; \
	ran=$$(grep -Eo 'Executed [0-9]+ tests' $(BUILD_DIR)/test.log | head -1 | awk '{print $$2}'); \
	if [ "$${ran:-0}" -eq 0 ]; then \
		echo "test: 0 tests executed. -only-testing:$(TEST_FILTER) matched nothing,"; \
		echo "       and xcodebuild reports that as TEST SUCCEEDED with exit 0."; \
		exit 1; \
	fi; \
	echo "test: $$ran test(s) executed, all green"

run: build
	@$(EXECUTABLE)

open: build
	@open $(APP_PATH)

run-release: release
	@$(RELEASE_EXECUTABLE)

clean:
	@rm -rf $(BUILD_DIR)
	@rm -rf $(PROJECT_NAME).xcodeproj
	@rm -rf *.xcworkspace
	@echo "Clean completed!"

install: release
	@echo "Installing $(PROJECT_NAME) to /Applications..."
	@cp -R $(RELEASE_APP_PATH) /Applications/
	@echo "Installed to /Applications/$(PROJECT_NAME).app"

uninstall:
	@echo "Removing $(PROJECT_NAME) from /Applications..."
	@rm -rf /Applications/$(PROJECT_NAME).app
	@echo "Uninstalled!"

xcode: setup
	@echo "Opening project in Xcode..."
	@open $(PROJECT_NAME).xcodeproj

build-verbose: setup
	@echo "Building $(PROJECT_NAME) (verbose)..."
	@mkdir -p $(BUILD_DIR)
	@xcodebuild -project $(PROJECT_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		build

help:
	@echo "Watt - macOS Power Monitor"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  setup         Generate Xcode project with XcodeGen"
	@echo "  build         Build the app (debug configuration)"
	@echo "  test          Run the unit tests"
	@echo "  release       Build release, package zip, update homebrew"
	@echo "  run           Build and run the executable directly"
	@echo "  open          Build and open the app bundle"
	@echo "  run-release   Build and run release version"
	@echo "  clean         Remove build artifacts and generated project"
	@echo "  install       Install release build to /Applications"
	@echo "  uninstall     Remove from /Applications"
	@echo "  xcode         Open project in Xcode"
	@echo "  help          Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make build    # Build debug"
	@echo "  make release  # Build release + update homebrew"
	@echo "  make install  # Install to /Applications"
