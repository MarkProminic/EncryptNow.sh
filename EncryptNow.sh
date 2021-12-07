#!/usr/bin/bash

# Variables

## FQDNs to Protect
SERVICE=automation
DOMAIN="$SERVICE.some.domain.net"

# If Additional Domains are to be registered in the same SSL, place them here and ensure they have an A record set, if not comment this.
#ADDITIONAL_DOMAINS="-d $SERVICE.some.domain.net  -d $SERVICE-01.some.domain.net -d $SERVICE-02.some.domain.net"

PASS="SomeSecurePassword"

## Email for Expiration Notifications
SUPPORTEMAIL=SomeUser@SomeDomain.TLD

## Name of the file of the key and certs without the ext.
KEYNAME=mydomain.com

# Where the certificate needs to be placed
CERTDIR=/ssl/live

## Clean Apt and or Yum Repo
CLEAN=false

### Update System
UPDATE=false

### Set this to true on the first few runs to not lock us out of attempts
STAGING=false

delimiter="-d"

## If this machine is a HAProxy instance, set this to true
DUMMYSERVICE=false

# If this is a machine without Haproxy set this to true
SKIPHAPROXY=true

## If you have added more domains after, set this to true to renew early
FORCERENEWAL=false

# Set to true for HAproxy installations
ALTERNATEPORT=true
INSTALL=false


## Begin Scripts Do Not Modify Below this point!
if $FORCERENEWAL; then
        force="--force-renewal"
else
        force=""
fi

if $ALTERNATEPORT; then
        altport="--http-01-port=8080"
fi

if $CLEAN; then
        /bin/echo -e "\nCleaning Repos for package updates\n"

        if [ -f /etc/redhat-release ]; then
                sudo yum clean all
        fi

        if [ -f /etc/lsb-release ]; then
                sudo apt-get clean -y
        fi

fi

if $UPDATE; then
        /bin/echo -e "\nUpdating All Packages\n"

        if [ -f /etc/redhat-release ]; then
                sudo yum update  -y
        fi

        if [ -f /etc/lsb-release ]; then
                sudo apt-get update -y
        fi

fi


if $INSTALL; then
        /bin/echo -e "\nInstalling Certbot Packages\n"

        if [ -f /etc/redhat-release ]; then
                if command -v python3 >/dev/null 2>&1 ; then
                        sudo yum install epel-release certbot python3-certbot  -y
                else
                        sudo yum install  epel-release certbot python2-certbot  -y
                fi
        fi

        if [ -f /etc/lsb-release ]; then
                if command -v python3 >/dev/null 2>&1 ; then
                        sudo apt-get install certbot python3-certbot  -y
                else
                        sudo apt-get install certbot python2-certbot  -y
                fi
        fi

fi

if $DUMMYSERVICE; then
   /bin/echo -e "\nSkipping Service shutdown as the service doesn't reside on this server\n"
else
   /bin/echo -e "\nStopping $SERVICE so that we can use the port\n"
   systemctl stop $SERVICE
fi

if $STAGING; then
        /bin/echo -e "\nWe are Running a Staging request\n"
        cmd="sudo certbot certonly --non-interactive -d  $DOMAIN $ADDITIONAL_DOMAINS  --agree-tos -m $SUPPORTEMAIL  --standalone $altport   $force --staging"
else
        /bin/echo -e "\nWe are Running a  production request\n"
        cmd="sudo certbot certonly --non-interactive -d  $DOMAIN $ADDITIONAL_DOMAINS  --agree-tos -m $SUPPORTEMAIL  --standalone $altport $force"
fi
$cmd
lastrun=$?
if [ $lastrun -eq 0 ] && /bin/echo -e "\nCertificate Retrieved\n\n" || exit 1; then
        PFKFILE=/etc/letsencrypt/live/$DOMAIN/$DOMAIN.pfx
        if test -f "$FILE"; then
                mv  $PFKFILE $PFKFILE-bak
                /bin/echo -e "\nBacking up the Old Certificate to: $PFKFILE-bak\n"
        fi
        /bin/echo -e "\nConvertingCertificate into PFX\n"

        openssl pkcs12 -inkey /etc/letsencrypt/live/$DOMAIN/privkey.pem -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem -export -out /etc/letsencrypt/live/$DOMAIN/$DOMAIN.pfx -passin pass:"$PASS"  -passout pass:"$PASS"


        ## Create the Symlink to the safelinx installation folder
        /bin/echo -e "\nCreating SYMLinks to the P12 Certificates to the Directory Path\n"
        ln -sf /etc/letsencrypt/live/$DOMAIN/$DOMAIN.pfx $CERTDIR/$DOMAIN/$KEYNAME.p12
        ln -sf /etc/letsencrypt/live/$DOMAIN/$DOMAIN.pfx $CERTDIR/$DOMAIN/$KEYNAME.pfx
        cp -rL /etc/letsencrypt/live/$DOMAIN $CERTDIR/
        if $DUMMYSERVICE; then
                /bin/echo -e "\nSkipping Service startup as the service doesn't reside on this server\n"
        else
                /bin/echo -e "\nStarting Service $SERVICE\n"
                systemctl stop $SERVICE
        fi
fi

## Update HAproxy with Alternate Port
if $SKIPHAPROXY; then
        /bin/echo -e "\nSkipping HAProxy Startup"
else
        ## Create the HAproxy Contactenated Certificate:
        cat /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/letsencrypt/live/$DOMAIN/privkey.pem >  /etc/letsencrypt/live/$DOMAIN/haproxy.$SERVICE.$DOMAIN.pem

        #Concatenate the delimiter with the main string
        string=$ADDITIONAL_DOMAINS$delimiter
        #Split the text based on the delimiter

#       myarray=()
        while [[ $string ]]; do
          myarray+=( "${string%%"$delimiter"*}" )
          string=${string#*"$delimiter"}
        done

        /bin/echo -e "\nConverting to HAProxy Concatenated PEM Structure\n"
        /bin/echo -e "/etc/letsencrypt/live/$DOMAIN/haproxy.$SERVICE.$DOMAIN.pem $DOMAIN ${myarray[@]}" >> /etc/ssl/certs.txt
        /bin/echo -e "\nStarting HAProxy"
        systemctl restart haproxy
fi
