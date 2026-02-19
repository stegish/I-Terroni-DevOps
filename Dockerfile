FROM python:3.9-slim

RUN apt-get update && apt-get install -y \
    gcc \
    libsqlite3-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN gcc flag_tool.c -o flag_tool -lsqlite3

#RUN mkdir -p tmp

EXPOSE 5000

#ENV DATABASE_URL=tmp/minitwit.db

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "minitwit_refactor:app"]