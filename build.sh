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
  gpfjs_package_image=$(e docker_data_img_gpfjs_package)

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
  }

  build_stage "Prepare GPF conda recipies"
  {
    local gpf_dependencies
    export gpf_dependencies=$( grep "=" sources/gpf/environment.yml | sed -E "s/\s+-\s+(.+)=(.+)$/    - \1=\2/g" )
    build_run_local echo "gpf_dependencies: \n$gpf_dependencies"

    local gpf_version
    export gpf_version=$(cat sources/gpf/VERSION)
    build_run_local echo "gpf_version=$gpf_version"

    if [ -z $BUILD_NUMBER ];
    then
      export build_number=0
    else
      export build_number=$BUILD_NUMBER
    fi

    build_run_local echo "build_number=$build_number"

    build_run_local ls -la conda-recipes/
    build_run_local ls -la conda-recipes/gpf_dae/
  
    build_run_local cat conda-recipes/gpf_dae/meta.yaml.template | \
      envsubst > conda-recipes/gpf_dae/meta.yaml

    build_run_local cat conda-recipes/gpf_gpfjs/meta.yaml.template | \
      envsubst > conda-recipes/gpf_gpfjs/meta.yaml

    build_run_local cat conda-recipes/gpf_wdae/meta.yaml.template | \
      envsubst > conda-recipes/gpf_wdae/meta.yaml

  }

  build_stage "Build gpf_dae package"
  {
    build_run_local echo "gpf_version=${gpf_version}"
    build_run_local echo "build_number=${build_number}"

    local iossifovlab_anaconda_base_image_ref
    iossifovlab_anaconda_base_image_ref=$(e docker_img_iossifovlab_anaconda_base)
    
    build_run_ctx_init "container" "$iossifovlab_anaconda_base_image_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_number="${build_number}"

    build_run_container conda build \
      -c defaults -c conda-forge -c iossifovlab -c bioconda \
      conda-recipes/gpf_dae

    build_run_container \
      cp /opt/conda/conda-bld/linux-64/gpf_dae-${gpf_version}-py39_${build_number}.tar.bz2 \
      /wd/builds
  }

  build_stage "Build gpf_wdae package"
  {
    local iossifovlab_anaconda_base_image_ref
    iossifovlab_anaconda_base_image_ref=$(e docker_img_iossifovlab_anaconda_base)

    build_run_ctx_init "container" "$iossifovlab_anaconda_base_image_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_number="${build_number}"

    build_run_container conda build \
      -c defaults -c conda-forge -c iossifovlab -c bioconda \
      conda-recipes/gpf_wdae

    build_run_container \
      cp /opt/conda/conda-bld/linux-64/gpf_wdae-${gpf_version}-py39_${build_number}.tar.bz2 \
      /wd/builds
  }

  build_stage "Build gpf_gpfjs package"
  {
    local iossifovlab_anaconda_base_image_ref
    iossifovlab_anaconda_base_image_ref=$(e docker_img_iossifovlab_anaconda_base)

    build_run_ctx_init "container" "$iossifovlab_anaconda_base_image_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_number="${build_number}"

    build_run_container conda build \
      -c defaults -c conda-forge -c iossifovlab -c bioconda \
      conda-recipes/gpf_gpfjs

    build_run_container \
      cp /opt/conda/conda-bld/linux-64/gpf_gpfjs-${gpf_version}-${build_number}.tar.bz2 \
      /wd/builds
  }


  build_stage "Deploy gpf packages"
  {
    local iossifovlab_anaconda_base_image_ref
    iossifovlab_anaconda_base_image_ref=$(e docker_img_iossifovlab_anaconda_base)

    build_run_ctx_init "container" "$iossifovlab_anaconda_base_image_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_number="${build_number}"

    build_run_container_cp_to /root/ $HOME/.continuum

    build_run_container anaconda upload \
      --force -u iossifovlab \
      --label dev \
      /wd/builds/gpf_dae-${gpf_version}-py39_${build_number}.tar.bz2

    build_run_container anaconda upload \
      --force -u iossifovlab \
      --label dev \
      /wd/builds/gpf_wdae-${gpf_version}-py39_${build_number}.tar.bz2

    build_run_container anaconda upload \
      --force -u iossifovlab \
      --label dev \
      /wd/builds/gpf_gpfjs-${gpf_version}-${build_number}.tar.bz2

  }


}

main "$@"
