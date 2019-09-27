#
# Builds individual plugins. The client's plugin classes themselves
# are built at the next directory back up the tree.
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

plugin_cflags = geary_c_options

subdir('desktop-notifications')
subdir('notification-badge')
