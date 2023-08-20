FROM registry.access.redhat.com/ubi9/ubi-micro

ADD --chmod=755 ssserver ssserver

CMD ./ssserver -c server.conf
