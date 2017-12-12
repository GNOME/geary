geary_test_sources = [
  'main.vala',
  'testcase.vala', # Based on same file in libgee, courtesy Julien Peeters

  'engine/api/geary-attachment-test.vala',
  'engine/api/geary-engine-test.vala',
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
  'engine/util-timeout-manager-test.vala',

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

geary_test_dependencies = [
  gee,
  gtk,
  libsoup,
  gmime,
  webkit2gtk,
  geary_engine_dep,
  geary_client_dep,
]

geary_test_bin = executable('geary-test',
  geary_test_sources,
  dependencies: geary_test_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_vala_options,
  c_args: geary_c_options,
)
test('Geary test suite', geary_test_bin)
