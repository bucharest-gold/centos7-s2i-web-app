#!/bin/bash
#
# The 'run' performs a simple test that verifies that STI image.
# The main focus here is to excersise the STI scripts.
#
# IMAGE_NAME specifies a name of the candidate image used for testing.
# The image has to be available before this script is executed.
#
BUILDER=${BUILDER}
NODE_VERSION=${NODE_VERSION}

APP_IMAGE="$(echo ${BUILDER} | cut -f 1 -d':')-testapp"

test_dir=`dirname ${BASH_SOURCE[0]}`
image_dir="${test_dir}/.."
cid_file=`date +%s`$$.cid

# Since we built the candidate image locally, we don't want S2I attempt to pull
# it from Docker hub
s2i_args="--pull-policy never "

# TODO: This should be part of the image metadata
test_port=8080

image_exists() {
  docker inspect $1 &>/dev/null
}

container_exists() {
  image_exists $(cat $cid_file)
}

run_s2i_build() {
  echo "Running s2i build ${s2i_args} ${test_dir}/test-react-app ${BUILDER} ${APP_IMAGE}"
  s2i build ${s2i_args} --exclude "(^|/)node_modules(/|$)" ${test_dir}/test-react-app ${BUILDER} ${APP_IMAGE}
}

run_s2i_build_incremental() {
  echo "Running s2i build ${s2i_args} ${test_dir}/test-react-app ${BUILDER} ${APP_IMAGE} --incremental=true"
  s2i build ${s2i_args} --exclude "(^|/)node_modules(/|$)" ${test_dir}/test-react-app ${BUILDER} ${APP_IMAGE} --incremental=true
}

prepare() {
  if ! image_exists ${BUILDER}; then
    echo "ERROR: The image ${BUILDER} must exist before this script is executed."
    exit 1
  fi
}

run_test_application() {
  echo "Starting test application ${APP_IMAGE}..."
  docker run -d --cidfile=${cid_file} -p ${test_port}:${test_port} $1 ${APP_IMAGE}
}

cleanup() {
  if [ -f $cid_file ]; then
    if container_exists; then
      cid=$(cat $cid_file)
      docker stop $cid
      exit_code=`docker inspect --format="{{ .State.ExitCode }}" $cid`
      echo "Container exit code = $exit_code"
      # Only check the exist status for non DEV_MODE
      if [ "$1" == "false" ] &&  [ "$exit_code" != "222" ] ; then
        echo "ERROR: The exist status should have been 222."
        exit 1
      fi
    fi
  fi
  cids=`ls -1 *.cid 2>/dev/null | wc -l`
  if [ $cids != 0 ]
  then
    rm *.cid
  fi
}

check_result() {
  local result="$1"
  if [[ "$result" != "0" ]]; then
    echo "S2I image '${BUILDER}' test FAILED (exit code: ${result})"
    cleanup
    exit $result
  fi
}

wait_for_cid() {
  local max_attempts=20
  local sleep_time=2
  local attempt=1
  local result=1
  while [ $attempt -le $max_attempts ]; do
    [ -f $cid_file ] && [ -s $cid_file ] && break
    echo "Waiting for container start..."
    attempt=$(( $attempt + 1 ))
    sleep $sleep_time
  done
}

test_s2i_usage() {
  echo "Testing 's2i usage'..."
  s2i usage ${s2i_args} ${BUILDER} &>/dev/null
}

test_docker_run_usage() {
  echo "Testing 'docker run' usage..."
  docker run ${BUILDER} &>/dev/null
}

test_connection() {
  echo "Testing HTTP connection..."
  local max_attempts=30
  local sleep_time=2
  local attempt=1
  local result=1
  while [ $attempt -le $max_attempts ]; do
    echo "Sending GET request to http://localhost:${test_port}/"
    response_code=$(curl -s -w %{http_code} -o /dev/null http://localhost:${test_port}/)
    status=$?
    if [ $status -eq 0 ]; then
      if [ $response_code -eq 200 ]; then
	result=0
      fi
      break
    fi
    attempt=$(( $attempt + 1 ))
    sleep $sleep_time
  done
  return $result
}

test_node_version() {
  local run_cmd="node --version"
  local expected="v${NODE_VERSION}"

  echo "Checking nodejs runtime version ..."
  out=$(docker run ${BUILDER} /bin/bash -c "${run_cmd}")
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[/bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
  out=$(docker exec $(cat ${cid_file}) /bin/bash -c "${run_cmd}" 2>&1)
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
  out=$(docker exec $(cat ${cid_file}) /bin/sh -ic "${run_cmd}" 2>&1)
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/sh -ic "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

test_directory_permissions() {
  local run_cmd="echo 'hello world' > public/index.html && cat public/index.html"
  local expected="hello world"

  echo "Checking directory writability ..."
  out=$(docker exec $(cat ${cid_file}) /bin/bash -c "${run_cmd}")
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

test_post_install() {
  local run_cmd="ls public/"
  local expected="index.html"

  echo "Checking post install ..."
  out=$(docker exec $(cat ${cid_file}) /bin/bash -c "${run_cmd}")
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

test_development_dependencies() {
  local run_cmd="ls -d node_modules/tape"
  local expected="tape"

  echo "Checking development dependencies ..."
  out=$(docker exec $(cat ${cid_file}) /bin/bash -c "${run_cmd}")
  if ! echo "${out}" | grep -q "${expected}"; then
    echo "ERROR[exec /bin/bash -c "${run_cmd}"] Expected '${expected}', got '${out}'"
    return 1
  fi
}

# Build the application image twice to ensure the 'save-artifacts' and
# 'restore-artifacts' scripts are working properly
prepare
run_s2i_build
check_result $?

run_s2i_build_incremental
check_result $?

# Verify the 'usage' script is working properly when running the base image with 's2i usage ...'
test_s2i_usage
check_result $?

# Verify the 'usage' script is working properly when running the base image with 'docker run ...'
test_docker_run_usage
check_result $?

# Verify that the HTTP connection can be established to test application container
run_test_application

# Wait for the container to write it's CID file
wait_for_cid

test_directory_permissions
check_result $?

test_post_install
check_result $?

test_node_version
check_result $?

test_connection
check_result $?

# The argument to clean up is the DEV_MODE
cleanup true
if image_exists ${APP_IMAGE}; then
  docker rmi -f ${APP_IMAGE}
  # echo "<><><><><><><><><><><> NOT CLEANING UP åå<><><><><><><><><><><>"
fi

echo "Success!"
