PROGRAM = geary
BUILD_ROOT = 1

VALAC := valac

APPS := console syntax lsmbox

ENGINE_SRC := \
	src/engine/Engine.vala \
	src/engine/Interfaces.vala \
	src/engine/Message.vala \
	src/engine/state/Machine.vala \
	src/engine/state/MachineDescriptor.vala \
	src/engine/state/Mapping.vala \
	src/engine/common/MessageData.vala \
	src/engine/imap/ClientConnection.vala \
	src/engine/imap/ClientSession.vala \
	src/engine/imap/Mailbox.vala \
	src/engine/imap/Parameter.vala \
	src/engine/imap/Tag.vala \
	src/engine/imap/Command.vala \
	src/engine/imap/Commands.vala \
	src/engine/imap/FetchCommand.vala \
	src/engine/imap/ResponseCode.vala \
	src/engine/imap/ServerResponse.vala \
	src/engine/imap/StatusResponse.vala \
	src/engine/imap/ServerData.vala \
	src/engine/imap/Status.vala \
	src/engine/imap/CommandResponse.vala \
	src/engine/imap/FetchResults.vala \
	src/engine/imap/FetchDataDecoder.vala \
	src/engine/imap/MessageData.vala \
	src/engine/imap/Serializable.vala \
	src/engine/imap/Serializer.vala \
	src/engine/imap/Deserializer.vala \
	src/engine/imap/Error.vala \
	src/engine/rfc822/MailboxAddress.vala \
	src/engine/rfc822/MessageData.vala \
	src/engine/util/string.vala

CONSOLE_SRC := \
	src/console/main.vala

SYNTAX_SRC := \
	src/tests/syntax.vala

LSMBOX_SRC := \
	src/tests/lsmbox.vala

ALL_SRC := $(ENGINE_SRC) $(CONSOLE_SRC) $(SYNTAX_SRC) $(LSMBOX_SRC)

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

lsmbox: $(ENGINE_SRC) $(LSMBOX_SRC) Makefile
	$(VALAC) --save-temps -g $(foreach pkg,$(EXTERNAL_PKGS),--pkg=$(pkg)) \
		$(ENGINE_SRC) $(LSMBOX_SRC) \
		-o $@

