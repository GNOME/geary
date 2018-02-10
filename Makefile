#
# Copyright 2016 Software Freedom Conservancy Inc.
#

# This Makefile is for developer convenience, and is optimised for
# development work, not production. Packagers should invoke meson and
# ninja directly. See INSTALL for further information.

CONFIGURE := meson \
	--buildtype debug \
	--warnlevel 3
MAKE := ninja

BUILD_DIR := build
BINARIES := geary geary-console geary-mailer

BUILD_BINARIES := \
	$(BUILD_DIR)/src/geary \
	$(BUILD_DIR)/src/console/geary-console \
	$(BUILD_DIR)/src/mailer/geary-mailer

.DEFAULT: all

.PHONY: all
all: $(BUILD_DIR)
	@$(MAKE) -C $(BUILD_DIR)
	@cp $(BUILD_BINARIES) .

$(BUILD_DIR):
	@$(CONFIGURE) $@

.PHONY: install
install: $(BUILD_DIR)
	@$(MAKE) -C $(BUILD_DIR) $@

.PHONY: uninstall
uninstall: $(BUILD_DIR)
	@$(MAKE) -C $(BUILD_DIR) $@

.PHONY: geary-pot
geary-pot: $(BUILD_DIR)
	@$(MAKE) -C $(BUILD_DIR) $@

# Keep the olde rule For compatibility
.PHONY: pot_file
pot_file: geary-pot

.PHONY: clean
clean: $(BUILD_DIR)
	@-$(MAKE) -C $(BUILD_DIR) $@

.PHONY: distclean
distclean:
	@-rm -rf $(BUILD_DIR)
	@-rm -rf $(BUILD_BINARIES)
	@-rm -rf valadoc
	@-rm -f po/geary.pot

.PHONY: test
test: $(BUILD_DIR)
	@$(MAKE) -C $(BUILD_DIR) $@

.PHONY: test-engine
test-engine: $(BUILD_DIR)
	cd $(BUILD_DIR) && meson test engine-tests

.PHONY: test-client
test-client: $(BUILD_DIR)
	cd $(BUILD_DIR) && meson test client-tests

.PHONY: dist
dist: tests
	@$(MAKE) -C $(BUILD_DIR) $@
	@cp -v $(BUILD_DIR)/meson-dist/*.xz* ..

.PHONY: valadoc
valadoc: all
	cp -r $(BUILD_DIR)/src/valadoc .
