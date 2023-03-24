/*
 * Copyright 2023 Cedric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * JS version for ConversationEmail.
 */
let ConversationEmail = function() {
    this.init.apply(this, arguments);
};

ConversationEmail.QUOTE_CONTAINER_ID = "geary-conversation-email";

ConversationEmail.prototype = {
    init: function() {
    },

    /**
     * Add a new email with id
     */
    add: function(email_id, name_str, addr_str, others_array, to_array, cc_array, bcc_array, preview_str) {
        let email = document.createElement('div');
        email.setAttribute("id", email_id);
        email.setAttribute("class", "geary-email-container");
        document.body.append(email);

        xmlhttp = new XMLHttpRequest();
        xmlhttp.open("GET", "html:conversation-email.html", false);
        xmlhttp.send();
        email.innerHTML = xmlhttp.responseText;

        let img = document.createElement('img');
        img.setAttribute("src", "avatar:" + email_id);
        let img_div = email.getElementsByClassName("geary-email-avatar")[0];
        img_div.appendChild(img);

        let display_name = email.getElementsByClassName("geary-email-header-from-display-name")[0];
        display_name.innerHTML = name_str;

        let addr = email.getElementsByClassName("geary-email-header-from-addr")[0];
        addr.innerHTML = addr_str;

        let others = email.getElementsByClassName("geary-email-header-from-others")[0];
        ConversationEmail.mailto_builder(others, others_array);

        let to = email.getElementsByClassName("geary-email-header-to")[0];
        ConversationEmail.mailto_builder(to, to_array);

        let cc = email.getElementsByClassName("geary-email-header-cc")[0];
        ConversationEmail.mailto_builder(cc, cc_array);

        let bcc = email.getElementsByClassName("geary-email-header-bcc")[0];
        ConversationEmail.mailto_builder(bcc, bcc_array);

        let preview = email.getElementsByClassName("geary-email-header-preview")[0];
        preview.innerText = preview_str;

        this.add_collapsible(email_id);
    },
    loadRemoteResources: function(email_id) {
        const TYPES = "*[src], *[srcset]";
        let email = document.getElementById(email_id);
        for (const element of email.querySelectorAll(TYPES)) {
            let src = "";
            try {
                src = element.src;
            } catch (e) {
                // fine
            }
            if (src != "") {
                element.src = "";
                element.src = src;
            }

            let srcset = "";
            try {
                srcset = element.srcset;
            } catch (e) {
                // fine
            }
            if (srcset != "") {
                element.srcset = "";
                element.srcset = srcset;
            }
        }
    },
    collapse: function(email_id) {
      let email = document.getElementById(email_id);
      let element = email.getElementsByClassName("geary-collapsible")[0];
      var content = element.nextElementSibling;
      if (content.style.maxHeight) {
        element.classList.toggle("active");
        content.style.maxHeight = null;
        return true;
      }
      return false;
    },
    expand: function(email_id) {
      let email = document.getElementById(email_id);
      let element = email.getElementsByClassName("geary-collapsible")[0];
      let content = element.nextElementSibling;
      let content_body = content.getElementsByClassName("geary-email-content-body")[0];

      element.classList.toggle("active");

      if (content_body.innerHTML != '') {
        content.style.maxHeight = content.scrollHeight + "px";
        return false;
      }

      xmlhttp = new XMLHttpRequest();
      xmlhttp.open("GET", "iframe:" + email_id, false);
      xmlhttp.send();
      let iframe = document.createElement('iframe');
      iframe.setAttribute("scrolling", "no");
      iframe.onload = function() {
        iframe.contentWindow.document.open();
        iframe.contentWindow.document.write(xmlhttp.responseText);
        iframe.contentWindow.document.close();
        Promise.all(
          Array.from(
            iframe.contentWindow.document.images
          ).filter(
            img => !img.complete
          ).map(
            img => new Promise(
              resolve => {
                img.onload = img.onerror = resolve;
              }
            )
          )
        ).then(() => {
            iframe.style.height = iframe.contentWindow.document.documentElement.scrollHeight + 'px';
            content.style.maxHeight = content.scrollHeight + "px";
            console.log("coucou")
            if (email.classList.contains("scrollTo")) {
              console.log(email.offsetTop)
              window.scrollTo(0, email.offsetTop);
            }
        });
        iframe.style.height = iframe.contentWindow.document.documentElement.scrollHeight + 'px';
        content.style.maxHeight = content.scrollHeight + "px";
      };
      content_body.appendChild(iframe);
      return true;
    },
    add_collapsible: function(email_id) {
      let email = document.getElementById(email_id);
      let element = email.getElementsByClassName("geary-collapsible")[0];
      element.addEventListener("click", () => {
        if (this.collapse(email_id)) return;
        if (this.expand(email_id)) return;

      });
    }
};

ConversationEmail.mailto_builder = function(parent, addresses) {
  if (addresses.length == 0) {
    parent.style.display = 'none';
    return;
  }

  addresses.forEach(address => {
    var split = address.split("<");
    if (split.length > 0) {
      let a = document.createElement('a');
      a.innerText = split[0];
      a.setAttribute("href", "mailto:" + address);
      parent.appendChild(a);
    }
  });
};

var conversation_email = new ConversationEmail();

