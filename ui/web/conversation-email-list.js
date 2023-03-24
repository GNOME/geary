/*
 * Copyright 2023 Cedric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * JS version for ConversationEmailList.
 */
let ConversationEmailList = function() {
    this.init.apply(this, arguments);
};

ConversationEmailList.SCROLL_MARGIN = 100;
ConversationEmailList.QUOTE_CONTAINER_ID = "geary-conversation-email-list";
ConversationEmailList.QUOTE_HIDE_CLASS = "geary-hide";

ConversationEmailList.prototype = {
    init: function() {
      this._imagesPolicyClicked = MessageSender("images_policy_clicked");
    },
    /**
     * Add a new conversation after removing any existing one
     */
    add: function(subject_str) {
        let parent = document.body;
        parent.innerHTML = '';

        xmlhttp = new XMLHttpRequest();
        xmlhttp.open("GET", "html:conversation-email-list.html", false);
        xmlhttp.send();
        parent.innerHTML = xmlhttp.responseText;

        let subject = document.getElementById("geary-conversation-subject");
        subject.innerHTML = subject_str;

        let images_policy = document.getElementById("geary-images-policy");
        images_policy.addEventListener('click', event => {
          var rect = images_policy.getBoundingClientRect();
          console.log(rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top);
          this._imagesPolicyClicked({
                    x: rect.left,
                    y: rect.top,
                    width: rect.right - rect.left,
                    height: rect.bottom - rect.top + 4
                });
        });
    },

    /**
     * Insert email with id at position
     */
    insert_email: function(email_id, position=-1) {
        let parent = document.getElementById(ConversationEmailList.QUOTE_CONTAINER_ID);
        let email = document.getElementById(email_id);
        if (position == -1) {
            parent.appendChild(email);
        } else {
            child = parent.children.item(position + 1);
            if (child == null) {
                parent.appendChild(email);
            } else {
                parent.insertBefore(email);
            }
        }
    },
    setLoaded: function() {
      let list = document.getElementById(ConversationEmailList.QUOTE_CONTAINER_ID);
      list.classList.add("geary-conversation-email-list-loaded");
    },
    scrollTo: function(email_id) {
      let email = document.getElementById(email_id);
      console.log(email.offsetTop);
      window.scrollTo(0, email.offsetTop - ConversationEmailList.SCROLL_MARGIN);
    },
};

var conversation_email_list = new ConversationEmailList();


