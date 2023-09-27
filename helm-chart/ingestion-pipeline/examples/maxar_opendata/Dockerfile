from ghcr.io/stac-utils/pgstac:v0.7.9

COPY requirements.txt /requirements.txt
RUN pip install -r /requirements.txt

COPY src /src

COPY catalog.json /catalog.json