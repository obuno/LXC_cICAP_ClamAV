# LXC_cICAP_ClamAV [ VIRUS FOUND ] SMTP notifications service

I made this document in order to provide potential ideas and solutions to trigger email/smtp notifications from your LXC_cICAP_ClamAV appliance(s) on VIRUS FOUND logs entry. The idea here is to trigger an outbound email in the occurrence of a ClamAV/SquidClamAV "VIRUS FOUND" positive ICAP submission. 

A few notes:

- I am not yet 100% satisfied with this implementation yet, it is work in progress so to say.
- I find the POSIX ASH shell to act somewhat strangely on the ```tail``` command.
- SMTP outbound service authentication isn't yet implemented.

I am currently working on the above mentioned items and will update accordingly in the occurrence of any updates/fixes/changes.   
**If you're able to help -- please get in touch !**

## Adding the needed package/create local directory on the Alpine LXC container:

```yaml
apk add --no-cache coreutils
mkdir -p /opt/c-icap/bin/custom
``` 

## Creating the POSIX ```#!/bin/sh``` compatible notification service script:

```yaml
/bin/cat << 'EOF' > /opt/c-icap/bin/custom/vf-service.sh
#!/bin/sh

set -euo pipefail

while true; do
    /opt/c-icap/bin/custom/vf-main.sh &
    pidVirusFound=$!
    sleep 60
    /sbin/rc-service c-icap-notification restart
done
EOF
```

## Creating the POSIX ```#!/bin/sh``` compatible email notification script (mind the update/adaptations needed):

```yaml
/bin/cat << 'EOF' > /opt/c-icap/bin/custom/vf-main.sh
#!/bin/sh

set -euo pipefail

smtpsrv=10.10.10.10 -----------------------------------------------------------------------> adaptations/update needed here
log=/var/log/c-icap/server.log

rm -rf /tmp/virusmail || true

# initial word count on the current c-icap server.log file
nLogLine="$( wc -l < /var/log/c-icap/server.log )"

# Delimiters and mail structuring items
virusfound="---------- cICAP/ClamAV | VIRUS FOUND ----------"
delim="------------------------------------------------"
delimtime="TIME --- : "
delimurl="URL ---- : "
delimvirus="VIRUS -- : "

# Create email structure function / UPDATE ARE NEEDED below according to your environment
fCmail () {
    echo "From: cicap@local.lan" > /tmp/virusmail -----------------------------------------> adaptations/update needed here
    echo "To: sysops@local.lan" >> /tmp/virusmail -----------------------------------------> adaptations/update needed here
    echo "Subject: VIRUS FOUND" >> /tmp/virusmail
    echo "" >> /tmp/virusmail
}

# main notification on new trigger function
fTail () {
    while : ; do

        # launch tail if the log file got updated
        NEW=$( tail -n +$(( 1 + nLogLine )) /var/log/c-icap/server.log | sed -n '/squidclamav_end_of_data_handler/p' | sed -n '/LOG Virus found in /p' )

        # arithmetic test on $NEW / greater than 0
        [[ "${#NEW}" -gt 0 ]] && {
            # storing the raw event log in a dedicated local file
            echo "${NEW}" >> /var/log/c-icap/virus-found.log

            # formatting our events
            caughttime=$( echo "${NEW}" | cut -d\, -f1 )
            urlused=$( echo "${NEW}" | cut -d\, -f5 | cut -c21- | awk -F ' ' '{print $1}' )
            virusinfo=$( echo "${NEW}" | cut -d\, -f5 | cut -c21- | awk -F ' ' '{print $5}' )

            # filling our final email information's
            echo "$virusfound" >> /tmp/virusmail
            echo "$delim" >> /tmp/virusmail
            echo "" >> /tmp/virusmail                 
            echo "$delimtime" "$caughttime" >> /tmp/virusmail
            echo "$delimurl" "$urlused" >> /tmp/virusmail
            echo "$delimvirus" "$virusinfo" >> /tmp/virusmail   

            # sendmail with our information
            /bin/cat /tmp/virusmail | /usr/sbin/sendmail -S "$smtpsrv" -t

            # re-init the nLogLine variable awaiting the next trigger
            nLogLine="$( wc -l < /var/log/c-icap/server.log )"
        }
        sleep 20

        # clear the local contents of our "sent" email
        rm -rf /tmp/virusmail || true

        # re-create our next to be sent email structure
        fCmail
    done
}

fCmail
fTail
EOF
```

We now need to make our scripts executable:

```yaml
chmod +x /opt/c-icap/bin/custom/vf-*
```

## Creating the OpenRC service definition file:

```yaml
/bin/cat << 'EOF' > /etc/init.d/c-icap-notification
#!/sbin/openrc-run

name=c-icap-notification
command="/opt/c-icap/bin/custom/vf-service.sh"
pidfile="/var/run/c-icap/c-icap-notification.pid"
command_background=True
command_user="root:root"

depend() {
    need net
    after c-clamd
    after c-icap
}

start_pre() {
    /bin/touch /var/log/c-icap/virus-found.log
}

stop() {
    ebegin "Stopping c-icap-notification"
    /usr/bin/pkill -f vf-main.sh
    start-stop-daemon --stop --retry 60 --pidfile /var/run/c-icap/c-icap-notification.pid
    eend $? "Failed to stop c-icap-notification"
}
EOF
```

We also need to make that script executable:

```yaml
chmod +x /etc/init.d/c-icap-notification
```

## Finally, let's enable & start the service:

```yaml
rc-update add c-icap-notification
```

```yaml
rc-service c-icap-notification start
```

```yaml
rc-status
... 
 c-icap-notification                                                     [  started  ]
... 
```

## The running process once the service has started:

```yaml
cICAP:~# ps
PID   USER     TIME  COMMAND
...
96280 root      0:00 {vf-service.sh} /bin/sh /opt/c-icap/bin/custom/vf-service.sh
97450 root      0:00 {vf-main.sh} /bin/sh /opt/c-icap/bin/custom/vf-main.sh
...
```
