geary_console_sources = files(
  'main.vala',
)

geary_console_dependencies = [
  gtk,
  gee,
  gmime,
  webkit2gtk,
  geary_engine_dep,
]

geary_console = executable('geary-console',
  geary_console_sources,
  dependencies: geary_console_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
)
