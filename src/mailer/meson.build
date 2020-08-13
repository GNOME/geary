mailer_sources = files(
  'main.vala',
)

mailer_dependencies = [
  gee,
  gmime,
  webkit2gtk,
  engine_dep,
]

mailer = executable('geary-mailer',
  mailer_sources,
  dependencies: mailer_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
)
