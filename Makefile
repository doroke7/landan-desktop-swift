APP_NAME := USBCamera
APP      := build/$(APP_NAME).app
BIN_DIR   = $(shell swift build -c release --show-bin-path)

.PHONY: all build app run dev dmg clean help

all: app

help:
	@echo "make build  - 編譯 (release)"
	@echo "make app    - 編譯並打包 $(APP)"
	@echo "make run    - 打包並啟動 app"
	@echo "make dev    - 直接用 swift run（除錯用，無攝影機權限提示）"
	@echo "make dmg    - 打包成 build/$(APP_NAME).dmg 方便發佈"
	@echo "make clean  - 清除 .build 與 build"

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp "$(BIN_DIR)/$(APP_NAME)" $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - --entitlements Resources/App.entitlements $(APP)
	@echo "完成: $(APP)"

run: app
	open $(APP)

dev:
	swift run

dmg: app
	rm -f build/$(APP_NAME).dmg
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(APP) -ov -format UDZO build/$(APP_NAME).dmg
	@echo "完成: build/$(APP_NAME).dmg"

clean:
	rm -rf .build build
