console_sources = files(
  'main.vala',
)

console_dependencies = [
  config_dep,
  gtk,
  gee,
  gmime,
  webkit2gtk,
  engine_dep,
]

console = executable('geary-console',
  console_sources,
  dependencies: console_dependencies,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
)
