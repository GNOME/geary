console_sources = files(
  'main.vala',
)

console_dependencies = [
  config_dep,
  gtk,
  gee,
  gmime,
  libadwaita,
  webkitgtk,
  engine_dep,
]

console_resources = gnome.compile_resources('org.gnome.GearyConsole',
  files('org.gnome.GearyConsole.gresource.xml'),
)

console = executable('geary-console',
  [ console_sources, console_resources ],
  dependencies: console_dependencies,
  vala_args: geary_vala_args,
  c_args: geary_c_args,
)
