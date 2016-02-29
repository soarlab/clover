# Copyright 2016 Marko Dimjašević
#
# This file is part of Clover.
#
# Clover is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# Clover is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with maline.  If not, see <http://www.gnu.org/licenses/>.


FROM debian:stable
MAINTAINER Marko Dimjašević <marko@dimjasevic.net>

ENV DEBIAN_FRONTEND noninteractive

# Add package sources and Stable backports
RUN echo "deb-src http://httpredir.debian.org/debian stable main" >> /etc/apt/sources.list
RUN echo "deb http://mirrors.kernel.org/debian jessie-backports main" >> /etc/apt/sources.list

RUN apt-get update
RUN apt-get install --yes build-essential
RUN apt-get install --yes emacs sudo git python wget

# Create a sudo user "docker"
ENV HOME_DIR /home/docker
RUN adduser --disabled-password docker
RUN adduser docker sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

WORKDIR ${HOME_DIR}
USER docker

# Install LLVM
# A work-around for the ENV command not doing shell expansion.
# Later prepend a needed RUN command with: bash -c 'source build-env && ...'
RUN echo "export LLVM_VERSION=3.4" >> build-env
RUN bash -c 'source build-env && sudo apt-get install --yes clang-${LLVM_VERSION} llvm-${LLVM_VERSION} llvm-${LLVM_VERSION}-dev llvm-${LLVM_VERSION}-tools'

# Get the Whole Program LLVM tool and configure it
RUN git clone https://github.com/travitch/whole-program-llvm.git
RUN echo "export LLVM_COMPILER=clang" >> build-env
RUN bash -c 'source build-env && echo "export LLVM_COMPILER_PATH=$(llvm-config-${LLVM_VERSION} --prefix)/bin" >> build-env'
RUN bash -c 'echo "export PATH=$PATH:${HOME_DIR}/whole-program-llvm" >> build-env'

# Get and install STP, KLEE and their dependencies
RUN bash -c 'source build-env && sudo apt-get install --yes libboost-program-options1.55.0 libgcc1 libstdc++6 minisat libcap2 libffi6 libllvm${LLVM_VERSION} libtinfo5 python python-tabulate'

ENV STP_PKG  stp_2.1.1+dfsg-1_amd64.deb
ENV KLEE_PKG klee_1.1.0-1_amd64.deb
RUN wget https://dimjasevic.net/marko/klee/${STP_PKG}
RUN wget https://dimjasevic.net/marko/klee/${KLEE_PKG}
RUN sudo dpkg -i ${STP_PKG}
RUN sudo dpkg -i ${KLEE_PKG}

USER root
# Remove GCC binaries and replace them with symlinks to LLVM
WORKDIR /usr/bin
ENV GCC_VERSION="4.9"
RUN rm g++-$GCC_VERSION gcc-$GCC_VERSION cpp-$GCC_VERSION
RUN bash -c 'source /home/docker/build-env && ln -s clang++-${LLVM_VERSION} g++-$GCC_VERSION'
RUN bash -c 'source /home/docker/build-env && ln -s clang-${LLVM_VERSION} gcc-$GCC_VERSION'
RUN bash -c 'source /home/docker/build-env && ln -s clang-${LLVM_VERSION} cpp-$GCC_VERSION'

RUN echo "Block the installation of new gcc version"
RUN echo "gcc-${GCC_VERSION} hold" | dpkg --set-selections
RUN echo "cpp-${GCC_VERSION} hold" | dpkg --set-selections
RUN echo "g++-${GCC_VERSION} hold" | dpkg --set-selections


WORKDIR ${HOME_DIR}
USER docker

# Add LLVM IR syntax highlighting for Emacs
RUN mkdir -p ${HOME_DIR}/.emacs.d/lisp
ADD misc/llvm-mode.el ${HOME_DIR}/.emacs.d/lisp/
ADD misc/.emacs ${HOME_DIR}/

# Remove this hardening compiler flag as it's not supported by Clang
ENV DEB_CFLAGS_STRIP "-fstack-protector-strong"
ENV DEB_CXXFLAGS_STRIP "-fstack-protector-strong"
ENV DEB_OBJCFLAGS_STRIP "-fstack-protector-strong"
ENV DEB_OBJCXXFLAGS_STRIP "-fstack-protector-strong"

# Pick a target package and prepare the environment for building
ENV target hostname
ENV target_v_file "/tmp/$target-v"
RUN echo $(apt-cache show $target | grep ^Version | awk -F" " '{print $2}') > $target_v_file
RUN bash -c 'echo "export target_version=$(cat $target_v_file)" >> build-env'
RUN sudo apt-get build-dep --yes $target
RUN apt-get source $target

RUN bash -c 'source ${HOME_DIR}/build-env && cd $target-${target_version} && CC=wllvm CXX=wllvm++ fakeroot debian/rules build'
RUN bash -c 'source ${HOME_DIR}/build-env && cd $target-${target_version} && CC=wllvm CXX=wllvm++ extract-bc $target'
# # The last command produces ${target}.bc, a single linked LLVM bitcode file

ENTRYPOINT bash -c 'source ${HOME_DIR}/build-env && cd $target-${target_version} && klee -libc=uclibc ${target}.bc -I'
