
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
  STRIPBLANKS "folder-popover.ui"
  STRIPBLANKS "login.glade"
  STRIPBLANKS "password-dialog.glade"
  STRIPBLANKS "preferences.glade"
  STRIPBLANKS "remove_confirm.glade"
  STRIPBLANKS "toolbar_empty_menu.ui"
  STRIPBLANKS "toolbar_mark_menu.ui"
  STRIPBLANKS "upgrade_dialog.glade"
  "geary.css"
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

# Work around valac wanting the resource files to be in the same
# directory as the XML file.
add_custom_target(resource_copy ALL
    mkdir -p ${CMAKE_BINARY_DIR}/ui
  COMMAND
    cp ${RESOURCES_XML} ${CMAKE_BINARY_DIR}/ui
  COMMAND
    cp ${CMAKE_SOURCE_DIR}/ui/*.glade ${CMAKE_SOURCE_DIR}/ui/*.interface ${CMAKE_SOURCE_DIR}/ui/*.ui ${CMAKE_BINARY_DIR}/ui
  COMMAND
    cp ${CMAKE_SOURCE_DIR}/ui/*.css ${CMAKE_BINARY_DIR}/ui
)
add_dependencies(resource_copy resource_c)

# Export the file names so they can be used in the source build
set(RESOURCES_C ${RESOURCES_C} PARENT_SCOPE)
set(RESOURCES_XML "${CMAKE_BINARY_DIR}/ui/.gresource.xml" PARENT_SCOPE)
