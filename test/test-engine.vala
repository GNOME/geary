/*
 * Copyright 2016-2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

int main(string[] args) {
    /*
     * Initialise all the things.
     */

    // Ensure things like e.g. GLib's formatting routines uses a
    // well-known UTF-8-based locale rather ASCII.
    //
    // Distros don't ship well-known locales other than C.UTF-8 by
    // default, but Flatpak does not currently support C.UTF-8, so
    // need to try both. :(
    // https://gitlab.com/freedesktop-sdk/freedesktop-sdk/issues/812
    string? locale = GLib.Intl.setlocale(LocaleCategory.ALL, "C.UTF-8");
    if (locale == null) {
        GLib.Intl.setlocale(LocaleCategory.ALL, "en_US.UTF-8");
    }

    Test.init(ref args);

    Geary.RFC822.init();
    Geary.HTML.init();
    Geary.Logging.init();

    /*
     * Hook up all tests into appropriate suites
     */

    TestSuite engine = new TestSuite("engine");

    engine.add_suite(new Geary.AccountInformationTest().get_suite());
    engine.add_suite(new Geary.AttachmentTest().get_suite());
    engine.add_suite(new Geary.ContactHarvesterImplTest().get_suite());
    engine.add_suite(new Geary.EngineTest().get_suite());
    engine.add_suite(new Geary.FolderPathTest().get_suite());
    engine.add_suite(new Geary.IdleManagerTest().get_suite());
    engine.add_suite(new Geary.TimeoutManagerTest().get_suite());
    engine.add_suite(new Geary.TlsNegotiationMethodTest().get_suite());
    engine.add_suite(new Geary.App.ConversationTest().get_suite());
    engine.add_suite(new Geary.App.ConversationSetTest().get_suite());
    // Depends on ConversationTest and ConversationSetTest passing
    engine.add_suite(new Geary.App.ConversationMonitorTest().get_suite());
    engine.add_suite(new Geary.Ascii.Test().get_suite());
    engine.add_suite(new Geary.ConfigFileTest().get_suite());
    engine.add_suite(new Geary.Db.DatabaseTest().get_suite());
    engine.add_suite(new Geary.Db.VersionedDatabaseTest().get_suite());
    engine.add_suite(new Geary.HTML.UtilTest().get_suite());
    // Other IMAP tests rely on DataFormat working, so test that first
    engine.add_suite(new Geary.Imap.DataFormatTest().get_suite());
    engine.add_suite(new Geary.Imap.CreateCommandTest().get_suite());
    engine.add_suite(new Geary.Imap.DeserializerTest().get_suite());
    engine.add_suite(new Geary.Imap.FetchCommandTest().get_suite());
    engine.add_suite(new Geary.Imap.ListParameterTest().get_suite());
    engine.add_suite(new Geary.Imap.MailboxSpecifierTest().get_suite());
    engine.add_suite(new Geary.Imap.NamespaceResponseTest().get_suite());
    engine.add_suite(new Geary.ImapDB.AccountTest().get_suite());
    engine.add_suite(new Geary.ImapDB.AttachmentTest().get_suite());
    engine.add_suite(new Geary.ImapDB.AttachmentIoTest().get_suite());
    engine.add_suite(new Geary.ImapDB.DatabaseTest().get_suite());
    engine.add_suite(new Geary.ImapDB.EmailIdentifierTest().get_suite());
    engine.add_suite(new Geary.ImapDB.FolderTest().get_suite());
    engine.add_suite(new Geary.ImapEngine.AccountProcessorTest().get_suite());

    // Depends on ImapDb.Database working correctly
    engine.add_suite(new Geary.ContactStoreImplTest().get_suite());

    engine.add_suite(new Geary.Inet.Test().get_suite());
    engine.add_suite(new Geary.JS.Test().get_suite());
    engine.add_suite(new Geary.Mime.ContentTypeTest().get_suite());
    engine.add_suite(new Geary.Outbox.EmailIdentifierTest().get_suite());
    engine.add_suite(new Geary.RFC822.MailboxAddressTest().get_suite());
    engine.add_suite(new Geary.RFC822.MailboxAddressesTest().get_suite());
    engine.add_suite(new Geary.RFC822.MessageTest().get_suite());
    engine.add_suite(new Geary.RFC822.MessageDataTest().get_suite());
    engine.add_suite(new Geary.RFC822.PartTest().get_suite());
    engine.add_suite(new Geary.RFC822.Utils.Test().get_suite());
    engine.add_suite(new Geary.String.Test().get_suite());

    /*
     * Run the tests
     */
    TestSuite root = TestSuite.get_root();
    root.add_suite(engine);

    MainLoop loop = new MainLoop ();

    int ret = -1;
    Idle.add(() => {
            ret = Test.run();
            loop.quit();
            return false;
        });

    loop.run();
    return ret;
}
