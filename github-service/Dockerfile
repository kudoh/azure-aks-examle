FROM gradle:jdk11 as build

ENV BUILD_DIR=/src
RUN mkdir -p ${BUILD_DIR}
WORKDIR ${BUILD_DIR}

COPY . ${BUILD_DIR}

RUN gradle assemble

FROM adoptopenjdk/openjdk11:alpine-slim as prod

ENV APP_DIR=/usr/local/app
RUN mkdir -p ${APP_DIR}

COPY --from=build /src/build/libs/github-service.jar ${APP_DIR}/
COPY applicationinsights-agent-2.5.0.jar AI-Agent.xml ${APP_DIR}/

EXPOSE 8080

ENTRYPOINT [ "java", "-Xmx512M", "-Xms512M", "-javaagent:/usr/local/app/applicationinsights-agent-2.5.0.jar", \
             "-jar", "/usr/local/app/github-service.jar"]
