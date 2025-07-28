FROM quay.io/lib/python:3.12-slim AS build

WORKDIR /tmp

COPY ./pkg/ ./

RUN python -m pip install --upgrade --no-cache-dir pip setuptools wheel

RUN python setup.py bdist_wheel

FROM quay.io/jupyter/scipy-notebook:python-3.12 AS runtime

WORKDIR /tmp

COPY --from=build /tmp/dist/notebook2app*.whl ./

RUN pip install --no-cache-dir notebook2app*.whl

WORKDIR /home/jovyan

COPY ./notebooks/ ./