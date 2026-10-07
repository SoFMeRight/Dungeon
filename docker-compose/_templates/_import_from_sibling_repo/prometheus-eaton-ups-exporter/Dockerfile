# Name: prometheus-eaton-ups-exporter-sfmr:latest

FROM python:3.14.3-alpine3.23

RUN apk add --no-cache git
RUN apk add --no-cache openssh
RUN apk add --no-cache coreutils

WORKDIR /usr/src/
RUN git clone https://gitlab.prplanit.com/precisionplanit/prometheus-eaton-ups-exporter.git
RUN mv ./prometheus-eaton-ups-exporter ./app
WORKDIR /usr/src/app
#COPY ./requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt && \
    rm requirements.txt && \
    mkdir etc

# Copy the application code
#COPY prometheus_eaton_ups_exporter prometheus_eaton_ups_exporter
#COPY prometheus_eaton_ups_exporter.py .
#COPY requirements.txt .
#COPY .pyre_configuration .

CMD ["python", "./prometheus_eaton_ups_exporter.py", "-k", "-v", "-c", "/usr/src/app/etc/config.json", "-w", "0.0.0.0:9795"]
