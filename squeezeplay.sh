#!/bin/sh

if [ -f /usr/local/sbin/config.cfg ]; then
	source /usr/local/sbin/config.cfg
fi

eventno=$(cat /proc/bus/input/devices | awk '/FT5406 memory based driver/{for(a=0;a>=0;a++){getline;{if(/mouse/==1){ print $NF;exit 0;}}}}')
if [ x"" != x"$eventno" ];then            
    export JIVE_NOCURSOR=1 
    export TSLIB_TSDEVICE=/dev/input/$eventno
    export SDL_MOUSEDRV=TSLIB
    export SDL_MOUSEDEV=$TSLIB_TSDEVICE
else
	unset JIVE_NOCURSOR
	unset SDL_MOUSEDRV
	unset SDL_MOUSEDEV
fi                         

export LOG=/var/log/jivelite.log
export HOME=/home/tc
export JIVE_FRAMERATE=22

# Define custom JogglerSkin size
# export JL_SCREEN_WIDTH=800
# export JL_SCREEN_HEIGHT=480

/usr/sbin/fbset -depth 32 >> $LOG 2>&1

set | grep TS >> $LOG 2>&1
echo $OUTPUT >> $LOG 2>&1            

while true; do
    sleep 3

    if [ -x /opt/squeezeplay/bin/jive ]; then

	/usr/local/etc/init.d/squeezelite stop >> $LOG 2>&1

	if [ ! -z "$OUTPUT" ]; then
		export USEALSADEVICE=$OUTPUT
		export USEALSACAPTURE=$OUTPUT
	else
		export USEALSADEVICE=hw:CARD=ALSA
		export USEALSACAPTURE=hw:CARD=ALSA
	fi

	export USEALSASAMPLESIZE=0
	export USEALSABUFFERTIME=100000
	export USEALSAPERIODCOUNT=4

	cd /opt/squeezeplay/bin
	./jive >> $LOG 2>&1
    else
        /opt/jivelite/bin/jivelite >> $LOG 2>&1
    fi
done
