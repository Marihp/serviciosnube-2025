import os
import re
import json
import boto3
import psycopg2
from psycopg2.extras import execute_values

ssm = boto3.client("ssm")
SSM_BASE = os.getenv("SSM_BASE", "/servicios-nube/dev")


def _get_param(name, decrypt=True):
    resp = ssm.get_parameter(Name=name, WithDecryption=decrypt)
    return resp["Parameter"]["Value"]


def _normalize_host_and_port(raw_host: str, port_from_ssm: str):
    """
    Normaliza valores de host que pueden venir como:
      - 'endpoint'
      - 'endpoint:9876'
      - 'http://endpoint:9876'
      - 'https://endpoint'
      - 'endpoint:9876/loquesea'
    Retorna (host_solo, puerto_int)
    """
    h = (raw_host or "").strip()
    # quita esquema
    h = re.sub(r"^https?://", "", h, flags=re.IGNORECASE)
    # corta cualquier path
    if "/" in h:
        h = h.split("/", 1)[0]
    host_only = h
    # puerto por defecto: el de SSM
    port = (
        int(str(port_from_ssm).strip()) if str(port_from_ssm).strip() else 5432
    )
    # si viene con :puerto, úsalo
    if ":" in h:
        host_only, maybe_port = h.rsplit(":", 1)
        if maybe_port.isdigit():
            port = int(maybe_port)
    return host_only, port


DDL = """
CREATE TABLE IF NOT EXISTS public.estudiante (
    id serial PRIMARY KEY,
    nombre varchar(50),
    apellido varchar(50),
    fecha_nacimiento date,
    direccion varchar(100),
    correo_electronico varchar(100),
    carrera varchar(50)
);
"""

ROWS = [
    (
        "Ana",
        "López",
        "2000-04-10",
        "Calle 321, Ciudad",
        "ana.lopez@example.com",
        "Ingeniería Informática",
    ),
    (
        "Carlos",
        "Rodríguez",
        "1999-08-22",
        "Avenida 654, Ciudad",
        "carlos@example.com",
        "Arquitectura",
    ),
    (
        "Sofía",
        "Hernández",
        "1998-07-15",
        "Calle 987, Ciudad",
        "sofia@example.com",
        "Contabilidad",
    ),
    (
        "Diego",
        "Gómez",
        "2001-01-05",
        "Calle 123, Ciudad",
        "diego@example.com",
        "Ingeniería Mecánica",
    ),
    (
        "Laura",
        "Díaz",
        "1999-03-20",
        "Avenida 456, Ciudad",
        "laura@example.com",
        "Enfermería",
    ),
    (
        "Pedro",
        "Ramírez",
        "1997-11-28",
        "Calle 789, Ciudad",
        "pedro@example.com",
        "Economía",
    ),
    (
        "Isabel",
        "Torres",
        "1996-06-14",
        "Avenida 654, Ciudad",
        "isabel@example.com",
        "Biología",
    ),
    (
        "Miguel",
        "Pérez",
        "2002-09-08",
        "Calle 321, Ciudad",
        "miguel@example.com",
        "Historia",
    ),
    (
        "Carolina",
        "García",
        "2000-02-25",
        "Avenida 987, Ciudad",
        "carolina@example.com",
        "Física",
    ),
    (
        "Andrés",
        "López",
        "1998-05-12",
        "Calle 123, Ciudad",
        "andres@example.com",
        "Matemáticas",
    ),
    (
        "Vincent",
        "Restrepo",
        "1990-03-26",
        "Calle 20, Ciudad",
        "vincent@example.com",
        "Ingeniería Informática",
    ),
    (
        "Elena",
        "Gómez",
        "1997-09-18",
        "Avenida 1234, Ciudad",
        "elena@example.com",
        "Ingeniería Eléctrica",
    ),
    (
        "Roberto",
        "Fernández",
        "1996-12-05",
        "Calle 5678, Ciudad",
        "roberto@example.com",
        "Ciencias de la Computación",
    ),
    (
        "Fernanda",
        "Sánchez",
        "1999-02-28",
        "Calle 9999, Ciudad",
        "fernanda@example.com",
        "Psicología",
    ),
    (
        "Julio",
        "Martínez",
        "2001-05-10",
        "Avenida 5555, Ciudad",
        "julio@example.com",
        "Medicina",
    ),
    (
        "Patricia",
        "Torres",
        "1998-08-22",
        "Calle 3333, Ciudad",
        "patricia@example.com",
        "Derecho",
    ),
    (
        "Raúl",
        "López",
        "1995-04-15",
        "Avenida 7777, Ciudad",
        "raul@example.com",
        "Arquitectura",
    ),
    (
        "Natalia",
        "Hernández",
        "2000-07-20",
        "Calle 2222, Ciudad",
        "natalia@example.com",
        "Contabilidad",
    ),
    (
        "Andrea",
        "Ramírez",
        "1997-10-12",
        "Calle 1111, Ciudad",
        "andrea@example.com",
        "Ingeniería Civil",
    ),
    (
        "Hugo",
        "González",
        "1996-03-28",
        "Avenida 8888, Ciudad",
        "hugo@example.com",
        "Historia del Arte",
    ),
    (
        "Silvia",
        "Pérez",
        "2002-01-08",
        "Calle 4444, Ciudad",
        "silvia@example.com",
        "Biomedicina",
    ),
]

INSERT_ONE = """
INSERT INTO public.estudiante
    (nombre, apellido, fecha_nacimiento, direccion, correo_electronico, carrera)
SELECT %s, %s, %s, %s, %s, %s
WHERE NOT EXISTS (
    SELECT 1 FROM public.estudiante e WHERE e.correo_electronico = %s
);
"""


def handler(event, ctx):
    try:
        raw_host = _get_param(f"{SSM_BASE}/db/host", decrypt=False)
        port_ssm = _get_param(f"{SSM_BASE}/db/port", decrypt=False)
        dbname = _get_param(f"{SSM_BASE}/db/name", decrypt=False)
        user = _get_param(f"{SSM_BASE}/db/user", decrypt=False)  # master user
        pwd = _get_param(
            f"{SSM_BASE}/db/master_password", decrypt=True
        )  # master password
        host, port = _normalize_host_and_port(raw_host, port_ssm)

        # Log de depuración para CloudWatch
        print(
            f"[db_init] SSM_BASE={SSM_BASE} raw_host='{raw_host}' -> host='{host}' port={port} db='{dbname}' user='{user}'"
        )

        conn = psycopg2.connect(
            host=host,
            port=port,
            dbname=dbname,
            user=user,
            password=pwd,
            connect_timeout=5,
        )
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": f"ConnParams: {str(e)}"}),
        }

    inserted = 0
    try:
        with conn, conn.cursor() as cur:
            cur.execute(DDL)
            for n, a, f, d, c, k in ROWS:
                cur.execute(INSERT_ONE, (n, a, f, d, c, k, c))
                if cur.rowcount == 1:
                    inserted += 1
            cur.execute("SELECT count(*) FROM public.estudiante;")
            total = cur.fetchone()[0]

        return {
            "statusCode": 200,
            "body": json.dumps(
                {"ok": True, "inserted_now": inserted, "rows_total": total}
            ),
        }
    finally:
        conn.close()
