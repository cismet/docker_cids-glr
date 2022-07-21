FROM gitlab/gitlab-runner:v15.2.0

# STUFF
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections \
    && apt-get update \
    && apt-get -y --no-install-recommends install unzip

# JAVA
RUN apt-get -y --no-install-recommends install default-jdk

# NODEJS
RUN curl -sL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get -y --no-install-recommends install nodejs 

# CSCONF
LABEL csonf_build=202207211632
RUN git clone https://github.com/cismet/cs-conf.git /usr/local/src \
    && cd /usr/local/src \
    && npm install -g @babel/node @babel/core \
    && npm install @babel/cli @babel/preset-env --save-dev \
    && npm run build \
    && npm install -g

# RES_CTL
COPY client-res_ctl.sh /client-res_ctl.sh

# CLEANUP
RUN rm -rf /var/lib/apt/lists/*

LABEL maintainer="Jean-Michel Ruiz <jean.ruiz@cismet.de>"