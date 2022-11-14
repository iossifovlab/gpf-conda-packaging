
GPFJS=$(python -c "import os; import gpfjs; print(os.path.dirname(gpfjs.__file__))")

rm -fr ${GPFJS}/static/gpfjs/gpfjs
