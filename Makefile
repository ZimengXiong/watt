.PHONY: all setup build build-release run open run-release clean install uninstall xcode \
	build-verbose release guard-clean guard-publish help

# Recipes below pipe xcodebuild through filters and check exit codes. Without
# pipefail, `xcodebuild ... | tail` reports the status of tail, so a build or test
# failure can look like success. bash is named explicitly because /bin/sh on
# some hosts is dash, which has no pipefail.
SHELL := /bin/bash
.SHELLFLAGS = -o pipefail -c

PROJECT_NAME = Watt
SCHEME = Watt
BUILD_DIR = build
DERIVED_DATA = $(BUILD_DIR)/DerivedData
APP_PATH = $(DERIVED_DATA)/Build/Products/Debug/$(PROJECT_NAME).app
RELEASE_APP_PATH = $(DERIVED_DATA)/Build/Products/Release/$(PROJECT_NAME).app
EXECUTABLE = $(APP_PATH)/Contents/MacOS/$(PROJECT_NAME)
RELEASE_EXECUTABLE = $(RELEASE_APP_PATH)/Contents/MacOS/$(PROJECT_NAME)

# The single source of truth for the version is project.yml.
MARKETING_VERSION := $(shell sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1)

# GitHub repository `gh` talks to, resolved from the current clone. Override with
# GH_REPO=owner/repo when publishing somewhere other than origin.
GH_REPO ?= $(shell gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)

# Code signing.
#
# These defaults are the maintainer's own Apple Development certificate, which
# exists in exactly one keychain. Everyone else - forks, CI, a fresh clone - can
# build without editing this file:
#
#   make build SIGN_IDENTITY=      # ad-hoc sign, no team (this is what CI uses)
#   make build SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" TEAM_ID=TEAMID
#
# project.yml already defaults to ad-hoc signing; these flags override it only
# when you pass an identity.
TEAM_ID ?= W9C2P3N7Q2
SIGN_IDENTITY ?= Apple Development: zxzimeng@gmail.com (4F7GA4MB42)

ifeq ($(strip $(SIGN_IDENTITY)),)
	SIGN_FLAGS = CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" CODE_SIGN_IDENTITY="-"
else
	SIGN_FLAGS = CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=$(TEAM_ID) "CODE_SIGN_IDENTITY=$(SIGN_IDENTITY)"
endif

# `make release` publishes: it pushes a branch, tags it, and creates a GitHub
# release. It therefore refuses to run without being told which remote you own.
# There is deliberately no default for REMOTE.
REMOTE ?=
BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null)

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

# Release-configuration build only. Packaging, tagging and publishing live in
# `release`, so building a release binary never touches a remote.
build-release: setup
	@echo "Building $(PROJECT_NAME) (Release)..."
	@mkdir -p $(BUILD_DIR)
	@xcodebuild -project $(PROJECT_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		-quiet \
		$(SIGN_FLAGS) \
		build
	@echo "Release build completed: $(RELEASE_APP_PATH)"

# ---- release pipeline guards ----------------------------------------------------------------------

guard-clean:
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "Error: Working directory has uncommitted changes. Commit or stash them first."; \
		exit 1; \
	fi

guard-publish: guard-clean
	@if [ -z "$(REMOTE)" ]; then \
		echo "Refusing to publish: no remote to publish to."; \
		echo "  make release REMOTE=<remote you own>   # e.g. origin on your own fork"; \
		exit 1; \
	fi
	@if [ -z "$(MARKETING_VERSION)" ]; then \
		echo "Refusing to publish: could not read MARKETING_VERSION from project.yml."; \
		exit 1; \
	fi
	@found="$$(git tag -l "v$(MARKETING_VERSION)" | head -1)"; \
	if [ -n "$$found" ]; then \
		echo "Refusing to publish: v$(MARKETING_VERSION) is already tagged locally."; \
		echo "  Bump MARKETING_VERSION in project.yml first - republishing over a"; \
		echo "  released tag would rewrite an existing download."; \
		exit 1; \
	fi
	@if git ls-remote --tags "$(REMOTE)" "refs/tags/v$(MARKETING_VERSION)" 2>/dev/null | grep -q "v$(MARKETING_VERSION)"; then \
		echo "Refusing to publish: v$(MARKETING_VERSION) already exists on $(REMOTE)."; \
		echo "  Bump MARKETING_VERSION in project.yml first."; \
		exit 1; \
	fi
	@echo "This will:"
	@echo "  1. push $(BRANCH) to $(REMOTE)"
	@echo "  2. tag v$(MARKETING_VERSION) and push the tag to $(REMOTE)"
	@echo "  3. create a GitHub release on $(if $(GH_REPO),$(GH_REPO),the repo of $(REMOTE)) with the app zip"
	@echo "  4. update homebrew/Casks/watt.rb, if that path exists"
	@if [ "$(YES)" != "1" ]; then \
		read -r -p "Continue? [type yes] " answer; \
		[ "$$answer" = "yes" ] || { echo "Aborted, nothing published."; exit 1; }; \
	fi

release: guard-publish build-release
	@echo "Pushing $(BRANCH) to $(REMOTE)..."
	@git push "$(REMOTE)" "refs/heads/$(BRANCH)"
	@echo "Packaging for distribution..."
	@mkdir -p $(BUILD_DIR)/release
	@rm -f $(BUILD_DIR)/release/$(PROJECT_NAME).app.zip
	@cd $(DERIVED_DATA)/Build/Products/Release && zip -rq $(PROJECT_NAME).app.zip $(PROJECT_NAME).app
	@mv $(DERIVED_DATA)/Build/Products/Release/$(PROJECT_NAME).app.zip $(BUILD_DIR)/release/
	@echo "Package: $(BUILD_DIR)/release/$(PROJECT_NAME).app.zip"
	@VERSION="$(MARKETING_VERSION)"; \
		SHA=$$(shasum -a 256 $(BUILD_DIR)/release/$(PROJECT_NAME).app.zip | cut -d' ' -f1) && \
		REPO="$(GH_REPO)" && \
		echo "Version: $$VERSION" && \
		echo "SHA256: $$SHA" && \
		echo "Creating git tag v$$VERSION..." && \
		git tag -a "v$$VERSION" -m "Release v$$VERSION" && \
		git push "$(REMOTE)" "v$$VERSION" && \
		echo "Creating GitHub release v$$VERSION..." && \
		gh release create "v$$VERSION" $(BUILD_DIR)/release/$(PROJECT_NAME).app.zip \
			$${REPO:+--repo $$REPO} \
			--title "$(PROJECT_NAME) v$$VERSION" \
			--generate-notes && \
		echo "GitHub release created: v$$VERSION" && \
		if [ -f homebrew/Casks/watt.rb ]; then \
			sed -i '' "s/version \".*\"/version \"$$VERSION\"/" homebrew/Casks/watt.rb && \
			sed -i '' "s/sha256 \".*\"/sha256 \"$$SHA\"/" homebrew/Casks/watt.rb && \
			echo "Updated homebrew/Casks/watt.rb" && \
			cd homebrew && \
			git add Casks/watt.rb && \
			git commit -m "Update to v$$VERSION" && \
			git push && \
			echo "Pushed homebrew update to remote"; \
		else \
			echo "Skipping the Homebrew tap: homebrew/Casks/watt.rb does not exist in this checkout."; \
			echo "Note that .gitignore lists homebrew/, so a fresh clone can never have it -"; \
			echo "add the tap as a submodule or a gitlink if \`make release\` should update it."; \
		fi

run: build
	@$(EXECUTABLE)

open: build
	@open $(APP_PATH)

run-release: build-release
	@$(RELEASE_EXECUTABLE)

clean:
	@rm -rf $(BUILD_DIR)
	@rm -rf $(PROJECT_NAME).xcodeproj
	@rm -rf *.xcworkspace
	@echo "Clean completed!"

# Build-and-copy only: installing a local build must never publish anything, so
# this depends on build-release, not on release.
install: build-release
	@echo "Installing $(PROJECT_NAME) to /Applications..."
	@rm -rf /Applications/$(PROJECT_NAME).app
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
	@echo "  build-release Build the app (release configuration), publish nothing"
	@echo "  install       Release build to /Applications (no push, no tag, no release)"
	@echo "  release       MAINTAINER ONLY: push, tag, GitHub release, homebrew tap"
	@echo "                  needs REMOTE=<your remote> and a typed confirmation"
	@echo "  run           Build and run the executable directly"
	@echo "  open          Build and open the app bundle"
	@echo "  run-release   Build and run release version"
	@echo "  clean         Remove build artifacts and generated project"
	@echo "  uninstall     Remove from /Applications"
	@echo "  xcode         Open project in Xcode"
	@echo "  help          Show this help message"
	@echo ""
	@echo "Signing:"
	@echo "  make build                        # maintainer certificate (default)"
	@echo "  make build SIGN_IDENTITY=         # ad-hoc, no Apple account needed"
	@echo ""
	@echo "Examples:"
	@echo "  make build                # Build debug"
	@echo "  make install              # Release build into /Applications"
	@echo "  make release REMOTE=origin# Full publish flow, after review"
