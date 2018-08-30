ARG BG_IMAGE_TAG
FROM bucharestgold/centos7-s2i-nodejs:${BG_IMAGE_TAG}
# This image provides a Node.JS environment you can use to build your Modern Web Applications

EXPOSE 8080

ENV OUTPUT_DIR=build \
    NPM_BUILD_COMMAND="npm run build" \
    DEPLOY_DIR=/opt/app-root/output \
    DEPLOY_PORT=8080 \
    DEBUG_PORT=5858 \
    NODE_VERSION=${NODE_VERSION} \
    NPM_VERSION=${NPM_VERSION} \
    SUMMARY="Platform for building Modern Web Applications that use Node.js" \
    DESCRIPTION="Web Application building with Node.js"

LABEL io.k8s.description="$DESCRIPTION" \
      io.openshift.expose-services="8080:http" \
      io.openshift.tags="builder,nodejs" \
      com.redhat.deployments-dir="/opt/app-root/src" \
      com.redhat.dev-mode.port="DEBUG_PORT:5858" \
      maintainer="Lucas Holmquist <lholmqui@redhat.com>" \
      summary="$SUMMARY" \
      description="$DESCRIPTION" \
      version="$NODE_VERSION" \
      name="bucharestgold/centos7-s2i-web-app"

COPY ./s2i/ $STI_SCRIPTS_PATH

USER 1001

# Set the default CMD to print the usage
CMD ${STI_SCRIPTS_PATH}/usage
