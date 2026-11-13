ARG client=mariadb

FROM oraclelinux:9 AS oracle
RUN dnf install -y gcc gcc-c++ make git curl-minimal tar xz && \
    dnf install -y https://repo.mysql.com/mysql84-community-release-el9-1.noarch.rpm && \
    dnf install -y --nogpgcheck mysql-community-devel mysql-community-client

FROM ubuntu:24.04 AS mariadb
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    gcc g++ make git curl ca-certificates xz-utils libmariadb-dev libmariadb-dev-compat mariadb-client

FROM ${client} AS tests
ARG nim_version=2.2.12
RUN curl -fsSL https://nim-lang.org/download/nim-${nim_version}-linux_x64.tar.xz | tar -xJ -C /opt
ENV PATH=/opt/nim-${nim_version}/bin:$PATH
WORKDIR /src
COPY src src
COPY tests tests
COPY .github/mysql/test.sh .github/mysql/test.sh
ENTRYPOINT ["sh", ".github/mysql/test.sh"]
