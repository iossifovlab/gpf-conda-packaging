#!/bin/bash

shopt -s extdebug
shopt -s inherit_errexit
set -e

. build-scripts/loader-extended.bash

loader_addpath build-scripts/

# shellcheck source=build-scripts/libmain.sh
include libmain.sh
# shellcheck source=build-scripts/libbuild.sh
include libbuild.sh
# shellcheck source=build-scripts/libdefer.sh
include libdefer.sh
# shellcheck source=build-scripts/liblog.sh
include liblog.sh
# shellcheck source=build-scripts/libopt.sh
include libopt.sh

function main() {
  local -A options
  libopt_parse options \
    stage:all preset:fast clobber:allow_if_matching_values build_no:0 \
    generate_jenkins_init:no expose_ports:no -- "$@"

  local preset="${options["preset"]}"
  local stage="${options["stage"]}"
  local clobber="${options["clobber"]}"
  local build_no="${options["build_no"]}"
  local generate_jenkins_init="${options["generate_jenkins_init"]}"
  local expose_ports="${options["expose_ports"]}"

  libmain_init iossifovlab.gpf-conda-packaging gpf_conda_packaging
  libmain_init_build_env \
    clobber:"$clobber" preset:"$preset" build_no:"$build_no" \
    generate_jenkins_init:"$generate_jenkins_init" expose_ports:"$expose_ports" \
    iossifovlab.iossifovlab-gpf-containers

  libmain_save_build_env_on_exit
  libbuild_init stage:"$stage" registry.seqpipe.org

  liblog_verbosity=6

  defer_ret build_run_ctx_reset_all_persistent
  defer_ret build_run_ctx_reset

  # cleanup
  build_stage "Cleanup"
  {
    build_run_ctx_init "container" "ubuntu:20.04"
    defer_ret build_run_ctx_reset

    build_run rm -rvf ./builds ./results ./sources
    build_run_local mkdir -p ./builds ./results ./sources

  }

  local gpf_package_image
  gpf_package_image=$(e docker_data_img_gpf_package)

  local gpfjs_package_image
  gpfjs_package_image=$(e docker_data_img_gpfjs_conda_package)

  local gpf_version
  if ee_exists "gpf_version"; then
    gpf_version="$(ee "gpf_version")"
  fi

  build_stage "Get gpf package"
  {
    # copy gpf package
    build_run_local mkdir -p ./sources/gpf
    build_docker_image_cp_from "$gpf_package_image" ./sources/ /gpf
  }

  build_stage "Get gpfjs package"
  {
    # copy gpf package
    build_run_local mkdir -p ./sources/gpfjs
    build_docker_image_cp_from "$gpfjs_package_image" ./sources/ /gpfjs
    build_docker_image_cp_from "$gpfjs_package_image" ./sources/gpf/wdae/wdae/gpfjs/static/gpfjs/ /gpfjs
  }

  build_stage "Prepare GPF conda recipes"
  {
    local gpf_dependencies
    gpf_dependencies=$(build_run_local bash -c 'grep "=" sources/gpf/environment.yml | sed -E "s/\s+-\s+(.+)=(.+)$/    - \1=\2/g"')

    if [ "$gpf_version" == "" ]; then
      version="$(build_run_local cat sources/gpf/VERSION)"
      if [ "$version" != "" ]; then
          gpf_version=${version}${build_no}
        ee_set "gpf_version" "$gpf_version"
      fi
    fi

    build_run_local ls -la conda-recipes/
    build_run_local ls -la conda-recipes/gpf_dae/
  
    build_run_local dd status=none of=conda-recipes/gpf_dae/meta.yaml <<<"
package:
  name: gpf_dae
  version: $gpf_version

source:
  path: ../../sources/gpf/dae/
build:
  number: $build_no
  script: python setup.py install --single-version-externally-managed --record=record.txt

requirements:
  host:
    - python=3.9

  run:
$gpf_dependencies

test:
  imports:
    - dae

about:
  home: https://github.com/iossifovlab/gpf
  license: MIT License
  license_family: MIT
  license_file: ''
  summary: GPF - Genotypes and Phenotypes in Familes
  description: ''
  doc_url: ''
  dev_url: ''

extra:
  recipe-maintainers: ''
"

    build_run_local dd status=none of=conda-recipes/gpf_gpfjs/meta.yaml <<<"
package:
  name: gpf_gpfjs
  version: $gpf_version

source:
  path: ../../sources/gpfjs
  folder: gpfjs/

build:
  number: $build_no
"

    build_run_local dd status=none of=conda-recipes/gpf_wdae/meta.yaml <<<"

package:
  name: gpf_wdae
  version: $gpf_version

source:
  path: ../../sources/gpf/wdae/
build:
  number: $build_no
  script: python setup.py install --single-version-externally-managed --record=record.txt

requirements:
  host:
    - python=3.9

  run:
    - gpf_dae=$gpf_version
$gpf_dependencies

test:
  imports:
    - wdae
    - users_api

about:
  home: https://github.com/iossifovlab/gpf
  license: MIT License
  license_family: MIT
  license_file: ''
  summary: GPF - Genotypes and Phenotypes in Familes
  description: ''
  doc_url: ''
  dev_url: ''

extra:
  recipe-maintainers: ''
"
  }

  build_stage "Build gpf_dae package"
  {
    build_run_local echo "gpf_version=${gpf_version}"
    build_run_local echo "build_no=${build_no}"

    local iossifovlab_miniconda_base_ref
    iossifovlab_miniconda_base_ref=$(e docker_img_iossifovlab_miniconda_base)
    
    build_run_ctx_init "container" "$iossifovlab_miniconda_base_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_no="${build_no}"
  
    build_run_container conda mambabuild \
      -c defaults -c conda-forge -c iossifovlab -c bioconda \
      conda-recipes/gpf_dae

    build_run_container \
      cp /opt/conda/conda-bld/linux-64/gpf_dae-${gpf_version}-py39_${build_no}.tar.bz2 \
      /wd/builds
  }

  build_stage "Build gpf_gpfjs package"
  {
    local iossifovlab_miniconda_base_ref
    iossifovlab_miniconda_base_ref=$(e docker_img_iossifovlab_miniconda_base)

    build_run_ctx_init "container" "$iossifovlab_miniconda_base_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_no="${build_no}"

    build_run_container conda mambabuild \
      -c defaults -c conda-forge -c iossifovlab -c bioconda \
      conda-recipes/gpf_gpfjs

    build_run_container \
      cp /opt/conda/conda-bld/linux-64/gpf_gpfjs-${gpf_version}-${build_no}.tar.bz2 \
      /wd/builds
  }

  build_stage "Build gpf_wdae package"
  {
    local iossifovlab_miniconda_base_ref
    iossifovlab_miniconda_base_ref=$(e docker_img_iossifovlab_miniconda_base)

    build_run_ctx_init "container" "$iossifovlab_miniconda_base_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_no="${build_no}"

    build_run_container conda mambabuild \
      -c defaults -c conda-forge -c iossifovlab -c bioconda \
      conda-recipes/gpf_wdae

    build_run_container \
      cp /opt/conda/conda-bld/linux-64/gpf_wdae-${gpf_version}-py39_${build_no}.tar.bz2 \
      /wd/builds
  }


  build_stage "Deploy gpf packages"
  {
    local iossifovlab_miniconda_base_ref
    iossifovlab_miniconda_base_ref=$(e docker_img_iossifovlab_miniconda_base)

    build_run_ctx_init "container" "$iossifovlab_miniconda_base_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_no="${build_no}"

    build_run_container_cp_to /root/ $HOME/.continuum
    build_run_container chown root:root -R /root/.continuum

    build_run_container anaconda upload \
      --force -u iossifovlab \
      --label dev \
      /wd/builds/gpf_dae-${gpf_version}-py39_${build_no}.tar.bz2

    build_run_container anaconda upload \
      --force -u iossifovlab \
      --label dev \
      /wd/builds/gpf_wdae-${gpf_version}-py39_${build_no}.tar.bz2

    build_run_container anaconda upload \
      --force -u iossifovlab \
      --label dev \
      /wd/builds/gpf_gpfjs-${gpf_version}-${build_no}.tar.bz2

  }


}

main "$@"
