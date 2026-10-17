FROM python:3.12-slim

# A known non-root user, because who owns the uploads volume is the point of
# one of the challenges.
RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin appsvc

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY alembic.ini .
COPY alembic ./alembic
COPY app ./app

RUN mkdir -p /app/uploads && chown -R appsvc:appsvc /app/uploads
USER appsvc

EXPOSE 8000
# FORWARDED_ALLOW_IPS is read by uvicorn as well as by our own config check:
# without it, X-Forwarded-For from the nginx in front is ignored.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips \"${FORWARDED_ALLOW_IPS}\""]
