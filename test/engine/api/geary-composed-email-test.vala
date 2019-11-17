/*
 * Copyright 2016-2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.ComposedEmailTest: TestCase {

    private const string IMG_CONTAINING_HTML_BODY = "<img src=\"test.png\" />";

    public ComposedEmailTest() {
        base("Geary.ComposedEmailTest");
        add_test("contains_inline_img_src", contains_inline_img_src);
        add_test("replace_inline_img_src", replace_inline_img_src);
    }

    public void contains_inline_img_src() throws Error {
        ComposedEmail composed = build_composed_with_img_src();
        assert_true(composed.contains_inline_img_src("test.png"), "Expected matched image source");
        assert_false(composed.contains_inline_img_src("missing.png"), "Expected missing image");
    }

    public void replace_inline_img_src() throws Error {
        ComposedEmail composed = build_composed_with_img_src();
        assert_true(composed.replace_inline_img_src("test.png", "updated.png"), "Expected replacement success");
        assert_false(composed.replace_inline_img_src("missing.png", "updated.png"), "Expected replacement failure");
        assert_true(composed.contains_inline_img_src("updated.png"), "Expected new image source");

        assert_true(composed.replace_inline_img_src("updated.png", "1234567.png"), "Expected replacement success for same length filename");
        assert_true(composed.contains_inline_img_src("1234567.png"), "Expected new same length image source");
    }

    private ComposedEmail build_composed_with_img_src() {
        RFC822.MailboxAddress to = new RFC822.MailboxAddress(
            "Test", "test@example.com"
        );
        RFC822.MailboxAddress from = new RFC822.MailboxAddress(
            "Sender", "sender@example.com"
        );

        var composed = new Geary.ComposedEmail(
            new GLib.DateTime.now_local(),
            new Geary.RFC822.MailboxAddresses.single(from)
        ).set_to(new Geary.RFC822.MailboxAddresses.single(to));
        composed.body_html = IMG_CONTAINING_HTML_BODY;
        return composed;
    }
}
