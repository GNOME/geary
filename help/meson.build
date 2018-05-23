geary_help_pages = [
  'accounts.page',
  'archive.page',
  'bugs.page',
  'index.page',
  'label.page',
  'limits.page',
  'overview.page',
  'preferences.page',
  'search.page',
  'shortcuts.page',
  'star.page',
  'write.page',
]

geary_help_media = [
  'figures/geary.svg'
]

# Meson 0.44 added support for automatically reading LINGUAS, until we
# can depend on that, read it in outselves. Note this means if you
# change LINGUAS, you will need remove your build directory and re-run
# meson for it to be picked up.
linguas = run_command(['cat', 'LINGUAS']).stdout().strip()
langs = []
foreach line : linguas.split('\n')
  line = line.strip()
  if not line.startswith('#')
    langs += line
  endif
endforeach

gnome.yelp(meson.project_name(),
  languages: langs,
  sources: geary_help_pages,
  media: geary_help_media
)
