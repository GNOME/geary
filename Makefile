PROGRAM = geary
BUILD_ROOT = 1

VALAC := valac

APPS := console syntax

ENGINE_SRC := \
	src/engine/state/Machine.vala \
	src/engine/state/MachineDescriptor.vala \
	src/engine/state/Mapping.vala \
	src/engine/imap/ClientConnection.vala \
	src/engine/imap/ClientSession.vala \
	src/engine/imap/Parameter.vala \
	src/engine/imap/Tag.vala \
	src/engine/imap/Command.vala \
	src/engine/imap/Commands.vala \
	src/engine/imap/Serializable.vala \
	src/engine/imap/Serializer.vala \
	src/engine/imap/Deserializer.vala \
	src/engine/imap/Error.vala \
	src/engine/util/string.vala

CONSOLE_SRC := \
	src/console/main.vala

SYNTAX_SRC := \
	src/tests/syntax.vala

ALL_SRC := $(ENGINE_SRC) $(CONSOLE_SRC) $(SYNTAX_SRC)

EXTERNAL_PKGS := \
	gio-2.0 \
	gee-1.0 \
	gtk+-2.0

.PHONY: all
all: $(APPS)

.PHONY: clean
clean: 
	rm -f $(ALL_SRC:.vala=.c)
	rm -f $(APPS)

console: $(ENGINE_SRC) $(CONSOLE_SRC) Makefile
	$(VALAC) --save-temps -g $(foreach pkg,$(EXTERNAL_PKGS),--pkg=$(pkg)) \
		$(ENGINE_SRC) $(CONSOLE_SRC) \
		-o $@

syntax: $(ENGINE_SRC) $(SYNTAX_SRC) Makefile
	$(VALAC) --save-temps -g $(foreach pkg,$(EXTERNAL_PKGS),--pkg=$(pkg)) \
		$(ENGINE_SRC) $(SYNTAX_SRC) \
		-o $@

