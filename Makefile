.PHONY: all setup build run clean install release help

PROJECT_NAME = Watt
SCHEME = Watt
BUILD_DIR = build
DERIVED_DATA = $(BUILD_DIR)/DerivedData
APP_PATH = $(DERIVED_DATA)/Build/Products/Debug/$(PROJECT_NAME).app
RELEASE_APP_PATH = $(DERIVED_DATA)/Build/Products/Release/$(PROJECT_NAME).app
EXECUTABLE = $(APP_PATH)/Contents/MacOS/$(PROJECT_NAME)
RELEASE_EXECUTABLE = $(RELEASE_APP_PATH)/Contents/MacOS/$(PROJECT_NAME)

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
		git tag -a "v$$VERSION" -m "Release v$$VERSION" && \
		git push origin "v$$VERSION" && \
		echo "Creating GitHub release v$$VERSION..." && \
		gh release create "v$$VERSION" $(BUILD_DIR)/release/$(PROJECT_NAME).app.zip \
			--title "Watt v$$VERSION" \
			--generate-notes && \
		echo "GitHub release created: v$$VERSION" && \
		sed -i '' "s/version \".*\"/version \"$$VERSION\"/" homebrew/watt.rb && \
		sed -i '' "s/sha256 \".*\"/sha256 \"$$SHA\"/" homebrew/watt.rb && \
		echo "Updated homebrew/watt.rb" && \
		cd homebrew && \
		git add watt.rb && \
		git commit -m "Update to v$$VERSION" && \
		git push && \
		echo "Pushed homebrew update to remote"

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
