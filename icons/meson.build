system_icons_dir = join_paths(data_dir, 'icons', 'hicolor')

icon_files = files(
  'mail-archive-symbolic.svg',
  'close-symbolic.svg',
  'detach-symbolic.svg',
  'text-x-generic-symbolic.svg',
  'edit-symbolic.svg',
  'font-size-symbolic.svg',
  'font-color-symbolic.svg',
  'format-ordered-list-symbolic.svg',
  'format-ordered-list-symbolic-rtl.svg',
  'format-text-remove-symbolic.svg',
  'format-toolbar-toggle-symbolic.svg',
  'format-unordered-list-symbolic.svg',
  'format-unordered-list-symbolic-rtl.svg',
  'mail-drafts-symbolic.svg',
  'mail-drafts-symbolic-rtl.svg',
  'mail-inbox-symbolic.svg',
  'mail-outbox-symbolic.svg',
  'mail-sent-symbolic.svg',
  'mail-sent-symbolic-rtl.svg',
  'tag-symbolic.svg',
  'tag-symbolic-rtl.svg',
)

colour_app_icon_dirs = [
  '16x16',
  '24x24',
  '32x32',
  '48x48',
  '256x256',
  '512x512',
]

install_data(icon_files,
  install_dir: join_paths(system_icons_dir, 'scalable', 'actions'),
)

scalable_dir = join_paths('hicolor', 'scalable', 'apps')

install_data(
  join_paths(scalable_dir, '@0@.svg'.format(geary_id)),
  install_dir: join_paths(data_dir, 'icons', scalable_dir),
)

symbolic_dir = join_paths('hicolor', 'symbolic', 'apps')

install_data(
  join_paths(symbolic_dir, 'org.gnome.Geary-symbolic.svg'),
  install_dir: join_paths(data_dir, 'icons', symbolic_dir),
  rename: '@0@-symbolic.svg'.format(geary_id)
)
