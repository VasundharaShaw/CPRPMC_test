FROM python:3.10-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    sqlite3 \
    curl \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install Docker
RUN curl -fsSL https://get.docker.com | sh

# Install Jupyter first - bare minimum for Binder to work
RUN pip install --no-cache-dir notebook jupyterlab

# Install pipeline dependencies
RUN pip install --no-cache-dir \
    jupyter-repo2docker \
    GitPython \
    nbconvert \
    nbdime \
    nbformat \
    nbclient \
    matplotlib \
    numpy \
    pandas \
    scipy \
    seaborn \
    requests

# Required for Binder/NFDI
ARG NB_USER=jovyan
ARG NB_UID=1000
ENV USER=${NB_USER}
ENV HOME=/home/${NB_USER}

RUN adduser --disabled-password \
    --gecos "Default user" \
    --uid ${NB_UID} \
    ${NB_USER}

WORKDIR ${HOME}
