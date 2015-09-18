#!/bin/bash
export IFS=$'\n'
DIR=$(cd $(dirname $0); pwd)
cd $DIR
CMDNAME=`basename $0`
FILENAME_QUEUE="queue_ehgm.txt"
if [ $# -ne 0 ]; then
    ${FILENAME_QUEUE}=${1}
fi
echo "reading from "${FILENAME_QUEUE}"..."

/usr/bin/perl ehgm.pl ${FILENAME_QUEUE}
