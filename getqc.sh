#!/bin/bash

scriptdir=$(dirname $0)
eval outputfile=$scriptdir/full.qc
cd $scriptdir/progs

rm -f $outputfile
touch $outputfile

for line in $(cat progs.src)
do
	[[ $line == *.qc* ]] && cat $(echo $line | sed 's/\r$//') >> $outputfile
done

cd - > /dev/null
