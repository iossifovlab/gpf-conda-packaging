#!/bin/bash -euo

function gpfjs_install
{
  ls -lh
  ls -lh gpfjs

  mkdir -p ${INSTALL_DIR}/gpfjs
  mv -v gpfjs/*  ${INSTALL_DIR}/gpfjs/

}

export INSTALL_DIR=${PREFIX}
gpfjs_install
