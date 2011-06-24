# Only geary is built by default.  Use "make all" to build command-line tools.

PROGRAM = geary
BUILD_ROOT = 1

VALAC := valac
VALAFLAGS := -g --enable-checking --fatal-warnings --vapidir=vapi

APPS := geary console watchmbox

ENGINE_SRC := \
	src/engine/Engine.vala \
	src/engine/ImapEngine.vala \
	src/engine/EngineFolder.vala \
	src/engine/api/Account.vala \
	src/engine/api/Email.vala \
	src/engine/api/EmailProperties.vala \
	src/engine/api/EmailLocation.vala \
	src/engine/api/Folder.vala \
	src/engine/api/FolderProperties.vala \
	src/engine/api/Credentials.vala \
	src/engine/api/EngineError.vala \
	src/engine/api/RemoteInterfaces.vala \
	src/engine/api/LocalInterfaces.vala \
	src/engine/sqlite/Database.vala \
	src/engine/sqlite/Table.vala \
	src/engine/sqlite/Row.vala \
	src/engine/sqlite/MailDatabase.vala \
	src/engine/sqlite/FolderTable.vala \
	src/engine/sqlite/FolderRow.vala \
	src/engine/sqlite/MessageRow.vala \
	src/engine/sqlite/MessageTable.vala \
	src/engine/sqlite/MessageLocationRow.vala \
	src/engine/sqlite/MessageLocationTable.vala \
	src/engine/sqlite/ImapMessageLocationPropertiesTable.vala \
	src/engine/sqlite/ImapMessageLocationPropertiesRow.vala \
	src/engine/sqlite/api/Account.vala \
	src/engine/sqlite/api/Folder.vala \
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
	src/engine/imap/MessageSet.vala \
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
	src/engine/imap/api/Account.vala \
	src/engine/imap/api/EmailLocation.vala \
	src/engine/imap/api/EmailProperties.vala \
	src/engine/imap/api/Folder.vala \
	src/engine/imap/api/FolderProperties.vala \
	src/engine/rfc822/MailboxAddress.vala \
	src/engine/rfc822/MailboxAddresses.vala \
	src/engine/rfc822/MessageData.vala \
	src/engine/util/Memory.vala \
	src/engine/util/ReferenceSemantics.vala \
	src/engine/util/Trillian.vala

COMMON_SRC := \
	src/common/String.vala \
	src/common/Interfaces.vala \
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

