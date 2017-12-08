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
)
