FROM python:3.10.5-slim-bullseye as install

ARG WEEWX_UID=421
ENV WEEWX_HOME="/home/weewx"
ENV WEEWX_VERSION="4.8.0"
ENV ARCHIVE="weewx-${WEEWX_VERSION}.tar.gz"
ENV WEEWX_WDC_VERSION="v1.3.1"

RUN addgroup --system --gid ${WEEWX_UID} weewx \
  && adduser --system --uid ${WEEWX_UID} --ingroup weewx weewx

# Install installation dependencies
RUN apt-get update -qq -y &&\
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential \
  unzip \
  wget \
  zlib1g-dev \
  -qq -y --no-install-recommends &&\
  rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
COPY requirements.txt ./

# Python setup
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir --requirement requirements.txt

# Download weewx and plugins
RUN wget -O "${ARCHIVE}" "http://www.weewx.com/downloads/released_versions/${ARCHIVE}" &&\
  wget -O weewx-interceptor.zip https://github.com/nifoc/weewx-interceptor/archive/refs/heads/feature/ecowitt-fields.zip &&\
  wget -O weewx-forecast.zip https://github.com/chaunceygardiner/weewx-forecast/archive/master.zip &&\
  wget -O weewx-wdc.zip https://github.com/Daveiano/weewx-wdc/releases/download/${WEEWX_WDC_VERSION}/weewx-wdc-${WEEWX_WDC_VERSION}.zip

# Extract weewx and (some) plugins
RUN tar --extract --gunzip --directory ${WEEWX_HOME} --strip-components=1 --file "${ARCHIVE}" &&\
  mkdir weewx-wdc && unzip weewx-wdc.zip -d weewx-wdc

# weewx setup
RUN chown -R weewx:weewx ${WEEWX_HOME}
WORKDIR ${WEEWX_HOME}
RUN bin/wee_extension --install /tmp/weewx-interceptor.zip &&\
  bin/wee_extension --install /tmp/weewx-forecast.zip &&\
  bin/wee_extension --install /tmp/weewx-wdc &&\
  mkdir user
COPY entrypoint.sh ./
COPY --chown=weewx:weewx user/ ./bin/user/

FROM python:3.10.5-slim-bullseye as final

ARG WEEWX_UID=421
ENV WEEWX_HOME="/home/weewx"

RUN addgroup --system --gid ${WEEWX_UID} weewx \
  && adduser --system --uid ${WEEWX_UID} --ingroup weewx weewx

# Install runtime dependencies
RUN apt-get update -qq -y &&\
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
  libusb-1.0-0 \
  zlib1g \
  gosu \
  busybox-syslogd \
  tzdata \
  nginx-light \
  -qq -y --no-install-recommends &&\
  rm -rf /var/lib/apt/lists/*

# Copy installation from install stage
WORKDIR ${WEEWX_HOME}
COPY --from=install /opt/venv /opt/venv
COPY --from=install ${WEEWX_HOME} ${WEEWX_HOME}

RUN mkdir /data && \
  cp weewx.conf /data

VOLUME ["/data"]

ENV PATH="/opt/venv/bin:$PATH"
ENTRYPOINT ["./entrypoint.sh"]
CMD ["/data/weewx.conf"]
