#!/bin/bash -euo

function gpfjs_install
{
  ls -lh
  ls -lh gpfjs

  # GPFJS=$(python -c "import os; import gpfjs; print(os.path.dirname(gpfjs.__file__))")
  # echo "GPFJS=${GPFJS}"

  # rm -rf ${GPFJS}/static/gpfjs
  # mkdir -p ${GPFJS}/static
  # mv * ${GPFJS}/static/
  mkdir -p ${INSTALL_DIR}/gpfjs
  mv -v gpfjs/*  ${INSTALL_DIR}/gpfjs/

}

export INSTALL_DIR=${PREFIX}
echo $PREFIX
echo "INSTALL_DIR=${INSTALL_DIR}"

gpfjs_install


for CHANGE in "activate" "deactivate"
do
    mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
    cp "${RECIPE_DIR}/scripts/${CHANGE}.sh" "${PREFIX}/etc/conda/${CHANGE}.d/${PKG_NAME}_${CHANGE}.sh"
done
