#!/bin/bash
echo "Running post_install_rpm..." >> /run/pnp_install.log

dstdir="/etc/pnp"
logdir="/var/log/pnp"
defaultpy="/usr/lib/python2.7"
installdir="/usr/lib/python2.7/site-packages/pnp"

# Create config folders
echo "Creating config folders..." >> /run/pnp_install.log
if [ ! -d "$dstdir" ]; then
    mkdir "$dstdir"
fi
if [ ! -d "/etc/pnp/certs" ]; then
    mkdir "/etc/pnp/certs"
fi
if [ ! -d "/etc/pnp/certs/trustpoint" ]; then
    mkdir "/etc/pnp/certs/trustpoint"
fi
if [ ! -d "/etc/pnp/certs/trustpool" ]; then
    mkdir "/etc/pnp/certs/trustpool"
fi
chmod a+rw $dstdir
chmod a+rw "/etc/pnp/certs"
chmod a+rw "/etc/pnp/certs/trustpoint"
chmod a+rw "/etc/pnp/certs/trustpool"

# install config files without overwriting existing ones
echo "Installing config files..." >> /run/pnp_install.log
cfg="$installdir/data/cfg"
for file in ${cfg}/*
do
    dstfile=$(basename $file)
    if [ ! -f "$dstdir/$dstfile" ]; then
        cp -f "$file" "$dstdir/$dstfile"
    fi
    chmod a+rw "$dstdir/$dstfile"
done

# Create log directory
echo "Creating log directory..." >> /run/pnp_install.log
if [ ! -d "$logdir" ]; then
    mkdir "$logdir"
fi
chmod a+rw $logdir

# Create log files
echo "Creating log files" >> /run/pnp_install.log
if [ ! -f "/var/log/pnp/nohup.log" ]; then
    echo >> "$logdir/nohup.log"
    chmod a+rw "$logdir/nohup.log"
fi
if [ ! -f "/var/log/pnp/pnp.log" ]; then
    echo >> "$logdir/pnp.log"
    chmod a+rw "$logdir/pnp.log"
fi
if [ ! -f "/var/log/pnp/profile_status.json" ]; then
    echo >> "$logdir/profile_status.json"
    chmod a+rw "$logdir/profile_status.json"
fi
if [ ! -f "$logdir/job_status.json" ]; then
    cp -f $installdir/"data/job_status.json" $logdir/"job_status.json"
    chmod a+rw "$logdir/job_status.json"
fi
if [ ! -f "$logdir/pnp_status.json" ]; then
    cp -f $installdir/"data/pnp_status.json" $logdir/"pnp_status.json"
    chmod a+rw "$logdir/pnp_status.json"
fi
ln -fs $installdir/"posix_pnp_nohup.py" "/usr/bin/pnp"
chmod 755 "/usr/bin/pnp"
