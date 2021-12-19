FROM python:stretch

WORKDIR /app

COPY . /app

RUN pip install --upgrade pip &&\
pip install -r requirements.txt

ENTRYPOINT ["gunicorn", "-b", ":8080", "main:APP"]