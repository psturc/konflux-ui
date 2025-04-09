#!/bin/bash

set -x

build_ui_image() {
    echo "Building UI from commit sha ${HEAD_SHA}"
    
    export IMAGE_NAME=localhost/test/test
    export IMAGE_TAG=konflux-ui
    export KONFLUX_UI_IMAGE_REF=${IMAGE_NAME}:${IMAGE_TAG}

    # Update konflux-ui image name and tag in konflux-ci kustomize files
    yq eval --inplace "del(.images[] | select(.name == \"*konflux-ui*\") | .digest)" konflux-ci/ui/core/kustomization.yaml
    yq eval --inplace "(.images[] | select(.name == \"*konflux-ui*\")) |=.newTag=\"${IMAGE_TAG}\"" konflux-ci/ui/core/kustomization.yaml
    yq eval --inplace "(.images[] | select(.name == \"*konflux-ui*\")) |=.newName=\"${IMAGE_NAME}\"" konflux-ci/ui/core/kustomization.yaml

    cd konflux-ui || exit 1

    # TODO: update component name to "konflux-ui"
    export COMPONENT=nodejs-test
    export AGENT_VERSION
    export NODEJS_AGENT_IMAGE=quay.io/konflux-ci/tekton-integration-catalog/sealights-nodejs:latest

    AGENT_VERSION=$(podman run $NODEJS_AGENT_IMAGE /bin/sh -c 'echo ${AGENT_VERSION}')

    podman run --network host --userns=keep-id --group-add keep-groups -v "$PWD:/konflux-ui" --workdir /konflux-ui -e NODE_DEBUG=sl \
        $NODEJS_AGENT_IMAGE \
        /bin/bash -cx "slnodejs prConfig --appName ${COMPONENT} --targetBranch ${TARGET_BRANCH} --repositoryUrl ${FORKED_REPO_URL} --latestCommit ${HEAD_SHA} --pullRequestNumber ${PR_NUMBER} --token ${SEALIGHTS_TOKEN}"

    echo "$SEALIGHTS_TOKEN" > /tmp/sl-token

    podman build --build-arg BSID="$(< buildSessionId)" \
        --build-arg AGENT_VERSION="${AGENT_VERSION}" \
        --secret id=sealights-credentials/token,src=/tmp/sl-token \
        -t ${KONFLUX_UI_IMAGE_REF} \
        -f Dockerfile.sealights .

    podman image save -o konflux-ui.tar ${KONFLUX_UI_IMAGE_REF}
    kind load image-archive konflux-ui.tar -n konflux

    cd .. || exit 1
}


run_test() {
    cd konflux-ui || exit 1

    # default image used if test code is not changed in a PR
    TEST_IMAGE="quay.io/konflux_ui_qe/konflux-ui-tests:latest"

    # monitor memory usage during a test
    while true; do date '+%F_%H:%M:%S' >> mem.log && free -m >> mem.log; sleep 1; done 2>&1 &
    MEM_PID=$!

    # fetch also target branch
    git fetch origin "${TARGET_BRANCH}"

    # Rebuild test image if Containerfile or entrypoint from e2e-tests was changed 
    git diff --exit-code --quiet "origin/${TARGET_BRANCH}" HEAD -- e2e-tests/Containerfile || is_changed_cf=$?
    git diff --exit-code --quiet "origin/${TARGET_BRANCH}" HEAD -- e2e-tests/entrypoint.sh || is_changed_ep=$?

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
        -e CYPRESS_KONFLUX_BASE_URL=https://localhost:9443 \
        -e CYPRESS_USERNAME=${CYPRESS_USERNAME} \
        -e CYPRESS_PASSWORD=${CYPRESS_PASSWORD} \
        -e CYPRESS_GH_TOKEN=${CYPRESS_GH_TOKEN} \
        -e CYPRESS_SL_TOKEN=${SEALIGHTS_TOKEN} \
        -e CYPRESS_SL_BUILD_SESSION_ID=$(< buildSessionId) \
        -e CYPRESS_SL_TEST_STAGE=konflux-ui-e2e"
    TEST_RUN=0

    podman run --network host ${COMMON_SETUP} ${TEST_IMAGE} || TEST_RUN=1
    PODMAN_RETURN_CODE=$?
    if [[ $PODMAN_RETURN_CODE -ne 0 ]]; then
        case $PODMAN_RETURN_CODE in
            255)
                echo "Test took too long, podman exited due to timeout set to 1 hour."
                ;;
            130)
                echo "Podman run was interrupted."
                ;;
            *)
                echo "Podman exited with exit code: ${PODMAN_RETURN_CODE}"
                ;;
        esac
        TEST_RUN=1
    fi

    kubectl logs "$(kubectl get pods -n konflux-ui -o name | grep proxy)" --all-containers=true -n konflux-ui > "$PWD/artifacts/konflux-ui.log"

    # kill the background process monitoring memory usage
    kill $MEM_PID
    cp mem.log "$PWD/artifacts"

    echo "Exiting pr_check.sh with code $TEST_RUN"

    cd ..
    exit $TEST_RUN
}

if [ $# -eq 0 ]; then
    echo "Usage: $0 [build|test]"
    exit 1
fi

case "$1" in
    build)
        echo "Running build process..."
        build_ui_image
        ;;
    test)
        echo "Running test suite..."
        run_test
        ;;
    *)
        echo "Invalid argument: $1"
        echo "Usage: $0 [build|test]"
        exit 1
        ;;
esac

