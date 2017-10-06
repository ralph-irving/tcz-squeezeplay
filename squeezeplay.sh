#!/bin/sh

##
## This script is a basic startup script for the SqueezePlay binary (jive) that requires a few environment variables be set.
##

## Change these if you changed your install path
INSTALL_DIR=/opt/squeezeplay
LIB_DIR=$INSTALL_DIR/lib
INC_DIR=$INSTALL_DIR/include

## Start up
export LD_LIBRARY_PATH=$LIB_DIR:$LD_LIBRARY_PATH
export LD_INCLUDE_PATH=$INC_DIR:$LD_INCLUDE_PATH
export PATH=$PATH:$INSTALL_DIR/bin:/usr/sbin:/sbin

#
# ALSA
#
# Supported sample sizes 0=autodetect, default=16
# "<0|16|24|24_3|32>"
#
export USEALSASAMPLESIZE=0
# export USEALSADEVICE=default
# export USEALSACAPTURE=default
# export USEALSAEFFECTS=null
# export USEALSAPCMTIMEOUT=500
# export USEALSABUFFERTIME=30000
# export USEALSAPERIODCOUNT=3
# export USEALSANOMMAP=null
#
# Allow screensaver to start
#
export SDL_VIDEO_ALLOW_SCREENSAVER=1
#
# Define custom JogglerSkin size
#
# export JL_SCREEN_WIDTH=800
# export JL_SCREEN_HEIGHT=480

eventno=$(cat /proc/bus/input/devices | awk '/FT5406 memory based driver/{for(a=0;a>=0;a++){getline;{if(/mouse/==1){ print $NF;exit 0;}}}}')

export HOME=/home/tc

export JIVE_NOCURSOR=1

export TSLIB_TSDEVICE=/dev/input/$eventno
export SDL_MOUSEDRV=TSLIB
export SDL_MOUSEDEV=$TSLIB_TSDEVICE

while true; do
sleep 3
cd $INSTALL_DIR/bin
./jive > /dev/null 2>&1
done

