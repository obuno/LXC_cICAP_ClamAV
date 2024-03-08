#!/bin/sh

####################################################################################################################################################
# This script will do everything in one shot -- You need to paste and run this shell script...
#
# Boot your container, paste the contents of this file in a local file and run it..
#
#    cICAP:~# vi cicap-deploy.sh
#    cICAP:~# sh cicap-deploy.sh
#
####################################################################################################################################################

(

echo "; ####################################################"
echo "; ###### cICAP deploymwent START #####################"
echo "; ####################################################"

export cicapBaseVersion="0.6.2" 
export cicapModuleVersion="0.5.7"

mkdir -p \
    /tmp/install \
    /opt/c-icap \
    /var/log/c-icap/ \
    /run/clamav \
    /var/run/c-icap
        
cd /tmp/install

echo "; ####################################################"
echo "; ###### apk update & add ############################"
echo "; ####################################################"
    
apk --update --no-cache add \
    bzip2 \
    bzip2-dev \
    zlib \
    zlib-dev \
    curl tar \
    gcc make \
    git \
    g++ \
    iproute2 \
    nano \
    tcpdump \
    curl \
    clamav \
    clamav-libunrar
 
echo "; ####################################################"
echo "; ###### c_icap base & module compilation ############"
echo "; ####################################################"
 
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

echo "; ####################################################"
echo "; ###### configuration updates & files alignment #####"
echo "; ####################################################"    

chown clamav:clamav /run/clamav
mv /etc/clamav/clamd.conf /etc/clamav/clamd.conf.defaults
mv /etc/clamav/freshclam.conf /etc/clamav/freshclam.conf.defaults

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
alias icap-reload='echo -n "reconfigure" > /var/run/c-icap.ctl'
alias icap-stat='c-icap-client -s '"'"'info?table=*?view=text'"'"' -i 0.0.0.0 -p 1344 -req use-any-url'
alias ls='ls -lsah'
alias size='for i in G M K; do    du -ah | grep [0-9]$i | sort -nr -k 1; done | head -n 11'
EOF

echo "; ####################################################"
echo "; ###### cICAP deploymwent END #######################"
echo "; ####################################################"    
    
) 2>&1 | tee /tmp/install/cicap-setup.log

read -p "Do you want to reboot now? " -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
    /sbin/reboot
fi
