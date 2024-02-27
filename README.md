# LXC_cICAP_ClamAV

## Building an ICAP enabled Antivirus server based on c-icap, clamav and Alpine Linux on Proxmox PVE/LXC container.

The idea here is to create an LXC Alpine based container that will host:
- [c-icap server](https://github.com/c-icap/c-icap-server) as our HTTP proxy ICAP content adaptation and filtering services.
- [ClamAV](https://github.com/Cisco-Talos/clamav) as our backend AntiVirus scanning system upon ICAP submissions.
- The ClamAV official signatures databases.
- 3rd party unoffical ClamAV sginatures databases boosting our defenses.

This implementation has been influenced by this repository [c_icapClamav](https://github.com/nkapashi/c_icapClamav) which is held toward Docker environements. I do not "dislike" Docker at all, although as I'm running PVE in my personal setups, I find PVE + LXC very handy and convenient in terms of updates, backups and so on. Docker in my own setups pretty much always means two or more layers of virtualization, which I tend to avoid if not puerly for demo's etc.

A few notes before you start:
- You might use Squid as your main proxy server -- mind that the Squid ICAP integration/implementation is beyond our scope here. You'll find more information about it [here](https://wiki.squid-cache.org/ConfigExamples/ContentAdaptation/C-ICAP).
- Obviously, you can submit to ICAP what you can read & see, therefore [SSL Bumping/SSL intercpetion](https://wiki.squid-cache.org/Features/SslBump) might be advised on your proxy subsystem in order to "intercept" SSL/TLS encrypted streams.
- The "ConcurrentDatabaseReload yes" parameter which is set within the /etc/clamav/clamd.conf file will require you to have enough free system resources (memory) in order to temporarily load a second ClamAV scanning engine while scanning continues using the first engine. Once fully loaded, the new engine takes over while the previous goes to heaven.

You can use the included [cicap-deploy.sh](https://github.com/obuno/LXC_cICAP_ClamAV/blob/main/cicap-deploy.sh) shell script to deploy everything needed at once.

## Proxmox PVE container creation:
### Download/Get the latest Alpine LXC template
````
pveam update
pveam available | grep alpine
pveam download local alpine-3.19-default_20240207_amd64.tar.xz
````
### Create your LXC container (mind the container ID & change the password):
````
pct create 100 local:vztmpl/alpine-3.19-default_20240207_amd64.tar.xz \
--storage local-lvm --ostype alpine \
--arch amd64 --password ChangeMe --unprivileged 1 \
--cores 4 --memory 4096 --swap 4096 \
--hostname cICAP --rootfs volume=local-lvm:16 \
--nameserver 9.9.9.9 --searchdomain local.lan \
--net0 name=eth0,bridge=vmbr0,ip=dhcp,type=veth \
--start false

pct start 100
````
### Should you need to address a static TCP/IP stack/gw within a dedicated VLAN:
````
pct create 100 local:vztmpl/alpine-3.19-default_20240207_amd64.tar.xz \
--storage local-lvm --ostype alpine \
--arch amd64 --password ChangeMe --unprivileged 1 \
--cores 4 --memory 4096 --swap 4096 \
--hostname cICAP --rootfs volume=local-lvm:16 \
--nameserver 9.9.9.9 --searchdomain local.lan \
--net0 name=eth0,bridge=vmbr0,tag=1234,ip=10.0.0.1/24,gw=10.0.0.254,type=veth \
--start false

pct start 100
````

## From within a console on our newly created/booted Alpine LXC Container:

### Install the needed components:
````
export cicapBaseVersion="0.6.2" 
export cicapModuleVersion="0.5.7"

mkdir -p \
    /tmp/install \
    /opt/c-icap \
    /var/log/c-icap/ \
    /run/clamav \
    /var/run/c-icap
    
cd /tmp/install

apk --update --no-cache add \
    bzip2 \
    bzip2-dev \
    zlib \
    zlib-dev \
    curl tar \
    gcc make \
    g++ \
    git \
    iproute2 \
    nano \
    tcpdump \
    curl \
    clamav \
    clamav-libunrar
````

### Get the needed source code and compile it:
````
curl --silent --location --remote-name "http://downloads.sourceforge.net/project/c-icap/c-icap/0.6.x/c_icap-${cicapBaseVersion}.tar.gz"
curl --silent --location --remote-name "https://sourceforge.net/projects/c-icap/files/c-icap-modules/0.5.x/c_icap_modules-${cicapModuleVersion}.tar.gz"

tar -xzf "c_icap-${cicapBaseVersion}.tar.gz" 
tar -xzf "c_icap_modules-${cicapModuleVersion}.tar.gz" 

cd c_icap-${cicapBaseVersion}
./configure --quiet --prefix=/opt/c-icap --enable-large-files
make
make install

cd ../c_icap_modules-${cicapModuleVersion}/ 
./configure --quiet --with-c-icap=/opt/c-icap --prefix=/opt/c-icap
make
make install

chown clamav:clamav /run/clamav
mv /etc/clamav/clamd.conf /etc/clamav/clamd.conf.defaults
mv /etc/clamav/freshclam.conf /etc/clamav/freshclam.conf.defaults
````

### Cloning this repository and updating our configuration:
````
cd /tmp/install
git clone https://github.com/obuno/LXC_cICAP_ClamAV.git

cd LXC_cICAP_ClamAV/opt/c-icap/etc/
cp * /opt/c-icap/etc/

cd /tmp/install/LXC_cICAP_ClamAV/etc/
cp -R * /etc/

chmod +x /etc/local.d/cicap.start
rc-update add local

chmod 0755 /etc/periodic/hourly/freshclam
/usr/bin/freshclam

cd /opt/c-icap/share/c_icap/templates/srv_content_filtering/
cp -R en/ en-US/

cd /opt/c-icap/share/c_icap/templates/srv_url_check/
cp -R en/ en-US/

cd /opt/c-icap/share/c_icap/templates/virus_scan/
cp -R en/ en-US/

cp /opt/c-icap/bin/c-icap-client /usr/local/bin/

sed -i '/unset/i. $HOME/.profile' /etc/profile

cat << 'EOF' > /root/.profile
ENV=$HOME/.ashrc; export ENV
. $ENV
EOF

cat << 'EOF' > /root/.ashrc
alias clam-logs='tail -f /var/log/clamav/clamd.log /var/log/clamav/freshclam-hourly.log'
alias clam-dbs='clamscan --debug 2>&1 /dev/null | grep "loaded"'
alias icap-logs='tail -f /opt/c-icap/var/log/server.log'
alias icap-stat='c-icap-client -s '"'"'info?view=text'"'"' -i 0.0.0.0 -p 1344 -req use-any-url'
alias ls='ls -lsah'
alias size='for i in G M K; do    du -ah | grep [0-9]$i | sort -nr -k 1; done | head -n 11'
EOF

reboot
````

## Verfying our setup
### Confirming our ClamAV databases are stored locally:
````
cICAP:~# ls -lsah /var/lib/clamav/
total 373M   
   4.0K drwxr-xr-x    2 clamav   clamav      4.0K Feb 18 16:08 .
   4.0K drwxr-xr-x    7 root     root        4.0K Feb 18 16:02 ..
   4.0K -rw-r--r--    1 clamav   clamav      1.4K Feb 18 16:08 Sanesecurity_sigtest.yara
   4.0K -rw-r--r--    1 clamav   clamav      1.2K Feb 18 16:08 Sanesecurity_spam.yara
 108.0K -rw-r--r--    1 clamav   clamav    107.4K Feb 18 16:08 badmacro.ndb
 312.0K -rw-r--r--    1 clamav   clamav    308.2K Feb 18 16:08 blurl.ndb
   4.0K -rw-r--r--    1 clamav   clamav      3.4K Feb 18 16:08 bofhland_cracked_URL.ndb
   4.0K -rw-r--r--    1 clamav   clamav       610 Feb 18 16:08 bofhland_malware_URL.ndb
 104.0K -rw-r--r--    1 clamav   clamav    103.8K Feb 18 16:08 bofhland_malware_attach.hdb
  12.0K -rw-r--r--    1 clamav   clamav      9.4K Feb 18 16:08 bofhland_phishing_URL.ndb
 288.0K -rw-r--r--    1 clamav   clamav    285.1K Feb 18 16:08 bytecode.cvd
  76.0K -rw-r--r--    1 clamav   clamav     72.5K Feb 18 16:08 clamav.ldb
   4.0K -rw-r--r--    1 clamav   clamav        82 Feb 18 16:08 crdfam.clamav.hdb
 190.2M -rw-r--r--    1 clamav   clamav    190.2M Feb 18 16:07 daily.cld
   4.0K -rw-r--r--    1 clamav   clamav        69 Feb 18 16:07 freshclam.dat
  48.0K -rw-r--r--    1 clamav   clamav     47.0K Feb 18 16:08 hackingteam.hsb
   8.0K -rw-r--r--    1 clamav   clamav      5.8K Feb 18 16:08 indicator_rmm.ldb
   6.8M -rw-r--r--    1 clamav   clamav      6.8M Feb 18 16:08 junk.ndb
   3.3M -rw-r--r--    1 clamav   clamav      3.3M Feb 18 16:08 jurlbl.ndb
  88.0K -rw-r--r--    1 clamav   clamav     86.4K Feb 18 16:08 jurlbla.ndb
 240.0K -rw-r--r--    1 clamav   clamav    239.9K Feb 18 16:08 lott.ndb
 162.6M -rw-r--r--    1 clamav   clamav    162.6M Feb 18 16:07 main.cvd
 100.0K -rw-r--r--    1 clamav   clamav     98.5K Feb 18 16:08 malwarehash.hsb
   4.3M -rw-r--r--    1 clamav   clamav      4.3M Feb 18 16:08 phish.ndb
   4.0K -rw-r--r--    1 clamav   clamav       107 Feb 18 16:08 phishtank.ndb
  24.0K -rw-r--r--    1 clamav   clamav     21.8K Feb 18 16:08 porcupine.hsb
 172.0K -rw-r--r--    1 clamav   clamav    168.9K Feb 18 16:08 porcupine.ndb
 856.0K -rw-r--r--    1 clamav   clamav    852.6K Feb 18 16:08 rfxn.hdb
 444.0K -rw-r--r--    1 clamav   clamav    443.4K Feb 18 16:08 rfxn.ndb
 704.0K -rw-r--r--    1 clamav   clamav    700.4K Feb 18 16:08 rogue.hdb
  16.0K -rw-r--r--    1 clamav   clamav     12.2K Feb 18 16:08 sanesecurity.ftm
   1.9M -rw-r--r--    1 clamav   clamav      1.9M Feb 18 16:08 scam.ndb
  12.0K -rw-r--r--    1 clamav   clamav      9.3K Feb 18 16:08 shelter.ldb
   4.0K -rw-r--r--    1 clamav   clamav       488 Feb 18 16:08 sigwhitelist.ign2
   4.0K -rw-r--r--    1 clamav   clamav       115 Feb 18 16:08 spear.ndb
   4.0K -rw-r--r--    1 clamav   clamav       115 Feb 18 16:08 spearl.ndb
   4.0K -rw-r--r--    1 clamav   clamav        64 Feb 18 16:08 winnow.attachments.hdb
   4.0K -rw-r--r--    1 clamav   clamav       660 Feb 18 16:08 winnow.complex.patterns.ldb
   4.0K -rw-r--r--    1 clamav   clamav        66 Feb 18 16:08 winnow_bad_cw.hdb
   4.0K -rw-r--r--    1 clamav   clamav        65 Feb 18 16:08 winnow_extended_malware.hdb
   4.0K -rw-r--r--    1 clamav   clamav       159 Feb 18 16:08 winnow_extended_malware_links.ndb
   4.0K -rw-r--r--    1 clamav   clamav        65 Feb 18 16:08 winnow_malware.hdb
  16.0K -rw-r--r--    1 clamav   clamav     14.4K Feb 18 16:08 winnow_malware_links.ndb
   8.0K -rw-r--r--    1 clamav   clamav      6.4K Feb 18 16:08 winnow_phish_complete_url.ndb
   4.0K -rw-r--r--    1 clamav   clamav      2.7K Feb 18 16:08 winnow_spam_complete.ndb
````

### Listing the ClamAV loaded databases:
````
cICAP:~# clamscan --debug 2>&1 /dev/null | grep "loaded"
LibClamAV debug: unrar support loaded from /usr/lib/libclamunrar_iface.so.12.0.1
LibClamAV debug: /var/lib/clamav/sigwhitelist.ign2 loaded
LibClamAV debug: /var/lib/clamav/securiteinfo.ign2 loaded
LibClamAV debug: daily.info loaded
...
````

### Confirm our process are up and running:
````
cICAP:~#
cICAP:~# ps
PID   USER     TIME  COMMAND
...
  458 clamav    0:36 /usr/sbin/clamd
  465 root      0:00 /opt/c-icap/bin/c-icap -D -d 5
  468 root      0:00 /opt/c-icap/bin/c-icap -D -d 5
  470 root      0:00 /opt/c-icap/bin/c-icap -D -d 5
  477 root      0:00 /opt/c-icap/bin/c-icap -D -d 5
...
cICAP:~#
cICAP:~# ss -tnlp
State                     Recv-Q                    Send-Q                  Local Address:Port              Peer Address:Port                
LISTEN                    0                         512                     10.0.0.1:1344                   0.0.0.0:*
cICAP:~#
cICAP:~#
````

### Confirming our c-icap server is ready and serving (assuming your Proxy <--> c-icap integration is functional):
````
cat /opt/c-icap/var/log/server.log
tail -f /opt/c-icap/var/log/server.log
````

````
cICAP:/tmp/install# tail -f /opt/c-icap/var/log/server.log
Sun Feb 18 19:37:38 2024, 475/946277176, Preview handler return allow 204 response
Sun Feb 18 19:37:38 2024, 475/946993976, Preview handler return allow 204 response
Sun Feb 18 19:37:38 2024, 475/946133816, Preview handler return allow 204 response
Sun Feb 18 19:37:38 2024, 475/945990456, Preview handler return allow 204 response
Sun Feb 18 19:37:38 2024, 475/946707256, Request type: 4. Preview size:1024
Sun Feb 18 19:37:38 2024, 475/946707256, Preview handler return allow 204 response
Sun Feb 18 19:37:38 2024, 475/946707256, Releasing virus_scan data.....
Sun Feb 18 19:37:38 2024, 468/946133816, Preview handler return allow 204 response
Sun Feb 18 19:37:38 2024, 468/946133816, Preview handler return allow 204 response
Sun Feb 18 19:37:38 2024, 475/946133816, Preview handler return allow 204 response
Sun Feb 18 19:37:48 2024, 475/945990456, Preview handler return allow 204 response
Sun Feb 18 19:37:48 2024, 475/946133816, Request type: 4. Preview size:869
Sun Feb 18 19:37:48 2024, 475/946133816, ci_simple_file_new: Use temporary filename: /var/tmp/CI_TMP_OLeNJE
Sun Feb 18 19:37:48 2024, 475/946133816, Preview handler receives all body data
Sun Feb 18 19:37:48 2024, 475/946133816, Use 'clamd' engine to scan data
Sun Feb 18 19:37:48 2024, 475/946133816, clamd_scan response: 'fd[11]: Js.Downloader.Email_phishing-1 FOUND'
Sun Feb 18 19:37:48 2024, 475/946133816, Print violation: 
        -
        Js.Downloader.Email_phishing-1
        0
        0 (next bytes: 958)
Sun Feb 18 19:37:48 2024, 475/946133816, Print viruses header 1
        -
        Js.Downloader.Email_phishing-1
        0
        0
Sun Feb 18 19:37:48 2024, 475/946133816, Print violation: Js.Downloader.Email_phishing-1::NO_ACTION (next bytes: 983)
Sun Feb 18 19:37:48 2024, 475/946133816, Print viruses list Js.Downloader.Email_phishing-1::NO_ACTION
Sun Feb 18 19:37:48 2024, 475/946133816, VIRUS DETECTED: Js.Downloader.Email_phishing-1 , http client ip: 10.0.0.2, http user: -, http url: https://sophostest.com/Sandstorm/TestFile2.zip 
Sun Feb 18 19:37:48 2024, 475/946133816, templateLoadText: Languages are: 'en-US,en;q=0.5'
Sun Feb 18 19:37:48 2024, 475/946133816, templateFind: found: virus_scan, en-US, VIRUS_FOUND in cache at index 0
Sun Feb 18 19:37:48 2024, 475/946133816, Releasing virus_scan data.....
````

### Checking the "freshclam" hourly updates status:

````
cat /var/log/clamav/freshclam-hourly.log
tail -f /var/log/clamav/freshclam-hourly.log
````

````
cICAP:~# cat /var/log/clamav/freshclam-hourly.log
--------------------------------------
ClamAV update process started at Sun Feb 18 17:00:00 2024
daily.cld database is up-to-date (version: 27189, sigs: 2053641, f-level: 90, builder: raynman)
main.cvd database is up-to-date (version: 62, sigs: 6647427, f-level: 90, builder: sigmgr)
bytecode.cvd database is up-to-date (version: 334, sigs: 91, f-level: 90, builder: anvilleg)
...
````

## Listing the running c-icap server statistics

````
cICAP:~# c-icap-client -s "info?table=*?view=text" -i 0.0.0.0 -p 1344 -req use-any-url
ICAP server:0.0.0.0, ip:127.0.0.1, port:1344

Running Servers Statistics
===========================
Children number: 3
Free Servers: 27
Used Servers: 3
Started Processes: 6
Closed Processes: 3
Crashed Processes: 0
...
````

## Recommended ClamAV add-ons:

I would highly recommend you to add/test the following unofficial ClamAV databases to your locally available ClamAV DB's:

- The ClamAV database files available on this repository: https://github.com/ditekshen/detection (already included in the configuration here)
- The SecuriteInfo ClamAV databases in "Pro Subscription": https://www.securiteinfo.com/clamav-antivirus/improve-detection-rate-of-zero-day-malwares-for-clamav.shtml?lg=en

## Testing your setup:

You can test your setup using a few available Malware Test sites on the internet:

https://www.ikarussecurity.com/wp-content/downloads/eicar_com.zip   
https://www.virusanalyst.com/eicar.zip   
https://sophostest.com   

