set(UI_DEST share/geary/ui)

install(FILES accelerators.ui DESTINATION ${UI_DEST})
install(FILES account_list.glade DESTINATION ${UI_DEST})
install(FILES account_cannot_remove.glade DESTINATION ${UI_DEST})
install(FILES account_spinner.glade DESTINATION ${UI_DEST})
install(FILES composer.glade DESTINATION ${UI_DEST})
install(FILES composer_accelerators.ui DESTINATION ${UI_DEST})
install(FILES find_bar.glade DESTINATION ${UI_DEST})
install(FILES login.glade DESTINATION ${UI_DEST})
install(FILES message.glade DESTINATION ${UI_DEST})
install(FILES password-dialog.glade DESTINATION ${UI_DEST})
install(FILES preferences.glade DESTINATION ${UI_DEST})
install(FILES remove_confirm.glade DESTINATION ${UI_DEST})
install(FILES toolbar_mark_menu.ui DESTINATION ${UI_DEST})
install(FILES toolbar_menu.ui DESTINATION ${UI_DEST})
install(FILES upgrade_dialog.glade DESTINATION ${UI_DEST})

#
# NOTE: Update GLADE_FILES in ../CMakeLists.txt with additions and removals
#
