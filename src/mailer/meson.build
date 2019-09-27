geary_mailer_sources = files(
  'main.vala',
)

geary_mailer_dependencies = [
  gee,
  gmime,
  webkit2gtk,
  geary_engine_dep,
]

geary_mailer = executable('geary-mailer',
  geary_mailer_sources,
  dependencies: geary_mailer_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
)
