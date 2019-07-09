#!/bin/bash

#names of server machines (see ssh config file / gnu parrallel man pages for more) each node has to have gnu parallel and ffmpeg installed
SERVERS="12/nfaProjekce,12/nfaDTL01,1/:,2/nfaAdela"

#if using multiple machines the path sould point to the same file (same mount point) in network shared folder
INPUT="$1"

#for multiple machines this should point to same location (mount point) on network
OUTPUT_PATH=/mnt/central/TEMP_KRYSTOF/chunks

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
if [ -f /tmp/files ]; then
  rm /tmp/files
fi 
if [ -f /tmp/files2 ]; then
  rm /tmp/files2
fi


# length of segment (in seconds)
FRAG_L=15

#get duration of input file and parse decimals
DURATION=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT");
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

  #echo $TIME $SEGMENT

  OUTPUT=$OUTPUT_PATH/$(echo `basename $INPUT` | awk -F'.' '{print $1}')_$(echo $TIME | tr ':' '_').ts

  echo "ffmpeg -loglevel panic -ss $TIME -i $INPUT -t $SEGMENT -c:v h264_nvenc -pix_fmt yuv420p -qp 16 -preset fast -c:a aac -strict -2 -ac 2 -bsf:v h264_mp4toannexb -f mpegts -y $OUTPUT" >> /tmp/jobs
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

parallel --progress --eta -S "$SERVERS" < /tmp/jobs
FIN="$(echo `basename $INPUT` | awk -F'.' '{print $1}')".mp4

# concat using ffmpeg
echo Concating segments
while read file; do echo `du -h $file` ; cat $file >> $OUTPUT_PATH/dump.ts ; done < /tmp/files2
ffmpeg -i $OUTPUT_PATH/dump.ts -c:a copy -c:v copy -absf aac_adtstoasc -flags global_header -t $DURATION  -movflags +faststart -y $FIN
echo Stitching segments
#ffmpeg -f concat -safe 0 -hwaccel nvdec -i /tmp/files -c:a copy -c:v copy -bsf:a aac_adtstoasc -flags global_header -movflags +faststart -y $FIN

echo Src length: "$DURATION"s
echo Fin length: $(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$FIN")s
