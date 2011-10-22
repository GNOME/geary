/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class TheseusAsync : MainAsync {
    public string username;
    public string password;
    public string folder;
    
    public TheseusAsync(string[] args, string username, string password, string? folder = null) {
        base (args);
        
        this.username = username;
        this.password = password;
        this.folder = folder ?? "INBOX";
    }
    
    protected override async int exec_async() throws Error {
        Geary.Account account = Geary.Engine.open(new Geary.Credentials(username, password),
            File.new_for_path(Environment.get_user_data_dir()).get_child("geary"),
            File.new_for_path(Environment.get_current_dir()));
        
        Geary.Folder inbox = yield account.fetch_folder_async(new Geary.FolderRoot(folder, null, true));
        yield inbox.open_async(true);
        
        Geary.Conversations threads = new Geary.Conversations(inbox, Geary.Email.Field.ENVELOPE);
        yield threads.load_async(-1, -1, Geary.Folder.ListFlags.NONE, null);
        
        yield inbox.close_async();
        
        foreach (Geary.Conversation conversation in threads.get_conversations()) {
            print_thread(conversation, conversation.get_origin(), 0);
            stdout.printf("\n");
        }
        
        return 0;
    }
    
    private void print_thread(Geary.Conversation conversation, Geary.ConversationNode node, int level) {
        for (int ctr = 0; ctr < level; ctr++)
            stdout.printf("  ");
        
        print_email(node);
        
        Gee.Collection<Geary.ConversationNode>? children = conversation.get_replies(node);
        if (children != null) {
            foreach (Geary.ConversationNode child_node in children)
                print_thread(conversation, child_node, level + 1);
        }
    }
    
    private void print_email(Geary.ConversationNode node) {
        Geary.Email? email = node.get_email();
        if (email == null)
            stdout.printf("(no message available)\n");
        else
            stdout.printf("%s\n", get_details(email));
    }
    
    private string get_details(Geary.Email email) {
        StringBuilder builder = new StringBuilder();
        
        if (email.subject != null)
            builder.append_printf("%.40s ", email.subject.value);
        
        if (email.from != null)
            builder.append_printf("(%.20s) ", email.from.to_string());
        
        if (email.date != null)
            builder.append_printf("[%s] ", email.date.to_string());
        
        return builder.str;
    }
}

int main(string[] args) {
    if (args.length != 3 && args.length != 4) {
        stderr.printf("usage: theseus <username> <password> [folder]\n");
        
        return 1;
    }
    
    return new TheseusAsync(args, args[1], args[2], (args.length == 4) ? args[3] : null).exec();
}

