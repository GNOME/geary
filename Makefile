# Only geary is built by default.  Use "make all" to build command-line tools.

PROGRAM = geary
BUILD_ROOT = 1

VALAC := valac
VALAFLAGS := -g --enable-checking --fatal-warnings --vapidir=vapi

APPS := geary console watchmbox

ENGINE_SRC := \
	src/engine/api/geary-account.vala \
	src/engine/api/geary-credentials.vala \
	src/engine/api/geary-email-location.vala \
	src/engine/api/geary-email-properties.vala \
	src/engine/api/geary-email.vala \
	src/engine/api/geary-engine-error.vala \
	src/engine/api/geary-engine-folder.vala \
	src/engine/api/geary-engine.vala \
	src/engine/api/geary-folder-properties.vala \
	src/engine/api/geary-folder.vala \
	src/engine/api/geary-imap-engine.vala \
	src/engine/api/geary-local-interfaces.vala \
	src/engine/api/geary-remote-interfaces.vala \
	\
	src/engine/common/common-interfaces.vala \
	src/engine/common/common-message-data.vala \
	src/engine/common/common-string.vala \
	\
	src/engine/imap/api/imap-account.vala \
	src/engine/imap/api/imap-email-location.vala \
	src/engine/imap/api/imap-email-properties.vala \
	src/engine/imap/api/imap-folder-properties.vala \
	src/engine/imap/api/imap-folder.vala \
	src/engine/imap/command/imap-command-response.vala \
	src/engine/imap/command/imap-commands.vala \
	src/engine/imap/command/imap-command.vala \
	src/engine/imap/decoders/imap-command-results.vala \
	src/engine/imap/decoders/imap-fetch-data-decoder.vala \
	src/engine/imap/decoders/imap-fetch-results.vala \
	src/engine/imap/decoders/imap-list-results.vala \
	src/engine/imap/decoders/imap-noop-results.vala \
	src/engine/imap/decoders/imap-select-examine-results.vala \
	src/engine/imap/decoders/imap-status-results.vala \
	src/engine/imap/imap-error.vala \
	src/engine/imap/message/imap-data-format.vala \
	src/engine/imap/message/imap-fetch-data-type.vala \
	src/engine/imap/message/imap-flag.vala \
	src/engine/imap/message/imap-message-data.vala \
	src/engine/imap/message/imap-message-set.vala \
	src/engine/imap/message/imap-parameter.vala \
	src/engine/imap/message/imap-tag.vala \
	src/engine/imap/response/imap-response-code-type.vala \
	src/engine/imap/response/imap-response-code.vala \
	src/engine/imap/response/imap-server-data-type.vala \
	src/engine/imap/response/imap-server-data.vala \
	src/engine/imap/response/imap-server-response.vala \
	src/engine/imap/response/imap-status-data-type.vala \
	src/engine/imap/response/imap-status-response.vala \
	src/engine/imap/response/imap-status.vala \
	src/engine/imap/transport/imap-client-connection.vala \
	src/engine/imap/transport/imap-client-session-manager.vala \
	src/engine/imap/transport/imap-client-session.vala \
	src/engine/imap/transport/imap-deserializer.vala \
	src/engine/imap/transport/imap-mailbox.vala \
	src/engine/imap/transport/imap-serializable.vala \
	src/engine/imap/transport/imap-serializer.vala \
	\
	src/engine/rfc822/rfc822-mailbox-addresses.vala \
	src/engine/rfc822/rfc822-mailbox-address.vala \
	src/engine/rfc822/rfc822-message-data.vala \
	\
	src/engine/sqlite/abstract/sqlite-database.vala \
	src/engine/sqlite/abstract/sqlite-row.vala \
	src/engine/sqlite/abstract/sqlite-table.vala \
	src/engine/sqlite/api/sqlite-account.vala \
	src/engine/sqlite/api/sqlite-folder.vala \
	src/engine/sqlite/email/sqlite-folder-row.vala \
	src/engine/sqlite/email/sqlite-folder-table.vala \
	src/engine/sqlite/email/sqlite-mail-database.vala \
	src/engine/sqlite/email/sqlite-message-location-row.vala \
	src/engine/sqlite/email/sqlite-message-location-table.vala \
	src/engine/sqlite/email/sqlite-message-row.vala \
	src/engine/sqlite/email/sqlite-message-table.vala \
	src/engine/sqlite/imap/sqlite-imap-message-location-properties-row.vala \
	src/engine/sqlite/imap/sqlite-imap-message-location-properties-table.vala \
	\
	src/engine/state/state-machine-descriptor.vala \
	src/engine/state/state-machine.vala \
	src/engine/state/state-mapping.vala \
	\
	src/engine/util/util-memory.vala \
	src/engine/util/util-reference-semantics.vala \
	src/engine/util/util-trillian.vala

COMMON_SRC := \
	src/common/YorbaApplication.vala \
	src/common/Date.vala

CLIENT_SRC := \
	src/client/main.vala \
	src/client/GearyApplication.vala \
	src/client/ui/MainWindow.vala \
	src/client/ui/MessageListView.vala \
	src/client/ui/MessageListStore.vala \
	src/client/ui/FolderListView.vala \
	src/client/ui/FolderListStore.vala \
	src/client/ui/MessageViewer.vala \
	src/client/ui/MessageBuffer.vala \
	src/client/util/Intl.vala

CONSOLE_SRC := \
	src/console/main.vala

WATCHMBOX_SRC := \
	src/tests/watchmbox.vala

ALL_SRC := $(ENGINE_SRC) $(COMMON_SRC) $(CLIENT_SRC) $(CONSOLE_SRC) $(WATCHMBOX_SRC)

EXTERNAL_PKGS := \
	gio-2.0 >= 2.28.0 \
	gee-1.0 >= 0.6.1 \
	gtk+-2.0 >= 2.22.0 \
	unique-1.0 >= 1.0.0 \
	gmime-2.4 >= 2.4.14 \
	sqlheavy-0.1 >= 0.0.1

EXTERNAL_BINDINGS := \
	gio-2.0 \
	gee-1.0 \
	gtk+-2.0 \
	unique-1.0 \
	posix \
	gmime-2.4 \
	sqlheavy-0.1

VAPI_FILES := \
	vapi/gmime-2.4.vapi

geary: $(ENGINE_SRC) $(COMMON_SRC) $(CLIENT_SRC) Makefile $(VAPI_FILES)
	pkg-config --exists --print-errors '$(EXTERNAL_PKGS)'
	$(VALAC) $(VALAFLAGS) $(foreach binding,$(EXTERNAL_BINDINGS),--pkg=$(binding)) \
		$(ENGINE_SRC) $(COMMON_SRC) $(CLIENT_SRC) \
		-o $@

.PHONY: all
all: $(APPS)

.PHONY: clean
clean: 
	rm -f $(ALL_SRC:.vala=.c)
	rm -f $(ALL_SRC:.vala=.vala.c)
	rm -f $(APPS)

console: $(ENGINE_SRC) $(COMMON_SRC) $(CONSOLE_SRC) Makefile
	$(VALAC) $(VALAFLAGS) $(foreach binding,$(EXTERNAL_BINDINGS),--pkg=$(binding)) \
		$(ENGINE_SRC) $(COMMON_SRC) $(CONSOLE_SRC) \
		-o $@

watchmbox: $(ENGINE_SRC) $(COMMON_SRC) $(WATCHMBOX_SRC) Makefile
	$(VALAC) $(VALAFLAGS) $(foreach binding,$(EXTERNAL_BINDINGS),--pkg=$(binding)) \
		$(ENGINE_SRC) $(COMMON_SRC) $(WATCHMBOX_SRC) \
		-o $@

