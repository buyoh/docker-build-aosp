ARG DIST_CODENAME=focal
# Pin the base image (ubuntu:focal). A tag is ignored if a digest is given,
# so update the digest together with DIST_CODENAME.
ARG UBUNTU_DIGEST=sha256:80ef4a44043dec4490506e6cc4289eeda2d106a70148b74b5ae91ee670e9c35d
FROM ubuntu@$UBUNTU_DIGEST

ARG DIST_CODENAME=focal
ARG UBUNTU_APT_URL=http://archive.ubuntu.com/ubuntu/

COPY ./configure-apt.sh /configure-apt.sh
COPY ./clean-after-apt.sh /clean-after-apt.sh

RUN set -eux \
  && export DEBIAN_FRONTEND=noninteractive \
  && UBUNTU_APT_URL=$UBUNTU_APT_URL DIST_CODENAME=$DIST_CODENAME . /configure-apt.sh \
  && apt-get update -qq \
  && apt-get install -y -qq \
    apt-utils libc6 libc6-dev \
  && apt-get install -y -qq \
    # util
    wget git sudo nano coreutils \
    # aosp
    libssl-dev python3 python-mako make \
    git-core gnupg flex bison build-essential zip curl zlib1g-dev gcc-multilib g++-multilib \
    libncurses5 lib32ncurses5-dev x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig \
    python bc \
    python3-distutils pkg-config \
    python3.9 \
    # kernel
    rsync \
  && apt-get install -y -qq gcc-arm-linux-gnueabihf gcc-aarch64-linux-gnu \
  # Use 3.9
  && (cd /usr/bin && rm python3 && ln -s python3.9 python3) \
  # repo manual install
  && export REPO=$(mktemp /tmp/repo.XXXXXXXXX) \
  && curl -o ${REPO} https://storage.googleapis.com/git-repo-downloads/repo \
  && gpg --recv-key 8BB9AD793E8E6153AF0F9A4416530D5E920F5C65 \
  && curl -s https://storage.googleapis.com/git-repo-downloads/repo.asc | gpg --verify - ${REPO} && install -m 755 ${REPO} /usr/local/bin/repo \
  # pip3
  && curl https://bootstrap.pypa.io/pip/3.9/get-pip.py -o /tmp/get-pip.py \
  && python3 /tmp/get-pip.py pip==24.2 \
  # meson and ninja affect the mesa3d build outputs
  && pip3 install meson==1.5.2 mako==1.3.5 MarkupSafe==2.1.5 ninja==1.11.1.1 \
  # clean up
  && . /clean-after-apt.sh
# workaround: use python3 for repo
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1

COPY ./entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "sh", "/entrypoint.sh" ]
CMD []
