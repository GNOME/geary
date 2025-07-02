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

    engine.add_suite(new Geary.AccountInformationTest().suite);
    engine.add_suite(new Geary.AttachmentTest().suite);
    engine.add_suite(new Geary.ContactHarvesterImplTest().suite);
    engine.add_suite(new Geary.EngineTest().suite);
    engine.add_suite(new Geary.FolderPathTest().suite);
    engine.add_suite(new Geary.IdleManagerTest().suite);
    engine.add_suite(new Geary.TimeoutManagerTest().suite);
    engine.add_suite(new Geary.TlsNegotiationMethodTest().suite);
    engine.add_suite(new Geary.App.ConversationTest().suite);
    engine.add_suite(new Geary.App.ConversationSetTest().suite);
    // Depends on ConversationTest and ConversationSetTest passing
    engine.add_suite(new Geary.App.ConversationMonitorTest().suite);
    engine.add_suite(new Geary.Ascii.Test().suite);
    engine.add_suite(new Geary.ConfigFileTest().suite);
    engine.add_suite(new Geary.Db.DatabaseTest().suite);
    engine.add_suite(new Geary.Db.VersionedDatabaseTest().suite);
    engine.add_suite(new Geary.HTML.UtilTest().suite);

    // Other IMAP tests rely on these working, so test them first
    engine.add_suite(new Geary.Imap.DataFormatTest().suite);

    engine.add_suite(new Geary.Imap.CreateCommandTest().suite);
    engine.add_suite(new Geary.Imap.FetchCommandTest().suite);
    engine.add_suite(new Geary.Imap.FetchDataDecoderTest().suite);
    engine.add_suite(new Geary.Imap.ListParameterTest().suite);
    engine.add_suite(new Geary.Imap.MailboxSpecifierTest().suite);
    engine.add_suite(new Geary.Imap.NamespaceResponseTest().suite);

    // Depends on IMAP commands working
    engine.add_suite(new Geary.Imap.DeserializerTest().suite);
    engine.add_suite(new Geary.Imap.ClientConnectionTest().suite);
    engine.add_suite(new Geary.Imap.ClientSessionTest().suite);

    engine.add_suite(new Geary.ImapDB.AccountTest().suite);
    engine.add_suite(new Geary.ImapDB.AttachmentTest().suite);
    engine.add_suite(new Geary.ImapDB.AttachmentIoTest().suite);
    engine.add_suite(new Geary.ImapDB.DatabaseTest().suite);
    engine.add_suite(new Geary.ImapDB.EmailIdentifierTest().suite);
    engine.add_suite(new Geary.ImapDB.FolderTest().suite);

    // Depends on ImapDB working
    engine.add_suite(new Geary.FtsSearchQueryTest().suite);

    engine.add_suite(new Geary.ImapEngine.AccountProcessorTest().suite);
    engine.add_suite(new Geary.ImapEngine.GenericAccountTest().suite);

    // Depends on ImapDb.Database working correctly
    engine.add_suite(new Geary.ContactStoreImplTest().suite);

    engine.add_suite(new Geary.Inet.Test().suite);
    engine.add_suite(new Geary.Mime.ContentTypeTest().suite);
    engine.add_suite(new Geary.Outbox.EmailIdentifierTest().suite);
    engine.add_suite(new Geary.RFC822.MailboxAddressTest().suite);
    engine.add_suite(new Geary.RFC822.MailboxAddressesTest().suite);
    engine.add_suite(new Geary.RFC822.MessageDataTest().suite);
    engine.add_suite(new Geary.RFC822.PartTest().suite);
    engine.add_suite(new Geary.RFC822.Utils.Test().suite);
    // Message requires all of the rest of the package working, so put
    // last
    engine.add_suite(new Geary.RFC822.MessageTest().suite);
    engine.add_suite(new Geary.String.Test().suite);
    engine.add_suite(new Geary.EmailTest().suite);
    engine.add_suite(new Geary.ComposedEmailTest().suite);

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
