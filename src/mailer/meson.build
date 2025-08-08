mailer_sources = files(
  'main.vala',
)

mailer_dependencies = [
  config_dep,
  gee,
  gmime,
  webkitgtk,
  engine_dep,
]

mailer = executable('geary-mailer',
  mailer_sources,
  dependencies: mailer_dependencies,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
)
