FROM python:3.12.4-slim-bookworm as install

ARG WEEWX_UID=421
ENV WEEWX_HOME="/home/weewx"
ENV WEEWX_VERSION="5.0.2"
ENV ARCHIVE="weewx-${WEEWX_VERSION}.tgz"
ENV WEEWX_WDC_VERSION="v3.5.1"

RUN addgroup --system --gid ${WEEWX_UID} weewx \
  && adduser --system --uid ${WEEWX_UID} --ingroup weewx weewx

# Install installation dependencies
RUN apt-get update -qq -y &&\
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential \
  unzip \
  wget \
  libjpeg62-turbo-dev \
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
RUN wget -nv -O "${ARCHIVE}" "http://www.weewx.com/downloads/released_versions/${ARCHIVE}" &&\
  wget -nv -O weewx-mqtt.zip https://github.com/matthewwall/weewx-mqtt/archive/master.zip &&\
  wget -nv -O weewx-MQTTSubscribe.zip https://github.com/bellrichm/WeeWX-MQTTSubscribe/archive/refs/tags/v2.3.1.zip &&\
  wget -nv -O weewx-forecast.zip https://github.com/chaunceygardiner/weewx-forecast/releases/download/v3.5/weewx-forecast-3.5.zip &&\
  wget -nv -O weewx-GTS.zip https://github.com/roe-dl/weewx-GTS/archive/master.zip &&\
  wget -nv -O weewx-purpleair.zip https://github.com/bakerkj/weewx-purpleair/archive/refs/tags/v0.9.zip &&\
  wget -nv -O weewx-aqi.zip https://github.com/jonathankoren/weewx-aqi/archive/refs/tags/v1.4.1.zip &&\
  wget -nv -O weewx-dwd.zip https://github.com/roe-dl/weewx-DWD/archive/master.zip &&\
  wget -nv -O weewx-wdc.zip https://github.com/Daveiano/weewx-wdc/releases/download/${WEEWX_WDC_VERSION}/weewx-wdc-${WEEWX_WDC_VERSION}.zip

# Extract weewx and (some) plugins
RUN tar --extract --gunzip --directory ${WEEWX_HOME} --strip-components=1 --file "${ARCHIVE}" &&\
  mkdir weewx-dwd && unzip weewx-dwd.zip -d weewx-dwd &&\
  mkdir weewx-wdc && unzip weewx-wdc.zip -d weewx-wdc

# Icons
RUN wget -nv -O icons-dwd.zip "https://www.dwd.de/DE/wetter/warnungen_aktuell/objekt_einbindung/icons/wettericons_zip.zip?__blob=publicationFile&v=3" &&\
  wget -nv -O warnicons-dwd.zip "https://www.dwd.de/DE/wetter/warnungen_aktuell/objekt_einbindung/icons/warnicons_nach_stufen_50x50_zip.zip?__blob=publicationFile&v=2" &&\
  wget -nv -O icons-carbon.zip "https://public-images-social.s3.eu-west-1.amazonaws.com/weewx-wdc-carbon-icons.zip" &&\
  mkdir -p "${WEEWX_HOME}/public_html/dwd/icons" && mkdir -p "${WEEWX_HOME}/public_html/dwd/warn_icons" &&\
  unzip /tmp/icons-dwd.zip -d "${WEEWX_HOME}/public_html/dwd/icons" &&\
  unzip /tmp/icons-carbon.zip -d "${WEEWX_HOME}/public_html/dwd/icons" &&\
  unzip /tmp/warnicons-dwd.zip -d "${WEEWX_HOME}/public_html/dwd/warn_icons"

# Adjust (some) file content and permissions
RUN sed -i -z -e "s|PTH=\"/etc/weewx/skins/Belchertown/dwd\"|PTH=\"/home/weewx/skins/weewx-wdc/dwd\"|g" /tmp/weewx-dwd/weewx-DWD-master/usr/local/bin/wget-dwd &&\
  sed -i -z -e "s|SchilderLZ|SchilderEM|g" /tmp/weewx-dwd/weewx-DWD-master/usr/local/bin/wget-dwd &&\
  sed -i -z -e "s|config = configobj.ConfigObj(\"/etc/weewx/weewx.conf\")|config = configobj.ConfigObj(\"/data/weewx.conf\")|g" /tmp/weewx-dwd/weewx-DWD-master/usr/local/bin/dwd-warnings &&\
  sed -i -z -e "s|#!/usr/bin/python3|#!/usr/bin/env python3|g" /tmp/weewx-dwd/weewx-DWD-master/usr/local/bin/dwd-warnings &&\
  sed -i -z -e "s|#!/usr/bin/python3|#!/usr/bin/env python3|g" /tmp/weewx-dwd/weewx-DWD-master/usr/local/bin/dwd-cap-warnings &&\
  sed -i -z -e "s|#!/usr/bin/python3|#!/usr/bin/env python3|g" /tmp/weewx-dwd/weewx-DWD-master/usr/local/bin/dwd-mosmix &&\
  sed -i -z -e "s|#!/usr/bin/python3|#!/usr/bin/env python3|g" /tmp/weewx-dwd/weewx-DWD-master/usr/local/bin/bbk-warnings &&\
  chmod +x /tmp/weewx-dwd/weewx-DWD-master/usr/local/bin/* &&\
  chown -R weewx:weewx ${WEEWX_HOME}

# weewx setup
WORKDIR ${WEEWX_HOME}
RUN bin/weectl extension install /tmp/weewx-mqtt.zip &&\ 
  bin/weectl extension install /tmp/weewx-MQTTSubscribe.zip &&\
  bin/weectl extension install /tmp/weewx-forecast.zip &&\
  bin/weectl extension install /tmp/weewx-GTS.zip &&\
  bin/weectl extension install /tmp/weewx-purpleair.zip &&\
  bin/weectl extension install /tmp/weewx-aqi.zip &&\
  bin/weectl extension install /tmp/weewx-wdc &&\
  mkdir "${WEEWX_HOME}/skins/weewx-wdc/dwd"

COPY entrypoint.sh ./
COPY --chown=weewx:weewx user/extensions.py ./bin/user/extensions.py

# Included for debugging
RUN echo 'Default Configuration:' &&\
  cat ${WEEWX_HOME}/weewx.conf

FROM python:3.12.4-slim-bookworm as final

ARG WEEWX_UID=421
ENV WEEWX_HOME="/home/weewx"

RUN addgroup --system --gid ${WEEWX_UID} weewx \
  && adduser --system --uid ${WEEWX_UID} --ingroup weewx weewx

# Install runtime dependencies
RUN apt-get update -qq -y &&\
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
  libusb-1.0-0 \
  zlib1g \
  libjpeg62-turbo \
  cron \
  wget \
  gosu \
  busybox-syslogd \
  tzdata \
  -qq -y --no-install-recommends &&\
  rm -rf /var/lib/apt/lists/*

# Copy installation from install stage
WORKDIR ${WEEWX_HOME}
COPY --from=install /opt/venv /opt/venv
COPY --from=install ${WEEWX_HOME} ${WEEWX_HOME}
COPY --from=install /tmp/weewx-dwd/weewx-DWD-master/usr/local/bin/* /usr/local/bin/
COPY --chown=weewx:weewx defaults/ /defaults

RUN mkdir /data && \
  cp weewx.conf /data

VOLUME ["/data"]

ENV PATH="/opt/venv/bin:$PATH"
ENTRYPOINT ["./entrypoint.sh"]
CMD ["/data/weewx.conf"]
