ARG BUILD_FROM=python:3.9.18-slim-bullseye
FROM ${BUILD_FROM}

# Match upstream cloudcutter deps + add full networkmanager, curl
# (ttyd is not in Bullseye apt; installed as static binary below)
RUN apt-get -qq update && apt-get install -qy --no-install-recommends \
      git hostapd rfkill dnsmasq build-essential libssl-dev iproute2 mosquitto iw \
      network-manager ca-certificates curl bash procps \
 && rm -rf /var/lib/apt/lists/*

# Install ttyd static aarch64 binary (Bullseye lacks an apt package)
ARG TTYD_VERSION=1.7.7
RUN curl -fsSL -o /usr/local/bin/ttyd \
      "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.aarch64" \
 && chmod +x /usr/local/bin/ttyd \
 && /usr/local/bin/ttyd --version

ARG CLOUDCUTTER_REV=main
RUN git clone https://github.com/tuya-cloudcutter/tuya-cloudcutter /opt/cloudcutter \
 && cd /opt/cloudcutter && git checkout "${CLOUDCUTTER_REV}"

# Device profiles + device descriptors live in a separate repo (tuya-cloudcutter.github.io).
# Sparse-checkout so we skip the ~133MB images/ dir.
ARG DEVICE_PROFILES_REV=master
RUN git clone --depth 1 --filter=blob:none --sparse \
      https://github.com/tuya-cloudcutter/tuya-cloudcutter.github.io /tmp/profiles-repo \
 && cd /tmp/profiles-repo \
 && git sparse-checkout set profiles devices \
 && cp -r profiles devices /opt/cloudcutter/device-profiles/ \
 && rm -rf /tmp/profiles-repo \
 && echo "device-profiles populated:" \
 && ls /opt/cloudcutter/device-profiles/profiles | wc -l && echo "profiles" \
 && ls /opt/cloudcutter/device-profiles/devices | wc -l && echo "devices"

# Pipfile is in src/ - install exactly as upstream
RUN pip install --upgrade pipenv \
 && cd /opt/cloudcutter/src && PIPENV_VENV_IN_PROJECT=1 pipenv install --deploy

# Symlink /work -> /opt/cloudcutter (some upstream paths assume /work)
RUN ln -s /opt/cloudcutter /work

WORKDIR /opt/cloudcutter

COPY run.sh /run.sh
COPY cc-wrap.py /opt/cloudcutter/cc-wrap.py
RUN chmod +x /run.sh /opt/cloudcutter/cc-wrap.py

ARG BUILD_VERSION
ARG BUILD_ARCH
LABEL \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.type="addon" \
  io.hass.arch="${BUILD_ARCH}"

CMD ["/run.sh"]
