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

internal const Geary.Email.Field REQUIRED_FIELDS = Email.Field.REFERENCES;

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
    
    // Create a common set of ancestors from In-Reply-To and References
    Gee.HashSet<RFC822.MessageID> ancestors = new Gee.HashSet<RFC822.MessageID>();
    add_ancestors(references_result.string_at(1), ancestors);
    add_ancestors(references_result.string_at(2), ancestors);
    
    // Add this message's Message-ID
    unowned string? rfc822_message_id_text = references_result.string_at(0);
    if (!String.is_empty(rfc822_message_id_text))
        ancestors.add(new RFC822.MessageID(rfc822_message_id_text));
    
    // in reality, no ancestors indicates that REFERENCES was not complete, so log that and exit
    if (ancestors.size == 0) {
        message("Unable to add message %s to conversation table: no ancestors", message_id.to_string());
        
        return;
    }
    
    // search for existing conversation(s) for any of these Message-IDs that's not this message
    StringBuilder sql = new StringBuilder("""
        SELECT conversation_id
        FROM MessageTable
        WHERE message_id IN (
    """);
    for (int ctr = 0; ctr < ancestors.size; ctr++)
        sql.append(ctr == 0 ? "?" : ",?");
    sql.append(") AND id <> ?");

    Db.Statement search_stmt = cx.prepare(sql.str);
    int col = 0;
    foreach (RFC822.MessageID ancestor in ancestors)
        search_stmt.bind_string(col++, ancestor.value);
    search_stmt.bind_rowid(col++, message_id);
    
    Gee.HashSet<int64?> conversation_ids = new Gee.HashSet<int64?>(Collection.int64_hash_func,
        Collection.int64_equal_func);
    
    Db.Result search_result = search_stmt.exec(cancellable);
    while (!search_result.finished) {
        // watch for NULL, which is the default value when a row is added to the MessageTable
        // without a conversation id (which is almost always for new rows)
        if (!search_result.is_null_at(0))
            conversation_ids.add(search_result.rowid_at(0));
        
        search_result.next(cancellable);
    }
    
    // Select the message's conversation_id from the following three scenarios:
    int64 conversation_id;
    if (conversation_ids.size > 1) {
        // this indicates that two (or more) conversations were created due to emails arriving
        // out of order and the complete(r) tree is only being available now; merge the
        // conversations into one
        conversation_id = do_merge_conversations(cx, conversation_ids, cancellable);
        
        debug("Merged %d conversations to conversation %s", conversation_ids.size - 1,
            conversation_id.to_string());
    } else if (conversation_ids.size == 0) {
        // No conversation for this Message-ID, so generate a new one
        cx.exec("""
            INSERT INTO ConversationTable
            DEFAULT VALUES
        """);
        conversation_id = cx.last_insert_rowid;
        
        debug("Created new conversation %s for message %s: %s", conversation_id.to_string(),
            message_id.to_string(), rfc822_message_id_text);
    } else {
        // one conversation found, so use that one
        conversation_id = traverse<int64?>(conversation_ids).first();
        
        debug("Expanding existing conversation %s with message %s: %s", conversation_id.to_string(),
            message_id.to_string(), rfc822_message_id_text);
    }
    
    // Assign the message to this conversation
    Db.Statement insert = cx.prepare("""
        UPDATE MessageTable
        SET conversation_id = ?
        WHERE id = ?
    """);
    insert.bind_rowid(0, conversation_id);
    insert.bind_rowid(1, message_id);
    
    insert.exec(cancellable);
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
    
    // doesn't really matter which; use the first one
    int64 conversation_id = traverse<int64?>(conversation_ids).first();
    
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
        UPDATE MessageTable
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

}

