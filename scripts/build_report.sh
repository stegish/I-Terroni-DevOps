#!/usr/bin/env bash
set -euo pipefail

mkdir -p report/build

pandoc report/MSc_group_i.md \
  -o report/build/MSc_group_i.pdf \
  --pdf-engine=xelatex \
  --resource-path=.:report:report/images

test -f report/build/MSc_group_i.pdf
echo "Built report/build/MSc_group_i.pdf"
