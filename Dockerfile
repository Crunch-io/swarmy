# A test harness for testing the bootstrap script
FROM ubuntu:precise

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -q && apt-get upgrade -qy && apt-get install -qy python-software-properties python-virtualenv curl

USER root
WORKDIR /root
ADD .aws/credentials .aws/credentials

ADD bootstrap-ubuntu.sh bootstrap.sh


ADD ./ swarmy/

CMD /root/bootstrap.sh ; /bin/bash -l
