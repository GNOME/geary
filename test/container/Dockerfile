# Postfix+Dovecot container
#
# Based configuration by David Gilly:
# https://github.com/daonerz/postfix-dovecot
#
# Build using something like:
#
#     docker build -t geary/postfix-dovecot test/container
#
# Run using something like the command:
#
#     docker run --rm --name geary-postfix-dovecot \
#         -p 25:25 -p 465:465 -p 143:143 -p 993:993 \
#         geary/postfix-dovecot

From ubuntu:rolling

# Set noninteractive mode for apt-get
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update
RUN apt-get -y install supervisor postfix dovecot-common dovecot-imapd rsyslog

# password is same as the login name
RUN useradd -m -G mail -p KBmTFjVSZs0EE geary
RUN touch /var/mail/geary
RUN chown geary:mail /var/mail/geary

ADD supervisor/supervisord.conf /etc/supervisor/conf.d/

ADD dovecot/10-master.conf /etc/dovecot/conf.d/

ADD postfix/master.cf /etc/postfix/
RUN postconf -e 'myhostname = localhost'
RUN postconf -e 'mydestination = localhost'
RUN postconf -e 'smtpd_sasl_type = dovecot'
RUN postconf -e 'smtpd_sasl_auth_enable = yes'
RUN postconf -e 'smtpd_recipient_restrictions = permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination'
RUN postconf -e 'smtpd_sasl_path = private/auth'
RUN postconf -e 'message_size_limit=52428800'

EXPOSE 25 143 587 993

# Run
CMD /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
