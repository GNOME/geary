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

    GLib.Intl.setlocale(LocaleCategory.ALL, "C.UTF-8");

    Test.init(ref args);

    Geary.RFC822.init();
    Geary.HTML.init();
    Geary.Logging.init();
    if (GLib.Test.verbose()) {
        GLib.Log.set_writer_func(Geary.Logging.default_log_writer);
        Geary.Logging.log_to(GLib.stdout);
    }

    /*
     * Hook up all tests into appropriate suites
     */

    TestSuite engine = new TestSuite("engine");

    engine.add_suite(new Geary.AccountInformationTest().steal_suite());
    engine.add_suite(new Geary.AttachmentTest().steal_suite());
    engine.add_suite(new Geary.ContactHarvesterImplTest().steal_suite());
    engine.add_suite(new Geary.EngineTest().steal_suite());
    engine.add_suite(new Geary.FolderPathTest().steal_suite());
    engine.add_suite(new Geary.IdleManagerTest().steal_suite());
    engine.add_suite(new Geary.TimeoutManagerTest().steal_suite());
    engine.add_suite(new Geary.TlsNegotiationMethodTest().steal_suite());
    engine.add_suite(new Geary.App.ConversationTest().steal_suite());
    engine.add_suite(new Geary.App.ConversationSetTest().steal_suite());
    // Depends on ConversationTest and ConversationSetTest passing
    engine.add_suite(new Geary.App.ConversationMonitorTest().steal_suite());
    engine.add_suite(new Geary.Ascii.Test().steal_suite());
    engine.add_suite(new Geary.ConfigFileTest().steal_suite());
    engine.add_suite(new Geary.Db.DatabaseTest().steal_suite());
    engine.add_suite(new Geary.Db.VersionedDatabaseTest().steal_suite());
    engine.add_suite(new Geary.HTML.UtilTest().steal_suite());

    // Other IMAP tests rely on these working, so test them first
    engine.add_suite(new Geary.Imap.DataFormatTest().steal_suite());

    engine.add_suite(new Geary.Imap.CreateCommandTest().steal_suite());
    engine.add_suite(new Geary.Imap.FetchCommandTest().steal_suite());
    engine.add_suite(new Geary.Imap.FetchDataDecoderTest().steal_suite());
    engine.add_suite(new Geary.Imap.ListParameterTest().steal_suite());
    engine.add_suite(new Geary.Imap.MailboxSpecifierTest().steal_suite());
    engine.add_suite(new Geary.Imap.NamespaceResponseTest().steal_suite());

    // Depends on IMAP commands working
    engine.add_suite(new Geary.Imap.DeserializerTest().steal_suite());
    engine.add_suite(new Geary.Imap.ClientConnectionTest().steal_suite());
    engine.add_suite(new Geary.Imap.ClientSessionTest().steal_suite());

    engine.add_suite(new Geary.ImapDB.AccountTest().steal_suite());
    engine.add_suite(new Geary.ImapDB.AttachmentTest().steal_suite());
    engine.add_suite(new Geary.ImapDB.AttachmentIoTest().steal_suite());
    engine.add_suite(new Geary.ImapDB.DatabaseTest().steal_suite());
    engine.add_suite(new Geary.ImapDB.EmailIdentifierTest().steal_suite());
    engine.add_suite(new Geary.ImapDB.FolderTest().steal_suite());

    // Depends on ImapDB working
    engine.add_suite(new Geary.FtsSearchQueryTest().steal_suite());

    engine.add_suite(new Geary.ImapEngine.AccountProcessorTest().steal_suite());
    engine.add_suite(new Geary.ImapEngine.GenericAccountTest().steal_suite());

    // Depends on ImapDb.Database working correctly
    engine.add_suite(new Geary.ContactStoreImplTest().steal_suite());

    engine.add_suite(new Geary.Inet.Test().steal_suite());
    engine.add_suite(new Geary.Mime.ContentTypeTest().steal_suite());
    engine.add_suite(new Geary.Outbox.EmailIdentifierTest().steal_suite());
    engine.add_suite(new Geary.RFC822.MailboxAddressTest().steal_suite());
    engine.add_suite(new Geary.RFC822.MailboxAddressesTest().steal_suite());
    engine.add_suite(new Geary.RFC822.MessageDataTest().steal_suite());
    engine.add_suite(new Geary.RFC822.PartTest().steal_suite());
    engine.add_suite(new Geary.RFC822.Utils.Test().steal_suite());
    // Message requires all of the rest of the package working, so put
    // last
    engine.add_suite(new Geary.RFC822.MessageTest().steal_suite());
    engine.add_suite(new Geary.String.Test().steal_suite());
    engine.add_suite(new Geary.EmailTest().steal_suite());
    engine.add_suite(new Geary.ComposedEmailTest().steal_suite());

    /*
     * Run the tests
     */
    unowned TestSuite root = TestSuite.get_root();
    root.add_suite((owned) engine);

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
