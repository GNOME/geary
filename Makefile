# Only geary is built by default.  Use "make all" to build command-line tools.

PROGRAM = geary
BUILD_ROOT = 1

VALAC := valac
VALAFLAGS := -g --save-temps --enable-checking --fatal-warnings --vapidir=vapi

APPS := geary console syntax lsmbox readmail watchmbox

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
	src/engine/imap/ClientSessionManager.vala \
	src/engine/imap/DataFormat.vala \
	src/engine/imap/Mailbox.vala \
	src/engine/imap/Parameter.vala \
	src/engine/imap/Tag.vala \
	src/engine/imap/Command.vala \
	src/engine/imap/Commands.vala \
	src/engine/imap/ResponseCode.vala \
	src/engine/imap/ResponseCodeType.vala \
	src/engine/imap/ServerResponse.vala \
	src/engine/imap/StatusResponse.vala \
	src/engine/imap/StatusDataType.vala \
	src/engine/imap/ServerData.vala \
	src/engine/imap/ServerDataType.vala \
	src/engine/imap/FetchDataType.vala \
	src/engine/imap/Status.vala \
	src/engine/imap/CommandResponse.vala \
	src/engine/imap/MessageData.vala \
	src/engine/imap/Serializable.vala \
	src/engine/imap/Serializer.vala \
	src/engine/imap/Deserializer.vala \
	src/engine/imap/Error.vala \
	src/engine/imap/Flag.vala \
	src/engine/imap/decoders/CommandResults.vala \
	src/engine/imap/decoders/FetchDataDecoder.vala \
	src/engine/imap/decoders/FetchResults.vala \
	src/engine/imap/decoders/NoopResults.vala \
	src/engine/imap/decoders/ListResults.vala \
	src/engine/imap/decoders/SelectExamineResults.vala \
	src/engine/imap/decoders/StatusResults.vala \
	src/engine/rfc822/MailboxAddress.vala \
	src/engine/rfc822/MessageData.vala \
	src/engine/util/String.vala \
	src/engine/util/Memory.vala \
	src/engine/util/Delegate.vala

CLIENT_SRC := \
	src/client/main.vala \
	src/client/YorbaApplication.vala \
	src/client/GearyApplication.vala \
	src/client/ui/MainWindow.vala \
	src/client/ui/MessageListView.vala \
	src/client/ui/MessageListStore.vala \
	src/client/ui/FolderListView.vala \
	src/client/ui/FolderListStore.vala \
	src/client/util/Intl.vala \
	src/client/util/Date.vala

CONSOLE_SRC := \
	src/console/main.vala

SYNTAX_SRC := \
	src/tests/syntax.vala

LSMBOX_SRC := \
	src/tests/lsmbox.vala

READMAIL_SRC := \
	src/tests/readmail.vala

WATCHMBOX_SRC := \
	src/tests/watchmbox.vala

ALL_SRC := $(ENGINE_SRC) $(CLIENT_SRC) $(CONSOLE_SRC) $(SYNTAX_SRC) $(LSMBOX_SRC) $(READMAIL_SRC) $(WATCHMBOX_SRC)

EXTERNAL_PKGS := \
	gio-2.0 \
	gee-1.0 \
	gtk+-2.0 \
	unique-1.0 \
	posix \
	gmime-2.4

VAPI_FILES := \
	vapi/gmime-2.4.vapi

geary: $(ENGINE_SRC) $(CLIENT_SRC) Makefile $(VAPI_FILES)
	$(VALAC) $(VALAFLAGS) $(foreach pkg,$(EXTERNAL_PKGS),--pkg=$(pkg)) \
		$(ENGINE_SRC) $(CLIENT_SRC) \
		-o $@

.PHONY: all
all: $(APPS)

.PHONY: clean
clean: 
	rm -f $(ALL_SRC:.vala=.c)
	rm -f $(APPS)

console: $(ENGINE_SRC) $(CONSOLE_SRC) Makefile
	$(VALAC) $(VALAFLAGS) $(foreach pkg,$(EXTERNAL_PKGS),--pkg=$(pkg)) \
		$(ENGINE_SRC) $(CONSOLE_SRC) \
		-o $@

syntax: $(ENGINE_SRC) $(SYNTAX_SRC) Makefile
	$(VALAC) $(VALAFLAGS) $(foreach pkg,$(EXTERNAL_PKGS),--pkg=$(pkg)) \
		$(ENGINE_SRC) $(SYNTAX_SRC) \
		-o $@

lsmbox: $(ENGINE_SRC) $(LSMBOX_SRC) Makefile
	$(VALAC) $(VALAFLAGS) $(foreach pkg,$(EXTERNAL_PKGS),--pkg=$(pkg)) \
		$(ENGINE_SRC) $(LSMBOX_SRC) \
		-o $@

readmail: $(ENGINE_SRC) $(READMAIL_SRC) Makefile
	$(VALAC) $(VALAFLAGS) $(foreach pkg,$(EXTERNAL_PKGS),--pkg=$(pkg)) \
		$(ENGINE_SRC) $(READMAIL_SRC) \
		-o $@

watchmbox: $(ENGINE_SRC) $(WATCHMBOX_SRC) Makefile
	$(VALAC) $(VALAFLAGS) $(foreach pkg,$(EXTERNAL_PKGS),--pkg=$(pkg)) \
		$(ENGINE_SRC) $(WATCHMBOX_SRC) \
		-o $@

