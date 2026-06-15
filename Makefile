.PHONY: help install get upgrade clean analyze format test \
        dev dev-ios dev-android run run-ios run-android \
        profile profile-ios release release-ios release-beta release-ios-beta \
        build-ios build-ios-ipa build-apk build-appbundle \
        devices doctor pods log status

# -------- Config --------
FLUTTER ?= flutter
DART    ?= dart
DEVICE  ?=
FLAVOR  ?=
MAIN    ?= lib/main.dart
IPHONE_DEVICE_ID := 00008130-0009088A02D8001C
XCODE_BETA_DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer

RUN_ARGS =
ifneq ($(DEVICE),)
  RUN_ARGS += -d $(DEVICE)
endif
ifneq ($(FLAVOR),)
  RUN_ARGS += --flavor $(FLAVOR)
endif

# -------- Help --------
help:
	@echo "Common targets:"
	@echo "  make install          - flutter pub get"
	@echo "  make upgrade          - flutter pub upgrade"
	@echo "  make clean            - flutter clean + pub get"
	@echo "  make analyze          - static analysis"
	@echo "  make format           - dart format ."
	@echo "  make test             - flutter test"
	@echo ""
	@echo "  make dev              - debug run with hot reload (pass DEVICE=xxx to target a device)"
	@echo "  make dev-ios          - debug run on iOS"
	@echo "  make dev-android      - debug run on Android"
	@echo "  make run              - alias for dev"
	@echo "  make profile          - profile mode"
	@echo "  make profile-ios      - profile mode on iOS"
	@echo "  make release          - release mode run"
	@echo "  make release-ios      - release mode run on iOS"
	@echo "  make release-beta     - release mode run using Xcode beta"
	@echo "  make release-ios-beta - release mode run on iOS using Xcode beta"
	@echo ""
	@echo "  make build-ios        - build iOS (no codesign)"
	@echo "  make build-ios-ipa    - build signed .ipa"
	@echo "  make build-apk        - build release APK"
	@echo "  make build-appbundle  - build release AAB"
	@echo ""
	@echo "  make devices          - list connected devices"
	@echo "  make doctor           - flutter doctor -v"
	@echo "  make pods             - reinstall iOS CocoaPods"
	@echo ""
	@echo "  make log              - short git log"
	@echo "  make status           - git status"
	@echo ""
	@echo "Variables: DEVICE=<id>  FLAVOR=<flavor>  MAIN=<path>"

# -------- Dependencies --------
install get:
	$(FLUTTER) pub get

upgrade:
	$(FLUTTER) pub upgrade

clean:
	$(FLUTTER) clean
	$(FLUTTER) pub get

# -------- Quality --------
analyze:
	$(FLUTTER) analyze

format:
	$(DART) format .

test:
	$(FLUTTER) test

# -------- Run --------
dev run:
	$(FLUTTER) run $(RUN_ARGS) -t $(MAIN)

dev-ios run-ios:
	$(FLUTTER) run -d ios $(RUN_ARGS) -t $(MAIN)

dev-android run-android:
	$(FLUTTER) run -d android $(RUN_ARGS) -t $(MAIN)

profile:
	$(FLUTTER) run --profile -d $(IPHONE_DEVICE_ID) -t $(MAIN)

profile-ios:
	$(FLUTTER) run --profile -d ios $(RUN_ARGS) -t $(MAIN)

release:
	$(FLUTTER) run --release -d $(IPHONE_DEVICE_ID) $(RUN_ARGS) -t $(MAIN)

release-ios:
	$(FLUTTER) run --release -d ios $(RUN_ARGS) -t $(MAIN)

release-beta:
	DEVELOPER_DIR=$(XCODE_BETA_DEVELOPER_DIR) $(FLUTTER) run --release -d $(IPHONE_DEVICE_ID) $(RUN_ARGS) -t $(MAIN)

release-ios-beta:
	DEVELOPER_DIR=$(XCODE_BETA_DEVELOPER_DIR) $(FLUTTER) run --release -d ios $(RUN_ARGS) -t $(MAIN)

# -------- Builds --------
build-ios:
	$(FLUTTER) build ios --release --no-codesign -t $(MAIN)

build-ios-ipa:
	$(FLUTTER) build ipa --release -t $(MAIN)

build-apk:
	$(FLUTTER) build apk --release -t $(MAIN)

build-appbundle:
	$(FLUTTER) build appbundle --release -t $(MAIN)

# -------- Tooling --------
devices:
	$(FLUTTER) devices

doctor:
	$(FLUTTER) doctor -v

pods:
	cd ios && rm -rf Pods Podfile.lock && pod install --repo-update

# -------- Git helpers --------
log:
	git log --oneline -20

status:
	git status
