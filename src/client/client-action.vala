/*
 * Copyright 2019-2021 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/** Common client GAction and action group names */
namespace Action {


    /** Common application GAction names. */
    namespace Application {

        /** Application GAction group name */
        public const string GROUP_NAME = "app";

        public const string ABOUT = "about";
        public const string ACCOUNTS = "accounts";
        public const string COMPOSE = "compose";
        public const string INSPECT = "inspect";
        public const string HELP = "help";
        public const string MAILTO = "mailto";
        public const string NEW_WINDOW = "new-window";
        public const string PREFERENCES = "preferences";
        public const string SHOW_EMAIL = "show-email";
        public const string SHOW_FOLDER = "show-folder";
        public const string QUIT = "quit";


        /** Returns the given action name prefixed with the group name. */
        public string prefix(string action_name) {
            return GROUP_NAME + "." + action_name;
        }

    }


    /** Common window GAction names. */
    namespace Window {

        /** Window GAction group name */
        public const string GROUP_NAME = "win";

        public const string CLOSE = "close";
        public const string SHORTCUT_HELP = "show-help-overlay";
        public const string SHOW_HELP_OVERLAY = "show-help-overlay";
        public const string SHOW_MENU = "show-menu";


        /** Returns the given action name prefixed with the group name. */
        public string prefix(string action_name) {
            return GROUP_NAME + "." + action_name;
        }

    }

    /** Common editing GAction names. */
    namespace Edit {

        /** Editing GAction group name */
        public const string GROUP_NAME = "edt";

        public const string COPY = "copy";
        public const string REDO = "redo";
        public const string UNDO = "undo";


        /** Returns the given action name prefixed with the group name. */
        public string prefix(string action_name) {
            return GROUP_NAME + "." + action_name;
        }

    }

}
