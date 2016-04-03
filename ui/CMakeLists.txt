
set(RESOURCE_LIST
  STRIPBLANKS "accelerators.ui"
  STRIPBLANKS "account_cannot_remove.glade"
  STRIPBLANKS "account_list.glade"
  STRIPBLANKS "account_spinner.glade"
  STRIPBLANKS "app_menu.interface"
  STRIPBLANKS "certificate_warning_dialog.glade"
  STRIPBLANKS "composer.glade"
  STRIPBLANKS "composer_accelerators.ui"
  STRIPBLANKS "edit_alternate_emails.glade"
  STRIPBLANKS "find_bar.glade"
  STRIPBLANKS "login.glade"
  STRIPBLANKS "password-dialog.glade"
  STRIPBLANKS "preferences.glade"
  STRIPBLANKS "remove_confirm.glade"
  STRIPBLANKS "toolbar_empty_menu.ui"
  STRIPBLANKS "toolbar_mark_menu.ui"
  STRIPBLANKS "upgrade_dialog.glade"
)

compile_gresources(
  RESOURCES_C
  RESOURCES_XML
  TYPE EMBED_C
  SOURCE_DIR "${CMAKE_SOURCE_DIR}/ui"
  PREFIX "/org/gnome/Geary"
  RESOURCES ${RESOURCE_LIST}
)

compile_gresources(
  RESOURCES_H
  RESOURCES_XML
  TYPE EMBED_H
  SOURCE_DIR "${CMAKE_SOURCE_DIR}/ui"
  PREFIX "/org/gnome/Geary"
  RESOURCES ${RESOURCE_LIST}
)

add_custom_target(resource_h ALL DEPENDS ${RESOURCES_H})
add_custom_target(resource_c ALL DEPENDS ${RESOURCES_C})

set(RESOURCES_C ${RESOURCES_C} PARENT_SCOPE)
