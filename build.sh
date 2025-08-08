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
    iossifovlab.gpf iossifovlab.gpfjs

  libmain_save_build_env_on_exit
  libbuild_init stage:"$stage" registry.seqpipe.org

  liblog_verbosity=6

  defer_ret build_run_ctx_reset_all_persistent
  defer_ret build_run_ctx_reset

  # cleanup
  build_stage "Cleanup"
  {
    build_run_ctx_init "container" "ubuntu:24.04"
    defer_ret build_run_ctx_reset

    build_run rm -rvf ./builds ./results ./sources
    build_run_local mkdir -p ./builds ./results ./sources \
        ./builds/noarch
  }

  local gpf_package_image
  gpf_package_image=$(e docker_data_img_gpf_package)

  local gpfjs_package_image
  gpfjs_package_image=$(e docker_data_img_gpfjs_conda_package)

  local gpf_version
  if ee_exists "gpf_version"; then
    gpf_version="$(ee "gpf_version")"
  fi

  local python_version
  if ee_exists "python_version"; then
    python_version="$(ee "python_version")"
  fi

  local numpy_version
  if ee_exists "numpy_version"; then
    numpy_version="$(ee "numpy_version")"
  fi

  build_stage "Get gpf package"
  {
    echo "gpf"
    # copy gpf package
    build_run_local mkdir -p ./sources/gpf
    build_docker_image_cp_from "$gpf_package_image" ./sources/ /gpf
    
    build_run cp sources/gpf/environment.yml sources/gpf/dae
    build_run cp sources/gpf/environment.yml sources/gpf/wdae

  }

  build_stage "Get gpfjs package"
  {
    echo "gpfjs"
    # copy gpf package
    build_run_local mkdir -p ./sources/gpfjs
    build_docker_image_cp_from "$gpfjs_package_image" ./sources/ /gpfjs
    build_docker_image_cp_from "$gpfjs_package_image" ./sources/gpf/wdae/wdae/gpfjs/static/gpfjs/ /gpfjs
  }

  build_stage "Get GPF version"
  {
    build_run_local pwd

    if [ "$gpf_version" == "" ]; then
      build_run_local cat sources/gpf/VERSION
      version="$(build_run_local cat sources/gpf/VERSION)"
      if [ "$version" != "" ]; then
          gpf_version=${version}
        ee_set "gpf_version" "$gpf_version"
      fi
    fi
  }

  build_stage "Get numpy version"
  {
    if [ "$numpy_version" == "" ]; then
      version="$(build_run_local grep -E 'numpy=(.+)$' -o sources/gpf/environment.yml | sed 's/numpy=\(.\+\)/\1/g')"
      echo "NUMPY version=${version}"
      if [ "$version" != "" ]; then
          numpy_version=$version
        ee_set "numpy_version" "$numpy_version"
      fi
    fi
  }


  build_stage "Get python version"
  {
    if [ "$python_version" == "" ]; then
      version="$(build_run_local grep -E 'python=(.+)$' -o sources/gpf/environment.yml | sed 's/python=\(.\+\)/\1/g')"
      echo "python version=${version}"
      if [ "$version" != "" ]; then
          python_version=$version
        ee_set "python_version" "$python_version"
      fi
    fi
  }

  build_stage "Draw build dependencies"
  {
    build_deps_graph_write_image 'build-env/dependency-graph.svg'
  }

  build_stage "Build gpf_dae package"
  {
    build_run_local echo "gpf_version=${gpf_version}"
    build_run_local echo "build_no=${build_no}"
    build_run_local echo "python_version=${python_version}"

    local iossifovlab_mamba_base_ref
    iossifovlab_mamba_base_ref=$(e docker_img_iossifovlab_mamba_base)

    local -A ctx_build

    build_run_ctx_init ctx:ctx_build "persistent" "container" \
        "$iossifovlab_mamba_base_ref" \
        -e gpf_version="${gpf_version}" \
        -e build_no="${build_no}" \
        -e numpy_version="${numpy_version}" \
        -e python_version="${python_version}"

    defer_ret build_run_ctx_reset ctx:ctx_build

    build_run_container ctx:ctx_build \
      conda mambabuild --numpy ${numpy_version} \
      -c conda-forge -c bioconda -c iossifovlab \
      /wd/conda-recipes/gpf_dae

    build_run_container ctx:ctx_build\
      cp /opt/conda/conda-bld/noarch/gpf_dae-${gpf_version}-py_${build_no}.tar.bz2 \
      /wd/builds/noarch

    build_run_container ctx:ctx_build\
      conda index /wd/builds/

    build_run_ctx_persist ctx:ctx_build

  }

  build_stage "Build GPF packages"
  {
    local iossifovlab_mamba_base_ref
    iossifovlab_mamba_base_ref=$(e docker_img_iossifovlab_mamba_base)

    # Create build contexts for each package
    local -A ctx_spliceai_annotator
    build_run_ctx_init ctx:ctx_spliceai_annotator "container" \
        "$iossifovlab_mamba_base_ref" \
        --gpus all \
        -e gpf_version="${gpf_version}" \
        -e build_no="${build_no}" \
        -e numpy_version="${numpy_version}" \
        -e python_version="${python_version}"
    defer_ret build_run_ctx_reset ctx:ctx_spliceai_annotator

    local -A ctx_rest_client
    build_run_ctx_init ctx:ctx_rest_client "container" "$iossifovlab_mamba_base_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_no="${build_no}" \
      -e numpy_version="${numpy_version}" \
      -e python_version="${python_version}"
    defer_ret build_run_ctx_reset ctx:ctx_rest_client

    local -A ctx_impala_storage
    build_run_ctx_init ctx:ctx_impala_storage "container" "$iossifovlab_mamba_base_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_no="${build_no}" \
      -e numpy_version="${numpy_version}" \
      -e python_version="${python_version}"
    defer_ret build_run_ctx_reset ctx:ctx_impala2_storage

    local -A ctx_impala2_storage
    build_run_ctx_init ctx:ctx_impala2_storage "container" "$iossifovlab_mamba_base_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_no="${build_no}" \
      -e numpy_version="${numpy_version}" \
      -e python_version="${python_version}"
    defer_ret build_run_ctx_reset ctx:ctx_impala_storage

    local -A ctx_vep_annotator
    build_run_ctx_init ctx:ctx_vep_annotator "container" "$iossifovlab_mamba_base_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_no="${build_no}" \
      -e numpy_version="${numpy_version}" \
      -e python_version="${python_version}"
    defer_ret build_run_ctx_reset ctx:ctx_vep_annotator

    local -A ctx_gpfjs
    build_run_ctx_init ctx:ctx_gpfjs "container" "$iossifovlab_mamba_base_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_no="${build_no}" \
      -e numpy_version="${numpy_version}" \
      -e python_version="${python_version}"
    defer_ret build_run_ctx_reset ctx:ctx_gpfjs

    local -A ctx_wdae
    build_run_ctx_init ctx:ctx_wdae "container" "$iossifovlab_mamba_base_ref" \
      -e gpf_version="${gpf_version}" \
      -e build_no="${build_no}" \
      -e numpy_version="${numpy_version}" \
      -e python_version="${python_version}"
    defer_ret build_run_ctx_reset ctx:ctx_wdae


    # Build each package in its own context in parallel
    build_run_container ctx:ctx_spliceai_annotator \
      conda mambabuild \
      -c conda-forge -c bioconda -c file:///wd/builds \
      /wd/conda-recipes/gpf_spliceai_annotator

    build_run_container ctx:ctx_rest_client \
      conda mambabuild --numpy ${numpy_version} \
      -c conda-forge -c bioconda -c file:///wd/builds -c iossifovlab \
      /wd/conda-recipes/gpf_rest_client

    build_run_container ctx:ctx_impala_storage \
      conda mambabuild --numpy ${numpy_version} \
      -c conda-forge -c bioconda -c file:///wd/builds -c iossifovlab \
      /wd/conda-recipes/gpf_impala_storage

    build_run_container ctx:ctx_impala2_storage \
      conda mambabuild --numpy ${numpy_version} \
      -c conda-forge -c bioconda -c file:///wd/builds -c iossifovlab \
      /wd/conda-recipes/gpf_impala2_storage

    build_run_container ctx:ctx_vep_annotator \
      conda mambabuild --numpy ${numpy_version} \
      -c conda-forge -c bioconda -c file:///wd/builds -c iossifovlab \
      /wd/conda-recipes/gpf_vep_annotator

    build_run_container ctx:ctx_gpfjs \
      conda mambabuild --numpy ${numpy_version} \
      -c conda-forge -c bioconda -c iossifovlab \
      /wd/conda-recipes/gpf_gpfjs

    build_run_container ctx:ctx_wdae \
      conda mambabuild --numpy ${numpy_version} \
      -c conda-forge -c bioconda -c file:///wd/builds -c iossifovlab \
      /wd/conda-recipes/gpf_wdae

    # Copy conda packages to the builds directory
    build_run_container ctx:ctx_spliceai_annotator \
      cp /opt/conda/conda-bld/noarch/gpf_spliceai_annotator-${gpf_version}-py_${build_no}.tar.bz2 \
      /wd/builds/noarch

    build_run_container ctx:ctx_rest_client \
      cp /opt/conda/conda-bld/noarch/gpf_rest_client-${gpf_version}-py_${build_no}.tar.bz2 \
      /wd/builds/noarch

    build_run_container ctx:ctx_impala_storage \
      cp /opt/conda/conda-bld/noarch/gpf_impala_storage-${gpf_version}-py_${build_no}.tar.bz2 \
      /wd/builds/noarch

    build_run_container ctx:ctx_impala2_storage \
      cp /opt/conda/conda-bld/noarch/gpf_impala2_storage-${gpf_version}-py_${build_no}.tar.bz2 \
      /wd/builds/noarch

    build_run_container ctx:ctx_vep_annotator \
      cp /opt/conda/conda-bld/noarch/gpf_vep_annotator-${gpf_version}-py_${build_no}.tar.bz2 \
      /wd/builds/noarch

    build_run_container ctx:ctx_gpfjs \
      cp /opt/conda/conda-bld/noarch/gpf_gpfjs-${gpf_version}-${build_no}.tar.bz2 \
      /wd/builds/noarch

    build_run_container ctx:ctx_wdae \
      cp /opt/conda/conda-bld/noarch/gpf_wdae-${gpf_version}-py_${build_no}.tar.bz2 \
      /wd/builds/noarch

    # Index the conda channel
    build_run_container ctx:ctx_build \
      conda index /wd/builds/

  }



  build_stage "Build gpf_federation package"
  {
    build_run_container ctx:ctx_build\
      conda mambabuild --numpy ${numpy_version} \
      -c conda-forge -c bioconda -c file:///wd/builds -c iossifovlab \
      conda-recipes/gpf_federation

    build_run_container ctx:ctx_build\
      cp /opt/conda/conda-bld/noarch/gpf_federation-${gpf_version}-py_${build_no}.tar.bz2 \
      /wd/builds/noarch

    build_run_container ctx:ctx_build\
      conda index /wd/builds/
  }

  build_stage "Deploy gpf packages"
  {
    build_run_container ctx:ctx_build\
      conda index /wd/builds/
    build_run_container ctx:ctx_build\
      tar czvf /wd/results/conda-channel.tar.gz \
          --exclude .cache \
          --transform "s,^.,conda-channel," \
          -C builds/ .

    local image_name="gpf-conda-packaging-channel"
    build_docker_data_image_create_from_tarball "${image_name}" <(
      build_run_local tar cvf - \
          --exclude .cache \
          --transform "s,^.,conda-channel," \
          -C builds/ .
    )

  }


}

main "$@"
