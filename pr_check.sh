#!/bin/bash

# -------------------------------------------
# ----------- RUN UI WITH CHANGES -----------
# -------------------------------------------
echo "Running UI from commit sha ${HEAD_SHA}"
cd konflux-ui

set -x

export COMPONENT NODE_DEBUG BUILD_NAME SL_fileExtensions BUILD_DIR_PATH BABYLON_PLUGINS BSID

# BUILD_NAME="konflux-ui-$(date -u +"%s")"
# TODO: update
COMPONENT=nodejs-test
SL_fileExtensions=".js,.jsx,.ts,.tsx"
BABYLON_PLUGINS="jsx,typescript"
BUILD_DIR_PATH="dist"
SL_BUILD_DIR_PATH="sl_dist"

NODEJS_AGENT_IMAGE=quay.io/konflux-ci/tekton-integration-catalog/sealights-nodejs:latest

podman run --network host --userns=keep-id --group-add keep-groups -v "$PWD:/konflux-ui" --workdir /konflux-ui -e NODE_DEBUG=sl \
    $NODEJS_AGENT_IMAGE \
    /bin/bash -cx "whoami && slnodejs prConfig --appName ${COMPONENT} --targetBranch ${TARGET_BRANCH} --repositoryUrl ${FORKED_REPO_URL} --latestCommit ${HEAD_SHA} --pullRequestNumber ${PR_NUMBER} --token ${SEALIGHTS_TOKEN}"
    # repositoryUrl ?

BSID=$(< buildSessionId)

./connect_to_local_konflux.sh

yarn install

# start the UI from the PR check in background, save logs to file
yarn start > yarn_start_logfile 2>&1 &

YARN_PID=$!

while ! ls ${BUILD_DIR_PATH} &> /dev/null; do
  echo "waiting until the directory ${BUILD_DIR_PATH} is created"
  sleep 5
done

podman run --network host --userns=keep-id --group-add keep-groups -v "$PWD:/konflux-ui" --workdir /konflux-ui -e NODE_DEBUG=sl \
    $NODEJS_AGENT_IMAGE \
    /bin/bash -cx "slnodejs scan --buildsessionidfile buildSessionId --scm git --workspacepath ${BUILD_DIR_PATH} --token ${SEALIGHTS_TOKEN} --outputpath ${SL_BUILD_DIR_PATH} --babylonPlugins ${BABYLON_PLUGINS} --instrumentForBrowsers"


cp -r ${SL_BUILD_DIR_PATH}/* ${BUILD_DIR_PATH}

# podman run --network host --userns=keep-id --group-add keep-groups -v "$PWD:/konflux-ui" --workdir /konflux-ui -e NODE_DEBUG=sl \
#     $NODEJS_AGENT_IMAGE \
#     /bin/bash -cx "slnodejs start --teststage konflux-ui-e2e --buildsessionidfile buildSessionId --token ${SEALIGHTS_TOKEN}"



# -------------------------------------
# ----------- RUN E2E TESTS -----------
# -------------------------------------

# default image used if test code is not changed ina PR
TEST_IMAGE="quay.io/konflux_ui_qe/konflux-ui-tests:latest"

# fetch also target branch
git fetch origin ${TARGET_BRANCH}

# Rebuild test image if Containerfile or entrypoint from e2e-tests was changed 
git diff --exit-code --quiet origin/${TARGET_BRANCH} HEAD -- e2e-tests/Containerfile || is_changed_cf=$?
git diff --exit-code --quiet origin/${TARGET_BRANCH} HEAD -- e2e-tests/entrypoint.sh || is_changed_ep=$?

if [[ ($is_changed_cf -eq 1) || ($is_changed_ep -eq 1) ]]; then
    echo "Containerfile changes detected, rebuilding test image"
    TEST_IMAGE="konflux-ui-tests:pr-$PR_NUMBER"

    cd e2e-tests
    podman build -t "$TEST_IMAGE" . -f Containerfile
    cd ..
else 
    echo "Using latest image from quay."
fi
mkdir artifacts
echo "running tests using image ${TEST_IMAGE}"
COMMON_SETUP="-v $PWD/artifacts:/tmp/artifacts:Z,U \
    -v $PWD/e2e-tests:/e2e:Z,U \
    -e CYPRESS_PR_CHECK=true \
    -e CYPRESS_KONFLUX_BASE_URL=https://localhost:8080 \
    -e CYPRESS_USERNAME=${CYPRESS_USERNAME} \
    -e CYPRESS_PASSWORD=${CYPRESS_PASSWORD} \
    -e CYPRESS_GH_TOKEN=${CYPRESS_GH_TOKEN} \
    -e CYPRESS_SL_TOKEN=${SEALIGHTS_TOKEN} \
    -e CYPRESS_SL_BUILD_SESSION_ID=${BSID} \
    -e CYPRESS_SL_TEST_STAGE=konflux-ui-e2e"

TEST_RUN=0

podman run --network host ${COMMON_SETUP} ${TEST_IMAGE} || TEST_RUN=1

# kill the background process running the UI
kill $YARN_PID
cp yarn_start_logfile $PWD/artifacts

# podman run --network host --userns=keep-id --group-add keep-groups -v "$PWD:/konflux-ui" --workdir /konflux-ui -e NODE_DEBUG=sl \
#     $NODEJS_AGENT_IMAGE \
#     /bin/bash -cx "slnodejs end --buildsessionidfile buildSessionId --token ${SEALIGHTS_TOKEN}"

echo "Exiting pr_check.sh with code $TEST_RUN"

cd ..
exit $TEST_RUN

