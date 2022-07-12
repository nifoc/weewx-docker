FROM python:3 as stage-1

ENV WEEWX_HOME="/home/weewx"
ENV ARCHIVE="weewx-4.8.0.tar.gz"
ENV NEOWX_VERSION="latest"
ENV WDC_VERSION="v1.3.1"

RUN addgroup --system --gid 421 weewx &&\
  adduser --system --uid 421 --ingroup weewx weewx

WORKDIR /tmp
COPY requirements.txt ./

# Python setup
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir --requirement requirements.txt

# WeeWX setup
RUN wget -O "${ARCHIVE}" "http://www.weewx.com/downloads/released_versions/${ARCHIVE}" &&\
  wget -O weewx-interceptor.zip https://github.com/nifoc/weewx-interceptor/archive/refs/heads/feature/ecowitt-fields.zip &&\
  wget -O weewx-forecast.zip https://github.com/chaunceygardiner/weewx-forecast/archive/master.zip &&\
  wget -O neowx-material.zip https://neoground.com/projects/neowx-material/download/${NEOWX_VERSION} &&\
  wget -O weewx-wdc.zip https://github.com/Daveiano/weewx-wdc/releases/download/${WDC_VERSION}/weewx-wdc-${WDC_VERSION}.zip &&\
  tar --extract --gunzip --directory ${WEEWX_HOME} --strip-components=1 --file "${ARCHIVE}" &&\
  mkdir weewx-wdc && unzip weewx-wdc.zip -d weewx-wdc &&\
  chown -R weewx:weewx ${WEEWX_HOME}

WORKDIR ${WEEWX_HOME}

RUN bin/wee_extension --install /tmp/weewx-interceptor.zip &&\
  bin/wee_extension --install /tmp/weewx-forecast.zip &&\
  bin/wee_extension --install /tmp/neowx-material.zip &&\
  bin/wee_extension --install /tmp/weewx-wdc &&\
  mkdir user

COPY entrypoint.sh ./
COPY user/ ./bin/user/

FROM python:3 as stage-2

ENV WEEWX_HOME="/home/weewx"

RUN addgroup --system --gid 421 weewx &&\
  adduser --system --uid 421 --ingroup weewx weewx

RUN apt-get update -qq -y &&\
  DEBIAN_FRONTEND=noninteractive apt-get install -y libusb-1.0-0 gosu busybox-syslogd tzdata nginx-light -qq -y --no-install-recommends &&\
  rm -rf /var/lib/apt/lists/*

WORKDIR ${WEEWX_HOME}

COPY --from=stage-1 /opt/venv /opt/venv
COPY --from=stage-1 ${WEEWX_HOME} ${WEEWX_HOME}

RUN mkdir /data && \
  cp weewx.conf /data

VOLUME ["/data"]

ENV PATH="/opt/venv/bin:$PATH"
ENTRYPOINT ["./entrypoint.sh"]
CMD ["/data/weewx.conf"]
