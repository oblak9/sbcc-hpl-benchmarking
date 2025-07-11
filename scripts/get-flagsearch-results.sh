cd ~/atlas-$1/tune/blas/gemm
grep 'BEST FLAGS GIVE MFLOP=' fs_d_* | sed 's/^.*=//' | cut -d'(' -f1 | sed 's/\./,/'
tail -n 2 fs_d_* | grep -v == | grep . | sed 's/^ *//g'