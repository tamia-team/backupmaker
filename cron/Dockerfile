FROM alpine:latest

ENV GIT_USERNAME="tamia-team" \
    GIT_REPOSITORY="team-tamia-oss-backupmaker" \
    GIT_BRANCH="dev" \
    SCRIPT_PATH="mongo/backupmaker.mongo.sh" 

ENV WORKDIR="/app" \
    DIR_RELATIVE_BACKUPS="backups" \
    DIR_RELATIVE_BIN="bin" \ 
ENV DIR_BACKUPS="${WORKDIR}/${DIR_RELATIVE_BACKUPS}" \ 
    DIR_BIN="${WORKDIR}/${DIR_RELATIVE_BIN}" \ 
    CRON_SCHEDULE="* * * * *" \
ENV SCRIPT_URL "https://github.com/${GIT_USERNAME}/${GIT_REPOSITORY}/raw/${GIT_BRANCH}/${SCRIPT_PATH}"

WORKDIR /app

RUN apk --no-cache add curl bash \
    && mkdir -p ${DIR_BIN} ${DIR_BACKUPS} \
    && export SCRIPT_NAME=$(echo "${SCRIPT_URL}" | sed 's/.*\///') \
    && export SCRIPT_FILENAME="${DIR_BIN}/${SCRIPT_NAME}" \
    && curl -o ${SCRIPT_FILENAME} ${SCRIPT_URL} \
    && chmod +x "${SCRIPT_FILENAME}" \
    && echo "${CRON_SCHEDULE} ${SCRIPT_FILENAME} \"$@\"" > /etc/crontabs/root \ 
    && touch /var/log/cron.log \
    && ln -sf /dev/stdout /var/log/cron.log

CMD ["crond", "-f"]

