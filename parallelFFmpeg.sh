#!/bin/bash

INPUT="$1"
OUTPUT_PATH=/tmp/chunks
mkdir $OUTPUT_PATH

# length of segment (in seconds)
FRAG_L=10

#get duration of input file and parse decimals
DURATION=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT");
SECS=$(echo $DURATION | awk -F'.' '{print $1}')
FRAG=$(echo $DURATION | awk -F'.' '{print $2}')

#compute number of chunks segemnts
NO_OF_SEGMENTS=$(($SECS/$FRAG_L))
echo total duration "$SECS.$FRAG"s
echo segment length "$FRAG_L"s
echo number of segments $NO_OF_SEGMENTS

#set the length of the last one
REST=$(( $SECS % $FRAG_L )).$FRAG


MINS=0
HOS=0

#
rm -rf $OUTPUT_PATH/*
echo "" > /tmp/jobs
echo "" > /tmp/files

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
  
  #echo $TIME $SEGMENT

  OUTPUT=$OUTPUT_PATH/$(echo `basename $INPUT` | awk -F'.' '{print $1}')_$TIME.mp4
  
  echo "ffmpeg -loglevel panic -ss $TIME -i $INPUT -t $SEGMENT -c:v h264_nvenc -pix_fmt yuv420p -qp 16 -c:a aac -b:a 384k -y $OUTPUT" >> /tmp/jobs
  echo file $OUTPUT >> /tmp/files
  
  SCOUNT_TOTAL=$(( $SCOUNT_TOTAL + $FRAG_L ))
  SCOUNT=$(( $SCOUNT + $FRAG_L ))
  
  if [ $SCOUNT -ge 59 ]
  then
    SCOUNT=$(( $SCOUNT % 60 ))
    MINS=$(( $MINS + 1 ))
  fi

  
  if [ $MINS -ge 59 ]
  then
    MINS=0
    HOS=$(( $HOS + 1 ))
  fi
  LOOP_NO=$(( $LOOP_NO + 1 ))
done

parallel --eta --progress -S "8/:" < /tmp/jobs
FIN="$(echo `basename $INPUT` | awk -F'.' '{print $1}')".mp4
ffmpeg -f concat -safe 0 -i /tmp/files -c:v copy -c:a copy -y $FIN
