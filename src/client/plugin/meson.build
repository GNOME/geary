#
# Builds individual plugins. The client's plugin classes themselves
# are built back up the tree.
#

plugin_dependencies = [
  folks,
  gdk,
  client_dep,
  engine_dep,
  gee,
  gmime,
  goa,
  gtk,
  javascriptcoregtk,
  libhandy,
  libmath,
  libpeas,
  libsoup,
  webkit2gtk,
]

plugin_c_args = geary_c_args

# Use .desktop.in since xgettext doesn't recognise .plugin files as
# desktop files when translating them at install time.
plugin_data_src_suffix = '.desktop.in'
plugin_data_suffix = '.plugin'

subdir('desktop-notifications')
subdir('email-templates')
subdir('folder-highlight')
subdir('messaging-menu')
subdir('notification-badge')
subdir('sent-sound')
subdir('special-folders')
