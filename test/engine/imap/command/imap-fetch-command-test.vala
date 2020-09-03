/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.FetchCommandTest : TestCase {


    private MessageSet? msg_set = null;


    public FetchCommandTest() {
        base("Geary.Imap.FetchCommandTest");
        add_test("list_ctor_single_data_item", list_ctor_single_data_item);
        add_test("list_ctor_single_body_item", list_ctor_single_body_item);
        add_test("list_ctor_multiple_data_item", list_ctor_multiple_data_item);
        add_test("list_ctor_multiple_body_item", list_ctor_multiple_body_item);
        add_test("list_ctor_both", list_ctor_both);
    }

    public override void set_up() {
        this.msg_set = new MessageSet(new SequenceNumber(1));
    }

    public void list_ctor_single_data_item() throws GLib.Error {
        Gee.List<FetchDataSpecifier> data_items =
            new Gee.LinkedList<FetchDataSpecifier>();
        data_items.add(FetchDataSpecifier.UID);

        assert_equal(
            new FetchCommand(this.msg_set, data_items, null, null).to_string(),
            "---- fetch 1 uid"
        );
    }

    public void list_ctor_single_body_item() throws GLib.Error {
        Gee.List<FetchBodyDataSpecifier?> body_items =
            new Gee.LinkedList<FetchBodyDataSpecifier>();
        body_items.add(
            new FetchBodyDataSpecifier(
                FetchBodyDataSpecifier.SectionPart.TEXT, null, -1, -1, null
            )
        );

        assert_equal(
            new FetchCommand(this.msg_set, null, body_items, null).to_string(),
            "---- fetch 1 body[text]"
        );
    }

    public void list_ctor_multiple_data_item() throws GLib.Error {
        Gee.List<FetchDataSpecifier> data_items =
            new Gee.LinkedList<FetchDataSpecifier>();
        data_items.add(FetchDataSpecifier.UID);
        data_items.add(FetchDataSpecifier.BODY);

        assert_equal(
            new FetchCommand(this.msg_set, data_items, null, null).to_string(),
            "---- fetch 1 (uid body)"
        );
    }

    public void list_ctor_multiple_body_item() throws GLib.Error {
        Gee.List<FetchBodyDataSpecifier?> body_items =
            new Gee.LinkedList<FetchBodyDataSpecifier>();
        body_items.add(
            new FetchBodyDataSpecifier(
                FetchBodyDataSpecifier.SectionPart.HEADER, null, -1, -1, null
            )
        );
        body_items.add(
            new FetchBodyDataSpecifier(
                FetchBodyDataSpecifier.SectionPart.TEXT, null, -1, -1, null
            )
        );

        assert_equal(
            new FetchCommand(this.msg_set, null, body_items, null).to_string(),
            "---- fetch 1 (body[header] body[text])"
        );
    }

    public void list_ctor_both() throws GLib.Error {
        Gee.List<FetchDataSpecifier> data_items =
            new Gee.LinkedList<FetchDataSpecifier>();
        data_items.add(FetchDataSpecifier.UID);
        data_items.add(FetchDataSpecifier.FLAGS);

        Gee.List<FetchBodyDataSpecifier?> body_items =
            new Gee.LinkedList<FetchBodyDataSpecifier>();
        body_items.add(
            new FetchBodyDataSpecifier(
                FetchBodyDataSpecifier.SectionPart.HEADER, null, -1, -1, null
            )
        );
        body_items.add(
            new FetchBodyDataSpecifier(
                FetchBodyDataSpecifier.SectionPart.TEXT, null, -1, -1, null
            )
        );

        assert_equal(
            new FetchCommand(this.msg_set, data_items, body_items, null).to_string(),
            "---- fetch 1 (uid flags body[header] body[text])"
        );
    }

}
