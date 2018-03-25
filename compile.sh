#!/bin/bash

if [ ! -e out ]; then
    mkdir out
fi

for i in progs/*.qc; do
    f=$(basename $i | cut -d. -f1)
    echo $f
    lua5.3 run.lua $i > out/$f.lua
done

cp qwprogs.lua out/
