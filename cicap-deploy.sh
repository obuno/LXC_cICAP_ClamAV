#!/bin/sh

####################################################################################################################################################
# This script will do everything in one shot -- You need GIT installed before being able to run this shell script...
#
# Boot your container, manually install git, paste the contents of this file in a local file and run it..
#
#    cICAP:~# apk --update --no-cache add git 
#    cICAP:~# vi cicap-deploy.sh
#    cICAP:~# sh cicap-deploy.sh
#
####################################################################################################################################################

(

    echo "; ####################################################"
    echo "; ###### cICAP deploymwent START #####################"
    echo "; ####################################################"

    export cicapBaseVersion="0.5.12" 
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
 
    curl --silent --location --remote-name "http://downloads.sourceforge.net/project/c-icap/c-icap/0.5.x/c_icap-${cicapBaseVersion}.tar.gz"
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

    echo "; ####################################################"
    echo "; ###### cICAP deploymwent END #######################"
    echo "; ####################################################"    
    
) 2>&1 | tee /tmp/install/cicap-setup.log

reboot
