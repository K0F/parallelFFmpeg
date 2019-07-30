#!/bin/sh
ffmpeg -f concat -safe 0 -hwaccel auto -i /tmp/files -c:a copy -c:v copy -bsf:a aac_adtstoasc -y ${1}
