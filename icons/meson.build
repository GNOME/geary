system_icons_dir = join_paths(datadir, 'icons', 'hicolor')

icon_files = files(
  'mail-archive-symbolic.svg',
  'close-symbolic.svg',
  'detach-symbolic.svg',
  'text-x-generic-symbolic.svg',
  'edit-symbolic.svg',
  'format-ordered-list-symbolic.svg',
  'format-ordered-list-symbolic-rtl.svg',
  'format-text-remove-symbolic.svg',
  'format-unordered-list-symbolic.svg',
  'format-unordered-list-symbolic-rtl.svg',
  'mail-drafts-symbolic.svg',
  'mail-drafts-symbolic-rtl.svg',
  'mail-forward-symbolic.svg',
  'mail-forward-symbolic-rtl.svg',
  'mail-inbox-symbolic.svg',
  'mail-outbox-symbolic.svg',
  'mail-reply-all-symbolic.svg',
  'mail-reply-all-symbolic-rtl.svg',
  'mail-reply-sender-symbolic.svg',
  'mail-reply-sender-symbolic-rtl.svg',
  'mail-sent-symbolic.svg',
  'mail-sent-symbolic-rtl.svg',
  'marker-symbolic.svg',
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

install_data(join_paths('hicolor', 'scalable', 'apps', 'org.gnome.Geary.svg'),
  install_dir: join_paths(system_icons_dir, 'scalable', 'apps'),
)

install_data(join_paths('hicolor', 'symbolic', 'apps', 'org.gnome.Geary-symbolic.svg'),
  install_dir: join_paths(system_icons_dir, 'symbolic', 'apps'),
)
