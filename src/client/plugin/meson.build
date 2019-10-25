#
# Builds individual plugins. The client's plugin classes themselves
# are built back up the tree.
#

plugin_dependencies = [
  folks,
  gdk,
  geary_client_dep,
  geary_engine_dep,
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

subdir('desktop-notifications')
subdir('messaging-menu')
subdir('notification-badge')
