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
)
