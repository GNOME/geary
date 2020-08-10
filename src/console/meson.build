console_sources = files(
  'main.vala',
)

console_dependencies = [
  gtk,
  gee,
  gmime,
  webkit2gtk,
  engine_dep,
]

console = executable('geary-console',
  console_sources,
  dependencies: console_dependencies,
  include_directories: config_h_dir,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
)
