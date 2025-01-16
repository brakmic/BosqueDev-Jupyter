# Stage 1: Use Bosque as the base for tools and dependencies
FROM brakmic/bosquedev:latest AS bosque-stage

# Stage 2: Build the final image with Jupyter
FROM quay.io/jupyter/base-notebook:latest

# Set environment variables
ARG NONROOT_USER=jovyan
ENV NONROOT_USER=${NONROOT_USER} \
    HOME=/home/${NONROOT_USER} \
    PNPM_HOME=/pnpm \
    PATH=/pnpm:/usr/local/bin:/usr/bin:$PATH \
    BOSQUE_JS_PATH=/workspace/bin/src/cmd/bosque.js \
    TERM=xterm-256color

# Configure default system locale settings
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Switch to root for administrative tasks
USER root

###############################################################################
# Install necessary packages
###############################################################################
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    software-properties-common \
    dirmngr \
    ca-certificates \
    xz-utils \
    sudo \
    nano \
    unzip \
    git \
    git-lfs \
    bash-completion \
    locales \
    && rm -rf /var/lib/apt/lists/*

###############################################################################
# Install Node.js
###############################################################################
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs

###############################################################################
# Configure locales
###############################################################################
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

###############################################################################
# Install nano syntax highlighting
###############################################################################
RUN mkdir -p /usr/share/nano-syntax \
    && curl -fsSL https://raw.githubusercontent.com/scopatz/nanorc/master/install.sh | bash

###############################################################################
# Add non-root to passwordless sudo
###############################################################################
RUN echo "${NONROOT_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${NONROOT_USER} \
&& chmod 0440 /etc/sudoers.d/${NONROOT_USER}

# Copy files and dependencies from the Bosque stage
COPY --from=bosque-stage /workspace /workspace
COPY --from=bosque-stage /pnpm /pnpm

# Copy user configuration files
COPY --from=bosque-stage /home/bosquedev/.bashrc ${HOME}/.bashrc
COPY --from=bosque-stage /home/bosquedev/.profile ${HOME}/.profile
COPY --from=bosque-stage /home/bosquedev/.bash_profile ${HOME}/.bash_profile
COPY --from=bosque-stage /home/bosquedev/.bash_aliases ${HOME}/.bash_aliases

# Recreate the symbolic links in /usr/local/bin with a wrapper script for 'bosque'
RUN echo '#!/bin/bash' > /usr/local/bin/bosque && \
    echo 'node ${BOSQUE_JS_PATH} "$@"' >> /usr/local/bin/bosque && \
    chmod +x /usr/local/bin/bosque && \
    ln -sf /pnpm/pnpm /usr/local/bin/pnpm

RUN pnpm add -g typescript ts-node node-gyp @bosque/jsbrex

# Ensure proper permissions
RUN fix-permissions /workspace /pnpm /usr/local/bin/bosque $HOME

WORKDIR /workspace

# Clone the Bosque kernel
RUN git clone https://github.com/brakmic/jupyterlab_bosque_kernel.git

WORKDIR /workspace/jupyterlab_bosque_kernel

# Install the Bosque kernel
RUN pip install --no-cache-dir . && cd .. && rm -rf jupyterlab_bosque_kernel

WORKDIR /workspace

# Clone the Bosque Syntax extension
RUN git clone https://github.com/brakmic/jupyterlab-bosque-syntax.git

WORKDIR /workspace/jupyterlab-bosque-syntax

# Create empty yarn.lock to isolate project
RUN rm yarn.lock && touch yarn.lock

# Build and verify extension
RUN jlpm install && \
    jlpm build:prod && \
    pip install --no-cache-dir . && \
    # Force rebuild of JupyterLab
    jupyter lab clean && \
    jupyter lab build --dev-build=False --minimize=True && \
    cd .. && rm -rf jupyterlab-bosque-syntax
    
WORKDIR /workspace

# Ensure all configurations are accessible to non-root user
RUN fix-permissions /workspace ${HOME}

# Switch back to non-root user
USER ${NONROOT_USER}

# Set default command to start Jupyter Lab
CMD ["python3", "/usr/local/bin/start-notebook.py"]
