FROM python:3.10-bookworm

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=off \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100 \
    AIOHTTP_NO_EXTENSIONS=1 \
    DOCKER=true \
    GIT_PYTHON_REFRESH=quiet

# System dependencies (combined into single layer, cache cleaned at the end)
RUN apt-get update && apt-get upgrade -y && apt-get install --no-install-recommends -y \
    build-essential \
    curl \
    ffmpeg \
    gcc \
    git \
    libavcodec-dev \
    libavdevice-dev \
    libavformat-dev \
    libavutil-dev \
    libcairo2 \
    libmagic1 \
    libswscale-dev \
    openssl \
    openssh-server \
    python3 \
    python3-dev \
    python3-pip \
    s3cmd \
    wkhtmltopdf \
    && curl -sL https://deb.nodesource.com/setup_18.x -o /tmp/nodesource_setup.sh \
    && bash /tmp/nodesource_setup.sh \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/ /var/cache/apt/archives/ /tmp/*

# Create data directory
WORKDIR /data
RUN mkdir -p /data/private

# Copy application source (replaces git clone)
COPY . /data/Heroku
WORKDIR /data/Heroku

# Install Python dependencies
RUN pip install --no-warn-script-location --no-cache-dir -U -r requirements.txt

# Copy and set entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "-m", "heroku", "--root"]
