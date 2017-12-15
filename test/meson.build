geary_test_engine_sources = [
  'test-engine.vala',
  'testcase.vala',

  'engine/api/geary-attachment-test.vala',
  'engine/api/geary-engine-test.vala',
  'engine/api/geary-email-identifier-test.vala',
  'engine/api/geary-folder-test.vala',
  'engine/api/geary-folder-path-test.vala',
  'engine/app/app-conversation-test.vala',
  'engine/app/app-conversation-set-test.vala',
  'engine/imap/command/imap-create-command-test.vala',
  'engine/imap/response/imap-namespace-response-test.vala',
  'engine/imap/transport/imap-deserializer-test.vala',
  'engine/mime-content-type-test.vala',
  'engine/rfc822-mailbox-address-test.vala',
  'engine/rfc822-message-test.vala',
  'engine/rfc822-message-data-test.vala',
  'engine/rfc822-utils-test.vala',
  'engine/util-html-test.vala',
  'engine/util-idle-manager-test.vala',
  'engine/util-inet-test.vala',
  'engine/util-js-test.vala',
  'engine/util-timeout-manager-test.vala'
]

geary_test_client_sources = [
  'test-client.vala',
  'testcase.vala',

  'client/application/geary-configuration-test.vala',
  'client/components/client-web-view-test.vala',
  'client/components/client-web-view-test-case.vala',
  'client/composer/composer-web-view-test.vala',

  'js/client-page-state-test.vala',
  'js/composer-page-state-test.vala',
  'js/conversation-page-state-test.vala',

  geary_compiled_schema,
  geary_resources
]

geary_test_engine_dependencies = [
  geary_engine_internal_dep,
  gee,
  gio,
  glib,
  gmime,
  javascriptcoregtk,
  libunwind,
  libxml,
  sqlite,
]

geary_test_client_dependencies = [
  geary_client_dep,
  geary_engine_dep,
  gee,
  gmime,
  gtk,
  libsoup,
  webkit2gtk,
]

geary_test_engine_bin = executable('geary-test-engine',
  geary_test_engine_sources,
  dependencies: geary_test_engine_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_vala_options,
  c_args: geary_c_options,
)

geary_test_client_bin = executable('geary-test-client',
  geary_test_client_sources,
  dependencies: geary_test_client_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_vala_options,
  c_args: geary_c_options,
)

test('engine-tests', geary_test_engine_bin)
test('client-tests', geary_test_client_bin)
