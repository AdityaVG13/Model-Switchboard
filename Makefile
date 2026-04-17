VERSION := $(shell tr -d '[:space:]' < VERSION)

.PHONY: test xcode app install uninstall dmg release

test:
	swift test

xcode:
	./Scripts/build-xcode-app.sh

app:
	./Scripts/build-app.sh

install:
	./Scripts/install.sh

uninstall:
	./Scripts/uninstall.sh

dmg:
	./Scripts/build-dmg.sh

release: dmg
	@printf 'release=%s\n' "dist/Model-Switchboard-$(VERSION).dmg"
