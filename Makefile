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

BUILD_ARTIFACTS := \
	$(BUILD_DIR)/src/geary \
	$(BUILD_DIR)/src/console/geary-console \
	$(BUILD_DIR)/src/mailer/geary-mailer \
	$(BUILD_DIR)/src/valadoc

.DEFAULT: all

.PHONY: all
all: compile $(BINARIES)

.PHONY: verbose
verbose: compile-verbose $(BINARIES)

.PHONY: compile
compile: $(BUILD_DIR)
	@$(MAKE) -C $(BUILD_DIR)

.PHONY: compile-verbose
compile-verbose: $(BUILD_DIR)
	@$(MAKE) -C $(BUILD_DIR) -v

.PHONY: install
install: compile
	@$(MAKE) -C $(BUILD_DIR) $@

.PHONY: uninstall
uninstall: compile
	@$(MAKE) -C $(BUILD_DIR) $@

.PHONY: geary-pot
geary-pot: compile
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
	@-rm -rf $(BINARIES)
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
dist: test
	@$(MAKE) -C $(BUILD_DIR) $@
	@cp -v $(BUILD_DIR)/meson-dist/*.xz* ..

# The rest of these are actual files

$(BUILD_DIR):
	@$(CONFIGURE) $@

valadoc: $(BUILD_DIR)/src/valadoc
	cp -r $< .

geary: $(BUILD_DIR)/src/geary
	cp $< .

geary-console: $(BUILD_DIR)/src/console/geary-console
	cp $< .

geary-mailer: $(BUILD_DIR)/src/mailer/geary-mailer
	cp $< .

$(BUILD_ARTIFACTS): compile
