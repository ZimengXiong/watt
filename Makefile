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
	@mkdir -p $(BUILD_DIR)
	@xcodebuild -project $(PROJECT_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		-quiet \
		build
	@echo "Release build completed: $(RELEASE_APP_PATH)"

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
	@echo "  release       Build the app (release configuration)"
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
	@echo "  make build    # Build the app"
	@echo "  make run      # Build and run"
	@echo "  make clean    # Clean everything"
