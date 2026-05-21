ARG BUILD_FROM=python:3.9.18-slim-bullseye
FROM ${BUILD_FROM}

# Match upstream cloudcutter deps + add full networkmanager, curl
# (ttyd is not in Bullseye apt; installed as static binary below)
RUN apt-get -qq update && apt-get install -qy --no-install-recommends \
      git hostapd rfkill dnsmasq build-essential libssl-dev iproute2 jq mosquitto iw \
      network-manager openssh-server ca-certificates curl bash procps \
 && rm -rf /var/lib/apt/lists/*

# Install ttyd static aarch64 binary (Bullseye lacks an apt package).
# SHA256 verified against https://github.com/tsl0922/ttyd/releases/download/1.7.7/SHA256SUMS
ARG TTYD_VERSION=1.7.7
ARG TTYD_SHA256=b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165
RUN curl -fsSL -o /usr/local/bin/ttyd \
      "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.aarch64" \
 && echo "${TTYD_SHA256}  /usr/local/bin/ttyd" | sha256sum -c - \
 && chmod +x /usr/local/bin/ttyd \
 && /usr/local/bin/ttyd --version

# Pin to a specific SHA. Use git-init + fetch-by-SHA so we get exact pinning while
# still benefiting from --depth 1 (no full history). Update SHA when intentionally
# bumping; CI/build is otherwise reproducible.
ARG CLOUDCUTTER_REV=7bd6b8b1b0c08d3b7a0929e2bb87dd2a649d7c73
RUN git init /opt/cloudcutter \
 && cd /opt/cloudcutter \
 && git remote add origin https://github.com/tuya-cloudcutter/tuya-cloudcutter \
 && git fetch --depth 1 origin "${CLOUDCUTTER_REV}" \
 && git checkout FETCH_HEAD

# Patch upstream setup_apmode.sh to fix the hostapd channel selection bug:
# upstream reads `iw dev wlan0 info` to pick a channel, which on multi-band
# radios returns the currently-tuned channel (often 5 GHz). But hostapd is
# configured for hw_mode=g (2.4 GHz only), so a 5 GHz value causes AP-DISABLED.
# We replace the assignment with an operator-overridable default of channel 6.
# Pre/post `grep -qx` guards fail the build LOUDLY if upstream changes the
# line, so we never silently no-op a patch.
RUN cd /opt/cloudcutter \
 && grep -qx 'AP_CHANNEL=$(get_ap_channel "$WLAN")' src/setup_apmode.sh \
 && sed -i 's|^AP_CHANNEL=\$(get_ap_channel "\$WLAN")$|AP_CHANNEL="${AP_CHANNEL:-6}"|' src/setup_apmode.sh \
 && grep -qx 'AP_CHANNEL="${AP_CHANNEL:-6}"' src/setup_apmode.sh

# Device profiles + device descriptors live in a separate repo (tuya-cloudcutter.github.io).
# Sparse-checkout so we skip the ~133MB images/ dir. SHA-pinned via fetch-by-SHA.
ARG DEVICE_PROFILES_REV=7af966ad3fc57b0bcb3318c2cac19d1d746ab454
RUN git init /tmp/profiles-repo \
 && cd /tmp/profiles-repo \
 && git remote add origin https://github.com/tuya-cloudcutter/tuya-cloudcutter.github.io \
 && git config core.sparseCheckout true \
 && git sparse-checkout init --no-cone \
 && git sparse-checkout set profiles devices \
 && git fetch --depth 1 --filter=blob:none origin "${DEVICE_PROFILES_REV}" \
 && git checkout FETCH_HEAD \
 && cp -r profiles devices /opt/cloudcutter/device-profiles/ \
 && mkdir -p /opt/cloudcutter/device-profiles/schema \
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

# Persist generated keys to /share/ so they survive addon updates/rebuilds.
# Upstream cloudcutter writes to ./configured-devices (relative); we replace
# the upstream-shipped empty directory with a symlink to /share/.
# The /share path is bind-mounted at runtime; symlink target may not yet exist
# at build time, that's fine — created on first start by run.sh.
RUN rm -rf /opt/cloudcutter/configured-devices \
 && ln -sfn /share/cloudcutter-configured-devices /opt/cloudcutter/configured-devices

COPY run.sh /run.sh
RUN chmod +x /run.sh

ARG BUILD_VERSION
ARG BUILD_ARCH
LABEL \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.type="addon" \
  io.hass.arch="${BUILD_ARCH}"

CMD ["/run.sh"]
