
echo "Deactivagint gpf_gpfjs..."

GPFJS=$(python -c "import os; import gpfjs; print(os.path.dirname(gpfjs.__file__))")
echo "GPFJS  =${GPFJS}"
echo "PREFIX =${CONDA_PREFIX}"

rm -fr ${GPFJS}/static/gpfjs/gpfjs
