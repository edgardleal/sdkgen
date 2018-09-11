FROM crystallang/crystal:0.24.2
CMD ["bash"]
ADD . /tmp/
WORKDIR /tmp
RUN crystal tool format --check
RUN crystal spec
WORKDIR /root
RUN crystal build /tmp/main.cr -o sdkgen
RUN cp sdkgen /usr/bin
