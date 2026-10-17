BOLD  := \033[1m
CYAN  := \033[36m
GREEN := \033[32m
RESET := \033[0m

.DEFAULT_GOAL := help

DIST := .local/dist
APP := $(DIST)/spale.app
ICONSET := $(DIST)/AppIcon.iconset
BUNDLE_ID := us.samzong.spale
TARGET := /Applications/spale.app
EXECUTABLE := $(TARGET)/Contents/MacOS/spale
BIN := /opt/homebrew/bin
COMMANDS := spale code
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# ── Build ────────────────────────────────────────────────────────────────────

.PHONY: build check icon

build: ## Release build of spale
	swift build -c release

check: ## Run the core contract checks
	swift run CoreContracts
	@printf '\n$(GREEN)  ✓ All checks passed$(RESET)\n\n'

icon: ## Render Resources/logo.svg into Resources/AppIcon.icns
	rm -rf "$(ICONSET)"
	mkdir -p "$(ICONSET)"
	qlmanage -t -s 1024 -o "$(ICONSET)" Resources/logo.svg >/dev/null
	@for size in 16 32 128 256 512; do \
		sips -z $$size $$size "$(ICONSET)/logo.svg.png" --out "$(ICONSET)/icon_$${size}x$${size}.png" >/dev/null; \
		sips -z $$((size * 2)) $$((size * 2)) "$(ICONSET)/logo.svg.png" --out "$(ICONSET)/icon_$${size}x$${size}@2x.png" >/dev/null; \
	done
	rm "$(ICONSET)/logo.svg.png"
	iconutil -c icns "$(ICONSET)" -o Resources/AppIcon.icns
	rm -rf "$(ICONSET)"
	@printf '$(GREEN)  ✓ Resources/AppIcon.icns$(RESET)\n'

# ── App ──────────────────────────────────────────────────────────────────────

.PHONY: app install uninstall quit

app: build ## Package .local/dist/spale.app
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp Info.plist "$(APP)/Contents/Info.plist"
	cp -R Resources/AppIcon.icns Resources/Fonts "$(APP)/Contents/Resources/"
	cp .build/release/spale "$(APP)/Contents/MacOS/spale"
	@identity="$$(security find-identity -v -p codesigning | awk -F '"' '/Apple Development: / { print $$2 }')"; \
	if [ -z "$$identity" ] || [ "$$(printf '%s\n' "$$identity" | wc -l | tr -d ' ')" != 1 ]; then \
		echo 'Exactly one Apple Development identity is required.' >&2; exit 1; \
	fi; \
	echo "spale: signing as $$identity"; \
	codesign --force --options runtime --sign "$$identity" "$(APP)" && codesign --verify --strict "$(APP)"
	@printf '$(GREEN)  ✓ %s$(RESET)\n' "$(APP)"

install: app ## Replace /Applications/spale.app and link the spale and code commands
	@for name in $(COMMANDS); do \
		link="$(BIN)/$$name"; \
		if { [ -e "$$link" ] || [ -L "$$link" ]; } && [ "$$(readlink "$$link")" != "$(EXECUTABLE)" ]; then \
			echo "$$link belongs to another installation." >&2; exit 1; \
		fi; \
	done
	@if [ -e "$(TARGET)" ] && ! /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$(TARGET)/Contents/Info.plist" | grep -qx "$(BUNDLE_ID)"; then \
		echo "$(TARGET) belongs to another app." >&2; exit 1; \
	fi
	@$(MAKE) --no-print-directory quit
	rm -rf "$(TARGET)"
	ditto "$(APP)" "$(TARGET)"
	@for name in $(COMMANDS); do ln -sfn "$(EXECUTABLE)" "$(BIN)/$$name"; done
	$(LSREGISTER) -f "$(TARGET)"
	@printf '$(GREEN)  ✓ %s, %s$(RESET)\n' "$(TARGET)" "$(foreach name,$(COMMANDS),$(BIN)/$(name))"

uninstall: ## Quit spale and remove /Applications/spale.app and its command links
	@$(MAKE) --no-print-directory quit
	@for name in $(COMMANDS); do \
		link="$(BIN)/$$name"; \
		if [ "$$(readlink "$$link")" = "$(EXECUTABLE)" ]; then rm "$$link"; fi; \
	done
	@if [ -e "$(TARGET)" ] && /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$(TARGET)/Contents/Info.plist" | grep -qx "$(BUNDLE_ID)"; then \
		rm -rf "$(TARGET)"; \
	fi

quit:
	@if pgrep -x spale >/dev/null; then \
		osascript -e 'tell application id "$(BUNDLE_ID)" to quit'; \
		for attempt in $$(seq 20); do pgrep -x spale >/dev/null || break; sleep 0.25; done; \
		if pgrep -x spale >/dev/null; then echo 'spale is still running. Save and close its documents first.' >&2; exit 1; fi; \
	fi

# ── Maintenance ──────────────────────────────────────────────────────────────

.PHONY: clean

clean: ## Remove .build and .local/dist
	rm -rf .build "$(DIST)"

# ── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "\n$(BOLD)spale$(RESET) — native macOS reader for live Git changes and plain-text editor\n"} \
		/^# ── / {n = $$0; gsub(/(^# ── | (─)+$$)/, "", n); printf "\n$(BOLD)%s$(RESET)\n", n} \
		/^[a-zA-Z_-]+:.*## / {printf "  $(CYAN)make %-14s$(RESET) %s\n", $$1, $$2} \
		END {printf "\n"}' $(MAKEFILE_LIST)
