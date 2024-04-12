####################################################################################################################################################
#!/bin/sh
####################################################################################################################################################
#
# Below is a representation of the targeted physical environment: you'll need two NIC's on your LXC container:
# - eth0 should be bound/connected to unfiltered WAN (a WAN/DMZ LAN/VLAN)
# - eth1 should be bound/connected to where you'd like to engage/connect through ICAP on TCP:1344 (your Proxy LAN/VLAN or such)
#
#         +-----------------------------------------------------+
#         |  cICAP Alpine LXC                                   |
#         |                                                     |
#         |                                     +-------------+ |
#         |                                     | ClamAV      | |
#         |                                     | ClamD       | |
#         | +-------------+                     +-------------+ |
#         | | freshclam   |                     | c-icap      | |
#         | | signatures  |                     |             | |
#         | | updates     |                     |             | |
#         | +-------------+                     +-------------+ |
#         |-----------------------------------------------------|
# eth0/WAN| ||| |                                         | ||| |eth1/LAN
#         +-----+                                         +-----+tcp:1344
#           |                                                |
#           |                                                |
#       0.0.0.0/0                                       Proxy / ICAP Client
#                                                       10/8
#                                                       172.16/12
#                                                       192.168/16
#
# You'll need the Alpine Linux PVE/LXC templates available on your PVE host:
#
#    pveam update
#    pveam available | grep alpine
#    pveam download local alpine-3.19-default_20240207_amd64.tar.xz (latest at time of writting)
#
# A typical LXC container PVE cli that would suite our needs:
#
#    pct create 100 local:vztmpl/alpine-3.19-default_20240207_amd64.tar.xz \
#    --storage local-lvm --ostype alpine \
#    --arch amd64 --password ChangeMe --unprivileged 1 \
#    --cores 4 --memory 4096 --swap 4096 \
#    --hostname cICAP --rootfs volume=local-lvm:16 \
#    --nameserver 9.9.9.9 --searchdomain local.lan \
#    --net0 name=eth0,bridge=vmbr99,tag=99,ip=192.168.1.134/24,gw=192.168.1.254,type=veth \
#    --net1 name=eth1,bridge=vmbr1,tag=1,ip=10.1.1.134/24,gw=10.1.1.254,type=veth \
#    --start false
#
# This script will do everything in one shot -- Get and run this shell script.
# Create & boot your container, paste the contents of this file in a local file and run it.
#
#    cICAP:/# mkdir -p /tmp/install && cd /tmp/install
#    cICAP:/tmp/install# wget https://raw.githubusercontent.com/obuno/LXC_cICAP_ClamAV/main/cicap-deploy.sh
#    cICAP:/tmp/install# sh cicap-deploy.sh
#
####################################################################################################################################################

(

function fgetSysIPs() {

    echo "; ####################################################"
    echo "; ###### cICAP system status CHECK ###################"
    echo "; ####################################################"

    /sbin/ip -o addr show up scope global | while read -r num dev fam addr rest; do echo ${addr%/*}; done >> sys_ip_addr.tmp
    systemIPs=$(awk 'END { print NR }' sys_ip_addr.tmp)

    if [ $systemIPs -ge 2 ]; then

        printf ${green}"[*] Your system host multiple NICs, is this correct? (Y/n) "${default}
        read answer

        if [ "$answer" != "${answer#[Yy]}" ] ;then 
            while read -r ipaddr1 && read -r ipaddr2; do
                eth0=$ipaddr1
                eth1=$ipaddr2
            done < sys_ip_addr.tmp
        else
            systemIPs=1
        fi
    fi

    rm sys_ip_addr.tmp
}

function fsetICAPIP() {

    if [ $systemIPs -ge 2 ]; then
        printf ${green}"[*] Enter the interface name where you want your ICAP server to listen: [eth0=$eth0] [eth1=$eth1]: "${default}
        read answer
        if [ "$answer" = "eth1" ]; then
             answer="$eth1"
             sed -i -e 's/Port 1344/Port '$eth1':1344/g' /opt/c-icap/etc/c-icap.conf
        elif [ "$answer" = "eth0" ]; then
             sed -i -e 's/Port 1344/Port '$eth0':1344/g' /opt/c-icap/etc/c-icap.conf
        else
             printf ${red}"[*] Please give in a valid interface name -- Exiting"${default}
             break
        fi
    fi
}

function faddRoutes() {

    if [[ $1 == addroutes1 ]]; then
        unset dstSubnet
        while [[ ! "$dstSubnet" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do read -r -p "[*] Destination Subnet : " dstSubnet; done
        unset netMask
        while [[ ! "$netMask" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do read -r -p "[*] Network Mask       : " netMask; done
        unset netGW
        while [[ ! "$netGW" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do read -r -p "[*] Network Gateway    : " netGW; done

        staticRoute="staticroute=\"net "$dstSubnet" netmask "$netMask" gw "$netGW\"
        echo $staticRoute >> /etc/conf.d/staticroute

        rc-service staticroute stop
        rc-service staticroute start
    else
        unset dstSubnet
        while [[ ! "$dstSubnet" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do read -r -p "[*] Destination Subnet : " dstSubnet; done
        unset netMask
        while [[ ! "$netMask" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do read -r -p "[*] Network Mask       : " netMask; done
        unset netGW
        while [[ ! "$netGW" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do read -r -p "[*] Network Gateway    : " netGW; done

        staticRoute1=${staticRoute::-1}
        staticRoute2="net "$dstSubnet" netmask "$netMask" gw "$netGW\"

        sed -i '$ d' /etc/conf.d/staticroute
        echo $staticRoute1 >> /etc/conf.d/staticroute
        echo $staticRoute2 >> /etc/conf.d/staticroute

        rc-service staticroute stop
        rc-service staticroute start
    fi
}

echo "; ####################################################"
echo "; ###### cICAP deployment START ######################"
echo "; ####################################################"

# shell color variables
black=$'\x1b[90m' # Dark gray. Not used much.
red=$'\x1b[91m'
green=$'\x1b[92m'
yellow=$'\x1b[93m'
blue=$'\x1b[94m'
purple=$'\x1b[95m'
cyan=$'\x1b[96m'
pink=$'\x1b[97m'
default=$'\x1b[0m' # Reset to default color.

fgetSysIPs
#availIPs=\"${eth0}\"\"${eth1}\"

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
    btop \
    bzip2 \
    bzip2-dev \
    zlib \
    zlib-dev \
    curl tar \
    gcc make \
    htop \
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
echo "; ###### ClamAV updates & files alignment ############"
echo "; ####################################################"

chown clamav:clamav /run/clamav
mv /etc/clamav/clamd.conf /etc/clamav/clamd.conf.defaults
mv /etc/clamav/freshclam.conf /etc/clamav/freshclam.conf.defaults

cd /tmp/install
git clone https://github.com/obuno/LXC_cICAP_ClamAV.git

cd LXC_cICAP_ClamAV/opt/c-icap/etc/
cp * /opt/c-icap/etc/

if [ $systemIPs -ge 2 ]; then
    fsetICAPIP
fi

cd /tmp/install/LXC_cICAP_ClamAV/etc/
cp -R * /etc/

chmod +x /etc/init.d/c-clamd
chmod +x /etc/init.d/c-icap

rc-update add c-clamd
rc-update add c-icap

cd /tmp/install/
git clone https://github.com/darold/squidclamav.git
cd squidclamav/
./configure --with-c-icap=/opt/c-icap
make && make install

chmod 0755 /etc/periodic/hourly/freshclam
/usr/bin/freshclam

cd /opt/c-icap/share/c_icap/templates/srv_content_filtering/
cp -R en/ en-US/

cd /opt/c-icap/share/c_icap/templates/srv_url_check/
cp -R en/ en-US/

cd /opt/c-icap/share/c_icap/templates/virus_scan/
cp -R en/ en-US/
mv /opt/c-icap/share/c_icap/templates/virus_scan/en-US/VIRUS_FOUND /opt/c-icap/share/c_icap/templates/virus_scan/en-US/VIRUS_FOUND.org
mv /opt/c-icap/share/c_icap/templates/squidclamav/en/MALWARE_FOUND /opt/c-icap/share/c_icap/templates/squidclamav/en/MALWARE_FOUND.org

cd /tmp/install/LXC_cICAP_ClamAV/opt/c-icap/share/
cp -r * /opt/c-icap/share/

cp /opt/c-icap/bin/c-icap-client /usr/local/bin/

sed -i '/unset/i. $HOME/.profile' /etc/profile

/bin/cat << 'EOF' > /root/.profile
ENV=$HOME/.ashrc; export ENV
. $ENV
EOF

/bin/cat << 'EOF' > /root/.ashrc
alias clam-dbs='clamscan --debug 2>&1 /dev/null | grep "loaded"'
alias clam-logs='tail -f /var/log/clamav/clamd.log /var/log/clamav/freshclam-hourly.log'
alias icap-logs='tail -f /opt/c-icap/var/log/server.log'
alias icap-reload='echo -n "reconfigure" > /var/run/c-icap.ctl'
#alias icap-stat='c-icap-client -s '"'"'info?table=*?view=text'"'"' -i 0.0.0.0 -p 1344 -req use-any-url'
alias ls='ls -lsah'
alias size='for i in G M K; do    du -ah | grep [0-9]$i | sort -nr -k 1; done | head -n 11'
alias squidclamr='echo -n "squidclamav:cfgreload" > /var/run/c-icap/c-icap.ct'
EOF

echo "; ####################################################"
echo "; ###### cICAP LAN static route ######################"
echo "; ####################################################"

printf ${green}"[*] Do you want to add a LAN side static route entry? (Y/n) "${default}
read answer
echo    # (optional) move to a new line
if [ "$answer" != "${answer#[Yy]}" ] ;then
    rc-update add staticroute
    faddRoutes addroutes1
    printf ${green}"[*] Do you want to add another LAN static route entry ? (Y/n) "${default}
    read answer
    echo    # (optional) move to a new line
    if [ "$answer" != "${answer#[Yy]}" ] ;then
        faddRoutes addroutes2
    fi
fi

echo "; ####################################################"
echo "; ###### cICAP disabling IPv6 ########################"
echo "; ####################################################"

printf ${green}"[*] Do you want to disable IPv6 system wide? (Y/n) "${default}
read answer
echo    # (optional) move to a new line
if [ "$answer" != "${answer#[Yy]}" ] ;then
    echo "# Disabling the IPv6" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.eth0.disable_ipv6 = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.eth1.disable_ipv6 = 1" >> /etc/sysctl.conf
    /sbin/sysctl -p
fi

echo "; ####################################################"
echo "; ###### cICAP deploymwent END #######################"
echo "; ####################################################"

) 2>&1 | tee /tmp/install/cicap-setup.log

printf $'\x1b[91m'"You have to reboot this host / Do you want to reboot now? (Y/n) "$'\x1b[0m'
read answer
echo    # (optional) move to a new line
if [ "$answer" != "${answer#[Yy]}" ] ;then
    /sbin/reboot
fi
