FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    curl \
    autoconf \
    flex \
    bison \
    libfl-dev \
    zlib1g-dev \
    help2man \
    perl \
    && rm -rf /var/lib/apt/lists/*

# Verilator 5, built from source.
#
# Why not `apt-get install verilator`: Ubuntu 22.04 ships 4.038, whose
# SystemVerilog support is too limited for the DPI wrapper in src/dpi/.
# Why not bump the base image to Ubuntu 24.04 (which packages Verilator 5.020):
# that would move us to GCC 13, and SystemC 2.3.4 predates it — its headers are
# missing includes that GCC 13 now requires. Building Verilator from source
# keeps the known-good SystemC build untouched. Costs ~3-5 min, cached in the
# image afterwards.
ENV VERILATOR_VERSION=v5.028
RUN git clone --depth 1 --branch ${VERILATOR_VERSION} \
        https://github.com/verilator/verilator /tmp/verilator \
    && cd /tmp/verilator \
    && autoconf \
    && ./configure \
    && make -j$(nproc) \
    && make install \
    && rm -rf /tmp/verilator

# Pre-compile SystemC 2.3.4 so project builds skip the download step
ENV SYSTEMC_HOME=/opt/systemc
RUN curl -L https://github.com/accellera-official/systemc/archive/refs/tags/2.3.4.tar.gz \
        | tar xz -C /tmp \
    && cmake -S /tmp/systemc-2.3.4 -B /tmp/systemc-build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_STANDARD=17 \
        -DCMAKE_INSTALL_PREFIX=${SYSTEMC_HOME} \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DBUILD_SOURCE_DOCUMENTATION=OFF \
    && cmake --build /tmp/systemc-build -j$(nproc) \
    && cmake --install /tmp/systemc-build \
    && rm -rf /tmp/systemc-2.3.4 /tmp/systemc-build
