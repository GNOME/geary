/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Enables plugins to display an action bar.
 *
 * Action bars are horizontal containers for buttons, menu buttons and
 * labels that can be added individually or in groups, at the start,
 * centre, or end of the bar. These interface items are added by
 * creating an appropriate {@link Item} instance and calling {@link
 * append_item}.
 *
 * The {@link Actionable} instances added to the action bar must have
 * their actions registered either globally for the application using
 * {@link Application.register_action} or locally for a specific UI
 * element, for example using {@link Composer.register_action}.
 */
public class Plugin.ActionBar : Geary.BaseObject {


    /**
     * Determines the position of a widget added to an action bar.
     *
     * @see append_item
     */
    public enum Position {
        /**
         * The widget is added at the start of the action bar.
         *
         * The start of the bar is the left side in locales with
         * left-to-right writing direction, and the right side in
         * right-to-left locales.
         */
        START,

        /** The widget is added in the centre of the action bar. */
        CENTRE,

        /**
         * The widget is added at the end of the action bar.
         *
         * The end of the bar is the right side in locales with
         * left-to-right writing direction, and the left side in
         * right-to-left locales.
         */
        END;
    }


    /** Denotes an object that can be added to an action bar. */
    public interface Item: GLib.Object {

    }

    /** A text label item for an action bar. */
    public class LabelItem: GLib.Object, Item {


        public string text { get; private set; }

        /** Constructs a text label item for an action bar. */
        public LabelItem(string text) {
            this.text = text;
        }

    }

    /** A button item for an action bar. */
    public class ButtonItem: GLib.Object, Item {


        public Actionable action { get; private set; }


        /** Constructs a button item for an action bar. */
        public ButtonItem(Actionable action) {
            this.action = action;
        }

    }

    /** A menu for an action bar. */
    public class MenuItem: GLib.Object, Item {


        public string label { get; private set; }
        public GLib.MenuModel menu { get; private set; }


        /** Constructs a menu item for an action bar. */
        public MenuItem(string label, GLib.MenuModel menu) {
            this.label = label;
            this.menu = menu;
        }

    }

    /**
     * A group of items for an action bar.
     *
     * Groups will be displayed in a way that indicates they are
     * related, for example as pill buttons. Items in the group are
     * laid out in the same direction as the current locale's writing
     * direction.
     */
    public class GroupItem: GLib.Object, Item {


        private Gee.List<Item> items = new Gee.LinkedList<Item>();


        /** Constructs a button item for an action bar. */
        public GroupItem(Gee.Collection<Item>? items = null) {
            if (items != null) {
                this.items.add_all(items);
            }
        }

        /** Appends an item to end of the group. */
        public void append_item(Item item) {
            this.items.add(item);
        }

        /** Returns a read-only list of items in the group. */
        public Gee.List<Item> get_items() {
            return this.items.read_only_view;
        }

    }


    private Gee.List<Item> start_items = new Gee.LinkedList<Item>();
    private Gee.List<Item> centre_items = new Gee.LinkedList<Item>();
    private Gee.List<Item> end_items = new Gee.LinkedList<Item>();


    /** Constructs a new, empty action bar. */
    public ActionBar() {
    }

    /**
     * Appends an item to the action bar in the given location.
     *
     * Items at the same position are laid out in the same direction
     * as the current locale's writing direction.
     */
    public void append_item(Item item, Position item_position) {
        switch (item_position) {
        case START:
            this.start_items.add(item);
            break;
        case CENTRE:
            this.centre_items.add(item);
            break;
        case END:
            this.end_items.add(item);
            break;
        }
    }

    /** Returns a read-only list of items at the given position. */
    public Gee.List<Item> get_items(Position item_position) {
        Gee.List<Item>? items = null;
        switch (item_position) {
        case START:
            items = this.start_items.read_only_view;
            break;

        case CENTRE:
            items = this.centre_items.read_only_view;
            break;

        case END:
            items = this.end_items.read_only_view;
            break;
        }
        return items;
    }

}
