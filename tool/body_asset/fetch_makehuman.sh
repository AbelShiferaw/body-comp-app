#!/bin/sh
# Downloads the CC0 MakeHuman assets build_body.py needs into $1.
set -e
DIR=${1:-.makehuman}; mkdir -p "$DIR"
B=https://raw.githubusercontent.com/makehumancommunity/makehuman/master
get() { curl -sfL -o "$DIR/$(basename "$1")" "$B/$1"; }
get LICENSE.ASSETS.md
get makehuman/data/3dobjs/base.obj
get makehuman/data/rigs/default_weights.mhw
T=makehuman/data/targets/macrodetails
for s in male female; do
  for r in african asian caucasian; do get $T/$r-$s-young.target; done
  for m in averagemuscle-maxweight averagemuscle-minweight maxmuscle-averageweight minmuscle-averageweight; do
    get $T/universal-$s-young-$m.target
  done
done
echo "MakeHuman assets in $DIR"
