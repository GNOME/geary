/* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Associated calls for adding and fetching messages associated as conversations.
 *
 * Note that methods prefixed with do_ are intended to be run from within a transaction.
 */
 
namespace Geary.ImapDB.Conversation {

internal const Geary.Email.Field REQUIRED_FIELDS = Geary.Account.ASSOCIATED_REQUIRED_FIELDS;

/**
 * Should only be called when an email message's {@link REQUIRED_FIELDS} are initially fulfilled.
 */
internal void do_add_message_to_conversation(Db.Connection cx, int64 message_id, Cancellable? cancellable)
    throws Error {
    Db.Statement references_stmt = cx.prepare("""
        SELECT message_id, in_reply_to, reference_ids
        FROM MessageTable
        WHERE id = ?
    """);
    references_stmt.bind_rowid(0, message_id);
    
    Db.Result references_result = references_stmt.exec(cancellable);
    if (references_result.finished) {
        message("Unable to add message %s to conversation table: not found", message_id.to_string());
        
        return;
    }
    
    // Create a common set of ancestors from In-Reply-To and References
    Gee.HashSet<RFC822.MessageID> ancestors = new Gee.HashSet<RFC822.MessageID>();
    add_ancestors(references_result.string_at(1), ancestors);
    add_ancestors(references_result.string_at(2), ancestors);
    
    // Add this message's Message-ID to the ancestors
    unowned string? rfc822_message_id_text = references_result.string_at(0);
    RFC822.MessageID? this_rfc822_message_id = null;
    if (!String.is_empty(rfc822_message_id_text)) {
        this_rfc822_message_id = new RFC822.MessageID(rfc822_message_id_text);
        ancestors.add(this_rfc822_message_id);
    }
    
    // in reality, no ancestors indicates that REFERENCES was not complete, so log that and exit
    if (ancestors.size == 0) {
        message("Unable to add message %s to conversation table: no references", message_id.to_string());
        
        return;
    }
    
    // search for existing conversation(s) for any of these Message-IDs ... include this message
    // to avoid a single-message conversation being processed multiple times and creating a new
    // conversation each time
    StringBuilder sql = new StringBuilder("""
        SELECT conversation_id
        FROM MessageConversationTable
        WHERE rfc822_message_id IN (
    """);
    for (int ctr = 0; ctr < ancestors.size; ctr++)
        sql.append(ctr == 0 ? "?" : ",?");
    sql.append(")");

    Db.Statement search_stmt = cx.prepare(sql.str);
    int col = 0;
    foreach (RFC822.MessageID ancestor in ancestors)
        search_stmt.bind_string(col++, ancestor.value);
    
    Gee.HashSet<int64?> conversation_ids = new Gee.HashSet<int64?>(Collection.int64_hash_func,
        Collection.int64_equal_func);
    
    Db.Result search_result = search_stmt.exec(cancellable);
    while (!search_result.finished) {
        // watch for NULL, which is the default value when a row is added to the MessageConversationTable
        // without a conversation id (which is almost always for new rows)
        if (!search_result.is_null_at(0))
            conversation_ids.add(search_result.rowid_at(0));
        
        search_result.next(cancellable);
    }
    
    // Select the message's conversation_id from the following three scenarios:
    int64 conversation_id;
    switch (conversation_ids.size) {
        case 0:
            // No conversation for this Message-ID, so generate a new one
            cx.exec("""
                INSERT INTO ConversationTable
                DEFAULT VALUES
            """);
            conversation_id = cx.last_insert_rowid;
            
            debug("Created new conversation %s for message %s: %s", conversation_id.to_string(),
                message_id.to_string(), rfc822_message_id_text);
        break;
        
        case 1:
            // one conversation found, so use that one
            conversation_id = traverse<int64?>(conversation_ids).first();
            
            debug("Expanding existing conversation %s with message %s: %s", conversation_id.to_string(),
                message_id.to_string(), rfc822_message_id_text);
        break;
        
        default:
            // this indicates that two (or more) conversations were created due to emails arriving
            // out of order and the complete(r) tree is only being available now; merge the
            // conversations into one
            conversation_id = do_merge_conversations(cx, conversation_ids, cancellable);
            
            debug("Merged %d conversations to conversation %s", conversation_ids.size - 1,
                conversation_id.to_string());
        break;
    }
    
    // If each Message-ID present in table, update its conversation_id, otherwise add Message-ID and
    // index to the conversation
    foreach (RFC822.MessageID ancestor in ancestors) {
        bool ancestor_is_added_message =
            this_rfc822_message_id != null && this_rfc822_message_id.equal_to(ancestor);
        
        Db.Statement select = cx.prepare("""
            SELECT id, conversation_id, message_id
            FROM MessageConversationTable
            WHERE rfc822_message_id = ?
        """);
        select.bind_string(0, ancestor.value);
        
        Db.Result result = select.exec(cancellable);
        if (result.finished) {
            // not present, add new
            Db.Statement insert = cx.prepare("""
                INSERT INTO MessageConversationTable
                (conversation_id, message_id, rfc822_message_id)
                VALUES (?, ?, ?)
            """);
            insert.bind_rowid(0, conversation_id);
            // if ancestor is the added message's Message-ID, connect them now
            if (ancestor_is_added_message)
                insert.bind_rowid(1, message_id);
            else
                insert.bind_null(1);
            insert.bind_string(2, ancestor.value);
            
            insert.exec(cancellable);
        } else if (ancestor_is_added_message || result.is_null_at(1) || result.rowid_at(1) != conversation_id) {
            // already present but with different conversation id, or this message is the Message-ID,
            // so connect them now
            Db.Statement update = cx.prepare("""
                UPDATE MessageConversationTable
                SET conversation_id = ?, message_id = ?
                WHERE id = ?
            """);
            update.bind_rowid(0, conversation_id);
            if (ancestor_is_added_message)
                update.bind_rowid(1, message_id);
            else if (!result.is_null_at(2))
                update.bind_rowid(1, result.rowid_at(2));
            else
                update.bind_null(1);
            update.bind_rowid(2, result.rowid_at(0));
            
            update.exec(cancellable);
        }
    }
}

private void add_ancestors(string? text, Gee.Collection<RFC822.MessageID> ancestors) {
    if (String.is_empty(text))
        return;
    
    RFC822.MessageIDList message_id_list = new RFC822.MessageIDList.from_rfc822_string(text);
    ancestors.add_all(message_id_list.list);
}

private int64 do_merge_conversations(Db.Connection cx, Gee.Set<int64?> conversation_ids, Cancellable? cancellable)
    throws Error {
    // must be at least two in order to merge
    assert(conversation_ids.size > 1);
    
    // although multithreaded transactions aren't problem per se with database locking, it is
    // possible for multiple threads to be processing mail on the same conversation at the same
    // time and will therefore be reading the same list and choosing which to merge; by being
    // predictable here, ensure that the same conversation is selected in both cases
    int64 conversation_id = traverse<int64?>(conversation_ids)
        .to_tree_set(Collection.int64_compare_func)
        .first();
    
    //
    // TODO: Merge flags together
    //
    
    // reuse this IN block in the following two SQL statements
    StringBuilder in_sql = new StringBuilder("(");
    bool first = true;
    foreach (int64 other_conversation_id in conversation_ids) {
        if (other_conversation_id == conversation_id)
            continue;
        
        if (!first)
            in_sql.append(",");
        
        in_sql.append(other_conversation_id.to_string());
        first = false;
    }
    in_sql.append(")");
    
    // set other messages in the other conversations to the chosen one
    StringBuilder merge_sql = new StringBuilder("""
        UPDATE MessageConversationTable
        SET conversation_id = ?
        WHERE conversation_id IN
    """);
    merge_sql.append(in_sql.str);
    
    Db.Statement merge_stmt = cx.prepare(merge_sql.str);
    merge_stmt.bind_rowid(0, conversation_id);
    
    merge_stmt.exec(cancellable);
    
    // remove merged conversation(s)
    StringBuilder delete_sql = new StringBuilder("""
        DELETE FROM ConversationTable
        WHERE id IN
    """);
    delete_sql.append(in_sql.str);
    
    cx.exec(delete_sql.str);
    
    return conversation_id;
}

private Gee.HashSet<ImapDB.EmailIdentifier>? do_fetch_associated_email_ids(Db.Connection cx,
    ImapDB.EmailIdentifier id, Cancellable? cancellable) throws Error {
    // In case not indexed in conversation table, always mark this message as a member of the
    // conversation, even if it's a singleton
    Gee.HashSet<ImapDB.EmailIdentifier> associated_message_ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
    associated_message_ids.add(id);
    
    Db.Statement stmt = cx.prepare("""
        SELECT conversation_id
        FROM MessageConversationTable
        WHERE message_id = ?
    """);
    stmt.bind_rowid(0, id.message_id);
    
    Db.Result result = stmt.exec(cancellable);
    if (result.finished || result.is_null_at(0))
        return associated_message_ids;
    
    int64 conversation_id = result.rowid_at(0);
    
    stmt = cx.prepare("""
        SELECT message_id
        FROM MessageConversationTable
        WHERE conversation_id = ?
    """);
    stmt.bind_rowid(0, conversation_id);
    
    for (result = stmt.exec(cancellable); !result.finished; result.next(cancellable)) {
        if (!result.is_null_at(0))
            associated_message_ids.add(new ImapDB.EmailIdentifier(result.rowid_at(0), null));
    }
    
    return associated_message_ids;
}

}

