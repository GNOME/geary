# Geary build script
# Copyright 2011-2012 Yorba Foundation

set(COMMON_SRC
common/common-arrays.vala
common/common-async.vala
common/common-date.vala
common/common-files.vala
common/common-international.vala
common/common-yorba-application.vala
)

set(ENGINE_SRC
engine/api/geary-account.vala
engine/api/geary-account-information.vala
engine/api/geary-attachment.vala
engine/api/geary-batch-operations.vala
engine/api/geary-composed-email.vala
engine/api/geary-conversation.vala
engine/api/geary-conversation-monitor.vala
engine/api/geary-credentials.vala
engine/api/geary-email-flag.vala
engine/api/geary-email-flags.vala
engine/api/geary-email-identifier.vala
engine/api/geary-email-properties.vala
engine/api/geary-email.vala
engine/api/geary-endpoint.vala
engine/api/geary-engine-account.vala
engine/api/geary-engine-error.vala
engine/api/geary-engine.vala
engine/api/geary-folder.vala
engine/api/geary-folder-path.vala
engine/api/geary-folder-supports-archive.vala
engine/api/geary-folder-supports-copy.vala
engine/api/geary-folder-supports-create.vala
engine/api/geary-folder-supports-mark.vala
engine/api/geary-folder-supports-move.vala
engine/api/geary-folder-supports-remove.vala
engine/api/geary-logging.vala
engine/api/geary-service-provider.vala
engine/api/geary-special-folder.vala

engine/common/common-message-data.vala

engine/imap/api/imap-account.vala
engine/imap/api/imap-email-flags.vala
engine/imap/api/imap-email-identifier.vala
engine/imap/api/imap-email-properties.vala
engine/imap/api/imap-folder-properties.vala
engine/imap/api/imap-folder.vala
engine/imap/command/imap-command-response.vala
engine/imap/command/imap-commands.vala
engine/imap/command/imap-command.vala
engine/imap/command/imap-fetch-command.vala
engine/imap/decoders/imap-capabilities.vala
engine/imap/decoders/imap-capability-results.vala
engine/imap/decoders/imap-command-results.vala
engine/imap/decoders/imap-fetch-data-decoder.vala
engine/imap/decoders/imap-fetch-results.vala
engine/imap/decoders/imap-list-results.vala
engine/imap/decoders/imap-select-examine-results.vala
engine/imap/decoders/imap-status-results.vala
engine/imap/imap-error.vala
engine/imap/message/imap-data-format.vala
engine/imap/message/imap-fetch-data-type.vala
engine/imap/message/imap-fetch-body-data-type.vala
engine/imap/message/imap-flag.vala
engine/imap/message/imap-message-data.vala
engine/imap/message/imap-message-set.vala
engine/imap/message/imap-parameter.vala
engine/imap/message/imap-tag.vala
engine/imap/response/imap-continuation-response.vala
engine/imap/response/imap-response-code-type.vala
engine/imap/response/imap-response-code.vala
engine/imap/response/imap-server-data-type.vala
engine/imap/response/imap-server-data.vala
engine/imap/response/imap-server-response.vala
engine/imap/response/imap-status-data-type.vala
engine/imap/response/imap-status-response.vala
engine/imap/response/imap-status.vala
engine/imap/response/imap-unsolicited-server-data.vala
engine/imap/transport/imap-client-connection.vala
engine/imap/transport/imap-client-session-manager.vala
engine/imap/transport/imap-client-session.vala
engine/imap/transport/imap-deserializer.vala
engine/imap/transport/imap-mailbox.vala
engine/imap/transport/imap-serializable.vala
engine/imap/transport/imap-serializer.vala

engine/impl/geary-abstract-account.vala
engine/impl/geary-abstract-folder.vala
engine/impl/geary-email-flag-watcher.vala
engine/impl/geary-email-prefetcher.vala
engine/impl/geary-generic-capabilities.vala
engine/impl/geary-generic-imap-account.vala
engine/impl/geary-generic-imap-folder.vala
engine/impl/geary-gmail-account.vala
engine/impl/geary-gmail-folder.vala
engine/impl/geary-other-account.vala
engine/impl/geary-other-folder.vala
engine/impl/geary-receive-replay-operations.vala
engine/impl/geary-replay-operation.vala
engine/impl/geary-replay-queue.vala
engine/impl/geary-send-replay-operations.vala
engine/impl/geary-yahoo-account.vala
engine/impl/geary-yahoo-folder.vala
engine/impl/outbox/smtp-outbox-folder.vala
engine/impl/outbox/smtp-outbox-email-identifier.vala
engine/impl/outbox/smtp-outbox-email-properties.vala

engine/nonblocking/nonblocking-abstract-semaphore.vala
engine/nonblocking/nonblocking-batch.vala
engine/nonblocking/nonblocking-mailbox.vala
engine/nonblocking/nonblocking-mutex.vala
engine/nonblocking/nonblocking-variants.vala

engine/rfc822/rfc822-error.vala
engine/rfc822/rfc822-gmime-filter-flowed.vala
engine/rfc822/rfc822-mailbox-addresses.vala
engine/rfc822/rfc822-mailbox-address.vala
engine/rfc822/rfc822-message.vala
engine/rfc822/rfc822-message-data.vala
engine/rfc822/rfc822-utils.vala

engine/smtp/smtp-abstract-authenticator.vala
engine/smtp/smtp-authenticator.vala
engine/smtp/smtp-capabilities.vala
engine/smtp/smtp-client-connection.vala
engine/smtp/smtp-client-session.vala
engine/smtp/smtp-command.vala
engine/smtp/smtp-data-format.vala
engine/smtp/smtp-error.vala
engine/smtp/smtp-greeting.vala
engine/smtp/smtp-login-authenticator.vala
engine/smtp/smtp-plain-authenticator.vala
engine/smtp/smtp-request.vala
engine/smtp/smtp-response.vala
engine/smtp/smtp-response-code.vala
engine/smtp/smtp-response-line.vala

engine/sqlite/abstract/sqlite-database.vala
engine/sqlite/abstract/sqlite-row.vala
engine/sqlite/abstract/sqlite-table.vala
engine/sqlite/abstract/sqlite-transaction.vala
engine/sqlite/api/sqlite-account.vala
engine/sqlite/api/sqlite-folder.vala
engine/sqlite/email/sqlite-folder-row.vala
engine/sqlite/email/sqlite-folder-table.vala
engine/sqlite/email/sqlite-mail-database.vala
engine/sqlite/email/sqlite-message-attachment-row.vala
engine/sqlite/email/sqlite-message-attachment-table.vala
engine/sqlite/email/sqlite-message-location-row.vala
engine/sqlite/email/sqlite-message-location-table.vala
engine/sqlite/email/sqlite-message-row.vala
engine/sqlite/email/sqlite-message-table.vala
engine/sqlite/imap/sqlite-imap-database.vala
engine/sqlite/imap/sqlite-imap-folder-properties-row.vala
engine/sqlite/imap/sqlite-imap-folder-properties-table.vala
engine/sqlite/imap/sqlite-imap-message-properties-row.vala
engine/sqlite/imap/sqlite-imap-message-properties-table.vala
engine/sqlite/smtp/sqlite-smtp-outbox-row.vala
engine/sqlite/smtp/sqlite-smtp-outbox-table.vala

engine/state/state-machine-descriptor.vala
engine/state/state-machine.vala
engine/state/state-mapping.vala

engine/util/util-collection.vala
engine/util/util-converter.vala
engine/util/util-html.vala
engine/util/util-inet.vala
engine/util/util-interfaces.vala
engine/util/util-memory.vala
engine/util/util-numeric.vala
engine/util/util-reference-semantics.vala
engine/util/util-scheduler.vala
engine/util/util-singleton.vala
engine/util/util-stream.vala
engine/util/util-string.vala
engine/util/util-timer-pool.vala
engine/util/util-trillian.vala
)

set(CLIENT_SRC
client/geary-application.vala
client/geary-config.vala
client/geary-controller.vala
client/main.vala

client/ui/composer-window.vala
client/ui/geary-login.vala
client/ui/email-entry.vala
client/ui/icon-factory.vala
client/ui/folder-list.vala
client/ui/folder-menu.vala
client/ui/main-toolbar.vala
client/ui/main-window.vala
client/ui/message-list-cell-renderer.vala
client/ui/message-list-store.vala
client/ui/message-list-view.vala
client/ui/message-viewer.vala
client/ui/password-dialog.vala
client/ui/preferences-dialog.vala
client/ui/webview-edit-fixer.vala
client/ui/notification-bubble.vala

client/ui/sidebar/sidebar-branch.vala
client/ui/sidebar/sidebar-common.vala
client/ui/sidebar/sidebar-entry.vala
client/ui/sidebar/sidebar-tree.vala

client/util/util-email.vala
client/util/util-gravatar.vala
client/util/util-keyring.vala
client/util/util-menu.vala
client/util/util-webkit.vala
)

set(CONSOLE_SRC
console/main.vala
)

set(MAILER_SRC
mailer/main.vala
)

set(DBUSSERVICE_SRC
dbusservice/controller.vala
dbusservice/database.vala
dbusservice/dbus-conversation.vala
dbusservice/dbus-conversations.vala
dbusservice/dbus-email.vala
dbusservice/main.vala
)

# Vala
find_package(Vala REQUIRED)
include(ValaVersion)
ensure_vala_version("0.17.2" MINIMUM)
include(ValaPrecompile)

# Packages
find_package(PkgConfig)
pkg_check_modules(DEPS REQUIRED
    gthread-2.0
    glib-2.0>=2.30.0
    gio-2.0>=2.28.0
    gtk+-3.0>=3.2.0
    gee-1.0>=0.6.0
    unique-3.0>=3.0.0
    libnotify>=0.7.5
    libcanberra>=0.28
    sqlite3>=3.7.4
    sqlheavy-0.1>=0.1.1
    gmime-2.6>=2.6.0
    gnome-keyring-1>=2.32.0
    webkitgtk-3.0>=1.4.3
)

set(ENGINE_PACKAGES
    glib-2.0 gee-1.0 gio-2.0 sqlheavy-0.1 gmime-2.6 unique-3.0 posix
)

set(CLIENT_PACKAGES
    gtk+-3.0 gnome-keyring-1 webkitgtk-3.0 libnotify libcanberra
)

set(CONSOLE_PACKAGES
    gtk+-3.0
)

set(DBUSSERVICE_PACKAGES
    gee-1.0 glib-2.0
)

set(GSETTINGS_DIR ${CMAKE_SOURCE_DIR}/src/client)

set(CFLAGS 
    ${DEPS_CFLAGS}
    ${DEPS_CFLAGS_OTHER}
    -D_VERSION=\"${VERSION}\"
    -D_INSTALL_PREFIX=\"${CMAKE_INSTALL_PREFIX}\"
    -D_SOURCE_ROOT_DIR=\"${CMAKE_SOURCE_DIR}\"
    -D_GSETTINGS_DIR=\"${CMAKE_BINARY_DIR}/gsettings\"
    -DGETTEXT_PACKAGE=\"${GETTEXT_PACKAGE}\"
    -DLANGUAGE_SUPPORT_DIRECTORY=\"${LANGUAGE_SUPPORT_DIRECTORY}\"
    -g
)

set(LIB_PATHS ${DEPS_LIBRARY_DIRS})
link_directories(${LIB_PATHS})
add_definitions(${CFLAGS})

# Engine (static library used for building)
#################################################
vala_precompile(ENGINE_VALA_C
    ${ENGINE_SRC}
    ${COMMON_SRC}
PACKAGES
    ${CONSOLE_PACKAGES}
    ${ENGINE_PACKAGES}
GENERATE_VAPI
    geary-static
OPTIONS
    --vapidir=${CMAKE_SOURCE_DIR}/vapi
    --thread
    --enable-checking
    --debug
    --fatal-warnings
)

add_library(geary-static STATIC ${ENGINE_VALA_C})
target_link_libraries(geary-static ${DEPS_LIBRARIES} gthread-2.0)

# Geary client app
#################################################
vala_precompile(GEARY_VALA_C
    ${CLIENT_SRC}
PACKAGES
    ${CLIENT_PACKAGES}
    ${ENGINE_PACKAGES}
    geary-static
OPTIONS
    --vapidir=${CMAKE_SOURCE_DIR}/vapi
    --vapidir=${CMAKE_BINARY_DIR}/src
    --thread
    --enable-checking
    --debug
    --fatal-warnings
)

add_executable(geary ${GEARY_VALA_C})
target_link_libraries(geary ${DEPS_LIBRARIES} gthread-2.0 geary-static)
install(TARGETS geary RUNTIME DESTINATION bin)
add_custom_command(
    TARGET
        geary
    POST_BUILD
    COMMAND 
        ${CMAKE_COMMAND} -E copy geary ${CMAKE_BINARY_DIR}/
)

# GSettings
include(GSettings)
add_schemas(geary ${GSETTINGS_DIR})

# Console app
#################################################
vala_precompile(CONSOLE_VALA_C
    ${CONSOLE_SRC}
PACKAGES
    ${CONSOLE_PACKAGES}
    ${ENGINE_PACKAGES}
    geary-static
OPTIONS
    --vapidir=${CMAKE_SOURCE_DIR}/vapi
    --vapidir=${CMAKE_BINARY_DIR}/src
    --thread
    --enable-checking
    --debug
    --fatal-warnings
)

add_executable(geary-console ${CONSOLE_VALA_C})
target_link_libraries(geary-console ${DEPS_LIBRARIES} gthread-2.0 geary-static)
add_custom_command(
    TARGET
        geary-console
    POST_BUILD
    COMMAND 
        ${CMAKE_COMMAND} -E copy geary-console ${CMAKE_BINARY_DIR}/
)

# Mailer app
#################################################
vala_precompile(MAILER_VALA_C
    ${MAILER_SRC}
PACKAGES
    ${ENGINE_PACKAGES}
    geary-static
OPTIONS
    --vapidir=${CMAKE_SOURCE_DIR}/vapi
    --vapidir=${CMAKE_BINARY_DIR}/src
    --thread
    --enable-checking
    --debug
    --fatal-warnings
)

add_executable(geary-mailer ${MAILER_VALA_C})
target_link_libraries(geary-mailer ${DEPS_LIBRARIES} gthread-2.0 geary-static)
add_custom_command(
    TARGET
        geary-mailer
    POST_BUILD
    COMMAND 
        ${CMAKE_COMMAND} -E copy geary-mailer ${CMAKE_BINARY_DIR}/
)

# DBus Service
#################################################
vala_precompile(DBUS_VALA_C
    ${DBUSSERVICE_SRC}
PACKAGES
    ${DBUSSERVICE_PACKAGES}
    ${ENGINE_PACKAGES}
    geary-static
OPTIONS
    --vapidir=${CMAKE_SOURCE_DIR}/vapi
    --vapidir=${CMAKE_BINARY_DIR}/src
    --thread
    --enable-checking
    --debug
    --fatal-warnings
)

add_executable(gearyd ${DBUS_VALA_C})
target_link_libraries(gearyd ${DEPS_LIBRARIES} gthread-2.0 geary-static)
add_custom_command(
    TARGET
        gearyd
    POST_BUILD
    COMMAND 
        ${CMAKE_COMMAND} -E copy gearyd ${CMAKE_BINARY_DIR}/
)

## Make clean: remove copied files
##################################################
set_property(
    DIRECTORY ..
    APPEND
    PROPERTY ADDITIONAL_MAKE_CLEAN_FILES
        geary
        geary-console
        geary-mailer
        gearyd
)

