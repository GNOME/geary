# Geary engine
engine_vala_sources = files(
  'api/geary.vala',
  'api/geary-abstract-local-folder.vala',
  'api/geary-account.vala',
  'api/geary-account-information.vala',
  'api/geary-aggregated-folder-properties.vala',
  'api/geary-attachment.vala',
  'api/geary-base-object.vala',
  'api/geary-client-service.vala',
  'api/geary-composed-email.vala',
  'api/geary-contact.vala',
  'api/geary-contact-store.vala',
  'api/geary-credentials.vala',
  'api/geary-credentials-mediator.vala',
  'api/geary-email-flags.vala',
  'api/geary-email-header-set.vala',
  'api/geary-email-identifier.vala',
  'api/geary-email-properties.vala',
  'api/geary-email.vala',
  'api/geary-endpoint.vala',
  'api/geary-engine-error.vala',
  'api/geary-engine.vala',
  'api/geary-folder.vala',
  'api/geary-folder-path.vala',
  'api/geary-folder-properties.vala',
  'api/geary-folder-supports-archive.vala',
  'api/geary-folder-supports-copy.vala',
  'api/geary-folder-supports-create.vala',
  'api/geary-folder-supports-empty.vala',
  'api/geary-folder-supports-mark.vala',
  'api/geary-folder-supports-move.vala',
  'api/geary-folder-supports-remove.vala',
  'api/geary-named-flag.vala',
  'api/geary-named-flags.vala',
  'api/geary-problem-report.vala',
  'api/geary-progress-monitor.vala',
  'api/geary-revokable.vala',
  'api/geary-search-query.vala',
  'api/geary-service-information.vala',
  'api/geary-service-provider.vala',

  'app/app-conversation.vala',
  'app/app-conversation-monitor.vala',
  'app/app-draft-manager.vala',
  'app/app-email-store.vala',
  'app/app-search-folder.vala',

  'app/conversation-monitor/app-append-operation.vala',
  'app/conversation-monitor/app-conversation-operation-queue.vala',
  'app/conversation-monitor/app-conversation-operation.vala',
  'app/conversation-monitor/app-conversation-set.vala',
  'app/conversation-monitor/app-external-append-operation.vala',
  'app/conversation-monitor/app-fill-window-operation.vala',
  'app/conversation-monitor/app-insert-operation.vala',
  'app/conversation-monitor/app-load-operation.vala',
  'app/conversation-monitor/app-local-search-operation.vala',
  'app/conversation-monitor/app-remove-operation.vala',
  'app/conversation-monitor/app-reseed-operation.vala',
  'app/conversation-monitor/app-terminate-operation.vala',

  'app/email-store/app-async-folder-operation.vala',
  'app/email-store/app-copy-operation.vala',
  'app/email-store/app-fetch-operation.vala',
  'app/email-store/app-list-operation.vala',
  'app/email-store/app-mark-operation.vala',

  'common/common-contact-harvester.vala',
  'common/common-contact-store-impl.vala',
  'common/common-fts-search-query.vala',
  'common/common-message-data.vala',

  'db/db.vala',
  'db/db-connection.vala',
  'db/db-context.vala',
  'db/db-database.vala',
  'db/db-database-connection.vala',
  'db/db-database-error.vala',
  'db/db-result.vala',
  'db/db-statement.vala',
  'db/db-synchronous-mode.vala',
  'db/db-transaction-async-job.vala',
  'db/db-transaction-connection.vala',
  'db/db-transaction-outcome.vala',
  'db/db-transaction-type.vala',
  'db/db-versioned-database.vala',

  'imap/imap.vala',
  'imap/imap-error.vala',
  'imap/api/imap-account-session.vala',
  'imap/api/imap-capabilities.vala',
  'imap/api/imap-client-service.vala',
  'imap/api/imap-email-flags.vala',
  'imap/api/imap-email-properties.vala',
  'imap/api/imap-folder.vala',
  'imap/api/imap-folder-properties.vala',
  'imap/api/imap-folder-root.vala',
  'imap/api/imap-folder-session.vala',
  'imap/api/imap-quirks.vala',
  'imap/api/imap-session-object.vala',
  'imap/command/imap-append-command.vala',
  'imap/command/imap-authenticate-command.vala',
  'imap/command/imap-capability-command.vala',
  'imap/command/imap-close-command.vala',
  'imap/command/imap-command.vala',
  'imap/command/imap-copy-command.vala',
  'imap/command/imap-create-command.vala',
  'imap/command/imap-delete-command.vala',
  'imap/command/imap-examine-command.vala',
  'imap/command/imap-expunge-command.vala',
  'imap/command/imap-fetch-command.vala',
  'imap/command/imap-id-command.vala',
  'imap/command/imap-idle-command.vala',
  'imap/command/imap-list-command.vala',
  'imap/command/imap-list-return-parameter.vala',
  'imap/command/imap-login-command.vala',
  'imap/command/imap-logout-command.vala',
  'imap/command/imap-message-set.vala',
  'imap/command/imap-namespace-command.vala',
  'imap/command/imap-noop-command.vala',
  'imap/command/imap-search-command.vala',
  'imap/command/imap-search-criteria.vala',
  'imap/command/imap-search-criterion.vala',
  'imap/command/imap-select-command.vala',
  'imap/command/imap-starttls-command.vala',
  'imap/command/imap-status-command.vala',
  'imap/command/imap-store-command.vala',
  'imap/message/imap-data-format.vala',
  'imap/message/imap-envelope.vala',
  'imap/message/imap-fetch-body-data-specifier.vala',
  'imap/message/imap-fetch-data-specifier.vala',
  'imap/message/imap-flag.vala',
  'imap/message/imap-flags.vala',
  'imap/message/imap-internal-date.vala',
  'imap/message/imap-mailbox-specifier.vala',
  'imap/message/imap-message-data.vala',
  'imap/message/imap-message-flag.vala',
  'imap/message/imap-message-flags.vala',
  'imap/message/imap-namespace.vala',
  'imap/message/imap-sequence-number.vala',
  'imap/message/imap-status-data-type.vala',
  'imap/message/imap-tag.vala',
  'imap/message/imap-uid.vala',
  'imap/message/imap-uid-validity.vala',
  'imap/parameter/imap-atom-parameter.vala',
  'imap/parameter/imap-list-parameter.vala',
  'imap/parameter/imap-literal-parameter.vala',
  'imap/parameter/imap-nil-parameter.vala',
  'imap/parameter/imap-number-parameter.vala',
  'imap/parameter/imap-parameter.vala',
  'imap/parameter/imap-quoted-string-parameter.vala',
  'imap/parameter/imap-root-parameters.vala',
  'imap/parameter/imap-string-parameter.vala',
  'imap/parameter/imap-unquoted-string-parameter.vala',
  'imap/response/imap-continuation-response.vala',
  'imap/response/imap-fetch-data-decoder.vala',
  'imap/response/imap-fetched-data.vala',
  'imap/response/imap-mailbox-attribute.vala',
  'imap/response/imap-mailbox-attributes.vala',
  'imap/response/imap-mailbox-information.vala',
  'imap/response/imap-namespace-response.vala',
  'imap/response/imap-response-code.vala',
  'imap/response/imap-response-code-type.vala',
  'imap/response/imap-server-data.vala',
  'imap/response/imap-server-data-type.vala',
  'imap/response/imap-server-response.vala',
  'imap/response/imap-status.vala',
  'imap/response/imap-status-data.vala',
  'imap/response/imap-status-response.vala',
  'imap/transport/imap-client-connection.vala',
  'imap/transport/imap-client-session.vala',
  'imap/transport/imap-deserializer.vala',
  'imap/transport/imap-serializer.vala',

  'imap-db/imap-db-account.vala',
  'imap-db/imap-db-attachment.vala',
  'imap-db/imap-db-database.vala',
  'imap-db/imap-db-email-identifier.vala',
  'imap-db/imap-db-folder.vala',
  'imap-db/imap-db-fts5-matches.c',
  'imap-db/imap-db-fts5-tokeniser.c',
  'imap-db/imap-db-gc.vala',
  'imap-db/imap-db-message-row.vala',
  'imap-db/imap-db-sqlite.c',

  'imap-engine/imap-engine.vala',
  'imap-engine/imap-engine-account-operation.vala',
  'imap-engine/imap-engine-account-processor.vala',
  'imap-engine/imap-engine-account-synchronizer.vala',
  'imap-engine/imap-engine-email-prefetcher.vala',
  'imap-engine/imap-engine-generic-account.vala',
  'imap-engine/imap-engine-generic-folder.vala',
  'imap-engine/imap-engine-minimal-folder.vala',
  'imap-engine/imap-engine-replay-operation.vala',
  'imap-engine/imap-engine-replay-queue.vala',
  'imap-engine/imap-engine-revokable-move.vala',
  'imap-engine/imap-engine-revokable-committed-move.vala',
  'imap-engine/imap-engine-send-replay-operation.vala',
  'imap-engine/gmail/imap-engine-gmail-account.vala',
  'imap-engine/gmail/imap-engine-gmail-all-mail-folder.vala',
  'imap-engine/gmail/imap-engine-gmail-drafts-folder.vala',
  'imap-engine/gmail/imap-engine-gmail-folder.vala',
  'imap-engine/gmail/imap-engine-gmail-spam-trash-folder.vala',
  'imap-engine/other/imap-engine-other-account.vala',
  'imap-engine/other/imap-engine-other-folder.vala',
  'imap-engine/outlook/imap-engine-outlook-account.vala',
  'imap-engine/outlook/imap-engine-outlook-folder.vala',
  'imap-engine/replay-ops/imap-engine-abstract-list-email.vala',
  'imap-engine/replay-ops/imap-engine-copy-email.vala',
  'imap-engine/replay-ops/imap-engine-create-email.vala',
  'imap-engine/replay-ops/imap-engine-empty-folder.vala',
  'imap-engine/replay-ops/imap-engine-fetch-email.vala',
  'imap-engine/replay-ops/imap-engine-list-email-by-id.vala',
  'imap-engine/replay-ops/imap-engine-list-email-by-sparse-id.vala',
  'imap-engine/replay-ops/imap-engine-mark-email.vala',
  'imap-engine/replay-ops/imap-engine-move-email-commit.vala',
  'imap-engine/replay-ops/imap-engine-move-email-prepare.vala',
  'imap-engine/replay-ops/imap-engine-move-email-revoke.vala',
  'imap-engine/replay-ops/imap-engine-remove-email.vala',
  'imap-engine/replay-ops/imap-engine-replay-append.vala',
  'imap-engine/replay-ops/imap-engine-replay-removal.vala',
  'imap-engine/replay-ops/imap-engine-replay-update.vala',
  'imap-engine/replay-ops/imap-engine-server-search-email.vala',
  'imap-engine/replay-ops/imap-engine-user-close.vala',

  'memory/memory-buffer.vala',
  'memory/memory-byte-buffer.vala',
  'memory/memory-empty-buffer.vala',
  'memory/memory-file-buffer.vala',
  'memory/memory-growable-buffer.vala',
  'memory/memory-string-buffer.vala',
  'memory/memory-unowned-byte-array-buffer.vala',
  'memory/memory-unowned-bytes-buffer.vala',
  'memory/memory-unowned-string-buffer.vala',

  'mime/mime-content-disposition.vala',
  'mime/mime-content-parameters.vala',
  'mime/mime-content-type.vala',
  'mime/mime-data-format.vala',
  'mime/mime-disposition-type.vala',
  'mime/mime-error.vala',
  'mime/mime-multipart-subtype.vala',

  'nonblocking/nonblocking-batch.vala',
  'nonblocking/nonblocking-concurrent.vala',
  'nonblocking/nonblocking-counting-semaphore.vala',
  'nonblocking/nonblocking-error.vala',
  'nonblocking/nonblocking-lock.vala',
  'nonblocking/nonblocking-mutex.vala',
  'nonblocking/nonblocking-queue.vala',
  'nonblocking/nonblocking-reporting-semaphore.vala',
  'nonblocking/nonblocking-variants.vala',

  'outbox/outbox-email-identifier.vala',
  'outbox/outbox-email-properties.vala',
  'outbox/outbox-folder.vala',
  'outbox/outbox-folder-properties.vala',

  'rfc822/rfc822.vala',
  'rfc822/rfc822-error.vala',
  'rfc822/rfc822-gmime-filter-flowed.vala',
  'rfc822/rfc822-gmime-filter-blockquotes.vala',
  'rfc822/rfc822-gmime-filter-plain.vala',
  'rfc822/rfc822-mailbox-addresses.vala',
  'rfc822/rfc822-mailbox-address.vala',
  'rfc822/rfc822-message.vala',
  'rfc822/rfc822-message-data.vala',
  'rfc822/rfc822-part.vala',
  'rfc822/rfc822-utils.vala',

  'smtp/smtp-authenticator.vala',
  'smtp/smtp-capabilities.vala',
  'smtp/smtp-client-connection.vala',
  'smtp/smtp-client-service.vala',
  'smtp/smtp-client-session.vala',
  'smtp/smtp-command.vala',
  'smtp/smtp-data-format.vala',
  'smtp/smtp-error.vala',
  'smtp/smtp-greeting.vala',
  'smtp/smtp-login-authenticator.vala',
  'smtp/smtp-oauth2-authenticator.vala',
  'smtp/smtp-plain-authenticator.vala',
  'smtp/smtp-request.vala',
  'smtp/smtp-response.vala',
  'smtp/smtp-response-code.vala',
  'smtp/smtp-response-line.vala',

  'state/state-machine-descriptor.vala',
  'state/state-machine.vala',
  'state/state-mapping.vala',

  'util/util-ascii.vala',
  'util/util-collection.vala',
  'util/util-config-file.vala',
  'util/util-connectivity-manager.vala',
  'util/util-error-context.vala',
  'util/util-files.vala',
  'util/util-generic-capabilities.vala',
  'util/util-html.vala',
  'util/util-idle-manager.vala',
  'util/util-imap-utf7.vala',
  'util/util-inet.vala',
  'util/util-iterable.vala',
  'util/util-logging.vala',
  'util/util-numeric.vala',
  'util/util-object.vala',
  'util/util-reference-semantics.vala',
  'util/util-scheduler.vala',
  'util/util-stream.vala',
  'util/util-string.vala',
  'util/util-synchronization.vala',
  'util/util-timeout-manager.vala',
  'util/util-trillian.vala',
)

engine_sources = [
  engine_vala_sources,
]

engine_dependencies = [
  gee,
  gio,
  glib,
  gmime,
  icu_uc,
  libmath,
  libstemmer,
  libxml,
  posix,
  sqlite
]

if libunwind_dep.found()
  engine_dependencies += libunwind
endif

engine_build_dir = meson.current_build_dir()

engine_c_args = geary_c_args
engine_vala_args = geary_vala_args

# Suppress SQLite loadable module init code
engine_c_args += [
  '-D', 'SQLITE_CORE',
]

# Generate internal VAPI for unit testing. See Meson issue
# https://github.com/mesonbuild/meson/issues/1781 for official
# internal VAPI support.
engine_vala_args += [
  '--internal-header=@0@/geary-engine-internal.h'.format(engine_build_dir),
  '--internal-vapi=@0@/geary-engine-internal.vapi'.format(engine_build_dir)
]

if libunwind_dep.found()
  engine_vala_args += [
    '-D', 'HAVE_LIBUNWIND',
  ]
endif

if libytnef.found()
  engine_dependencies += libytnef
  engine_vala_args += [
    '-D', 'WITH_TNEF_SUPPORT'
  ]
endif

if get_option('delayed_replay_queue')
  engine_vala_args += [
    '-D', 'WITH_DELAYED_REPLAY_QUEUE'
  ]
endif

engine_lib = static_library('geary-engine',
  engine_sources,
  dependencies: engine_dependencies,
  include_directories: config_h_dir,
  vala_args: engine_vala_args,
  c_args: engine_c_args,
)

# Dummy target to tell Meson about the internal VAPI given the
# workaround above, and fix the VAPI header to work around
# GNOME/vala#358
engine_internal_header_fixup = custom_target(
  'engine_internal_header_fixup',
  output: [
    'geary-engine-internal.h',
    'geary-engine-internal.vapi',
  ],
  command: [
    find_program('sed'),
    '-ibak',
    's/geary-engine.h/geary-engine-internal.h/g',
    '@OUTDIR@/geary-engine-internal.vapi',
  ],
  depends: engine_lib
)

engine_dep = declare_dependency(
  link_with: [
    engine_lib,
  ],
  include_directories: include_directories('.')
)

engine_internal_dep = declare_dependency(
  # Can't just include engine_lib in link_with since that will
  # pull in the public header and we get duplicate symbol errors.
  link_args: [
    '-L' + engine_build_dir,
    '-lgeary-engine'
  ],
  include_directories: include_directories('.'),
  sources: engine_internal_header_fixup
)

# Compile a loadable library containing the custom tokeniser so SQLite
# command line app can still be used.
tokeniser_lib = shared_library('geary-tokeniser',
  files('imap-db/imap-db-fts5-tokeniser.c'),
  dependencies: [ glib, icu_uc, sqlite ],
  c_args: [
    # Enable GLib structured logging
    '-DG_LOG_USE_STRUCTURED',
  ],
)
