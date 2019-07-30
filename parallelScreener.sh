#!/bin/bash

#names of server machines (see ssh config file / gnu parrallel man pages for more) each node has to have gnu parallel and ffmpeg installed
#SERVERS="2/:,2/nfaAdela,8/nfaDTL01,8/nfaProjekce"
SERVERS="4/:,4/mothership"

#if using multiple machines the path sould point to the same file (same mount point) in network shared folder
INPUT="$1"

#for multiple machines this should point to same location (mount point) on network
OUTPUT_PATH=/home/kof/chunks

#for multiple machines this should point to the same location on each machine (system vars?)
FONTDIR=/home/kof/.fonts

# clean auxiliary directory
if [ -d "$OUTPUT_PATH" ]; then
  echo Cleaning temp directory
  rm -rf $OUTPUT_PATH/*
else
  echo Creating temp directory
  mkdir $OUTPUT_PATH
fi

# clean temp files
if [ -f /tmp/jobs ]; then
  rm /tmp/jobs
fi
if [ -f /tmp/jobs2 ]; then
  rm /tmp/jobs2
fi
if [ -f /tmp/files ]; then
  rm /tmp/files
fi 
if [ -f /tmp/files2 ]; then
  rm /tmp/files2
fi
if [ -f $OUTPUT_PATH/dump.ts ]; then
  rm $OUTPUT_PATH/dump.ts
fi

CRF=22
HEIGHT=480
SIZ=14

# length of segment (in seconds)
FRAG_L=15

#get duration of input file and parse decimals
DURATION=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT");
FRAMERATE=`ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT" | bc -l `
SECS=$(echo $DURATION | awk -F'.' '{print $1}')
FRAG=$(echo $DURATION | awk -F'.' '{print $2}')

# Floor function
Floor () {
  DIVIDEND=${1}
  DIVISOR=${2}
  RESULT=$(( ( ${DIVIDEND} - ( ${DIVIDEND} % ${DIVISOR}) )/${DIVISOR} ))
  echo ${RESULT}
}

#compute number of chunks segemnts
NO_OF_SEGMENTS=$( Floor $SECS $FRAG_L )
echo Total duration: "$SECS.$FRAG"s
echo Segment length: "$FRAG_L"s
echo Number of segments: $NO_OF_SEGMENTS

#set the length of the last one
REST=$(( $SECS % $FRAG_L )).$FRAG


MINS=0
HOS=0

SCOUNT=0
LOOP_NO=0
SCOUNT_TOTAL=0

while [[ $SCOUNT_TOTAL -le $SECS ]];
do
  TIME=`printf "%02d" $HOS`:`printf "%02d" $MINS`:`printf "%02d" $SCOUNT`

  SEGMENT=$FRAG_L
  if [ $LOOP_NO -eq  $NO_OF_SEGMENTS ]
  then
    SEGMENT=$REST
  fi

  OUTPUT=$OUTPUT_PATH/$(echo `basename "$INPUT"` | awk -F'.' '{print $1}')_$(echo $TIME | tr ':' '_').ts

  echo "ffmpeg -loglevel panic -hwaccel auto -vaapi_device  /dev/dri/renderD128 -ss $TIME -i "$INPUT" -t $SEGMENT -filter_complex \"setdar=dar=(w/h),setsar=sar=1/1,scale=-2:$HEIGHT,drawtext=fontfile=$FONTDIR/Monaco_Linux.ttf:y=9:x=(w-tw)/2:fontcolor=white:alpha=0.75:shadowcolor=black:shadowx=1:shadowy=1:fontsize=9:r=$FRAMERATE:timecode=\'$TIME:00\',drawtext=fontfile=$FONTDIR/Executive-Regular.otf:x=(main_w)-(text_w)-36:y=main_h-48:fontcolor=white:fontsize=$SIZ*1.3334:text='NFA',format=nv12,hwupload\" -c:v h264_vaapi -qp $CRF -pix_fmt yuv420p -preset fast -c:a aac -bsf:v h264_mp4toannexb -color_primaries bt709 -color_trc bt709 -colorspace bt709 -f mpegts -y \"$OUTPUT\"" >> /tmp/jobs
  
  #echo cat "$OUTPUT >> $OUTPUT_PATH/dump.ts" >> /tmp/jobs2
  
  echo file $OUTPUT >> /tmp/files
  echo $OUTPUT >> /tmp/files2

  SCOUNT_TOTAL=$(( $SCOUNT_TOTAL + $FRAG_L ))
  SCOUNT=$(( $SCOUNT + $FRAG_L ))

  if [ $SCOUNT -gt 59 ]
  then
    SCOUNT=$(( $SCOUNT % 60 ))
    MINS=$(( $MINS + 1 ))
  fi

  if [ $MINS -gt 59 ]
  then
    MINS=0
    HOS=$(( $HOS + 1 ))
  fi



  LOOP_NO=$(( $LOOP_NO + 1 ))
done

parallel --bar --eta --halt 'now,fail=1' -S "$SERVERS" < /tmp/jobs || exit 1
echo Concating $LOOP_NO segments
FIN="$(echo `basename \"$INPUT\"` | awk -F'.' '{print $1}')".mp4

#sudo mount -t tmpfs -o size=16G tmpfs /mnt/tmpfs
# concat using ffmpeg
echo Concating $LOOP_NO segments
while read file; do echo `du -h $file` ; cat $file >> $OUTPUT_PATH/dump.ts ; done < /tmp/files2

echo Stitching $LOOP_NO segments
ffmpeg -i $OUTPUT_PATH/dump.ts -c:a copy -c:v copy -absf aac_adtstoasc -flags global_header -t $DURATION  -movflags +faststart -y "$FIN"

#ffmpeg -f concat -safe 0 -hwaccel auto -i /tmp/files -c:a copy -c:v copy -flags global_header -movflags +faststart -y $FIN

echo Src length: "$DURATION"s
echo Fin length: $(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$FIN")s
