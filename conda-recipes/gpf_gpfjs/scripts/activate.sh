
echo "Activagint gpf_gpfjs..."

export GPFJS=$(python -c "import os; import gpfjs; print(os.path.dirname(gpfjs.__file__))")
echo "GPFJS  =${GPFJS}"
echo "PREFIX =${CONDA_PREFIX}"

rm -f ${GPFJS}/static/gpfjs/gpfjs
ln -s ${CONDA_PREFIX}/gpfjs ${GPFJS}/static/gpfjs/
