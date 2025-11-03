import os, json, boto3, psycopg2

sec = boto3.client("secretsmanager")
DB_ARN = os.environ["DB_SECRET_ARN"]  # master secret (RDS managed)
APP_ARN = os.environ["APP_SECRET_ARN"]  # app user + apikeys

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

DDL = """
CREATE TABLE IF NOT EXISTS public.estudiante (
    id serial PRIMARY KEY,
    nombre varchar(50),
    apellido varchar(50),
    fecha_nacimiento date,
    direccion varchar(100),
    correo_electronico varchar(100) UNIQUE,
    carrera varchar(50)
);
"""


def handler(event, ctx):
    # master creds
    creds = json.loads(sec.get_secret_value(SecretId=DB_ARN)["SecretString"])
    # app creds
    app = json.loads(sec.get_secret_value(SecretId=APP_ARN)["SecretString"])
    app_user = app["DB_USER"]
    app_pass = app["DB_PASSWORD"]

    conn = psycopg2.connect(
        host=creds["host"],
        port=creds["port"],
        dbname=creds["dbname"],
        user=creds["username"],
        password=creds["password"],
        connect_timeout=5,
    )
    try:
        with conn, conn.cursor() as cur:
            # tabla + datos
            cur.execute(DDL)
            for nombre, apellido, fecha_nac, direccion, correo, carrera in ROWS:
                cur.execute(
                    """
                    INSERT INTO public.estudiante
                        (nombre, apellido, fecha_nacimiento, direccion, correo_electronico, carrera)
                    VALUES (%s,%s,%s,%s,%s,%s)
                    ON CONFLICT (correo_electronico) DO NOTHING;
                """,
                    (nombre, apellido, fecha_nac, direccion, correo, carrera),
                )

            # usuario de app y privilegios mínimos
            cur.execute(
                "SELECT 1 FROM pg_roles WHERE rolname = %s", (app_user,)
            )
            exists = cur.fetchone() is not None
            if exists:
                cur.execute(
                    f"ALTER ROLE {psycopg2.extensions.AsIs(app_user)} WITH LOGIN PASSWORD %s",
                    (app_pass,),
                )
            else:
                cur.execute(
                    f"CREATE ROLE {psycopg2.extensions.AsIs(app_user)} WITH LOGIN PASSWORD %s",
                    (app_pass,),
                )

            cur.execute(
                "GRANT CONNECT ON DATABASE %s TO %s",
                (
                    psycopg2.extensions.AsIs(creds["dbname"]),
                    psycopg2.extensions.AsIs(app_user),
                ),
            )
            cur.execute(
                "GRANT USAGE ON SCHEMA public TO %s",
                (psycopg2.extensions.AsIs(app_user),),
            )
            cur.execute(
                "GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO %s",
                (psycopg2.extensions.AsIs(app_user),),
            )
            cur.execute(
                "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO %s",
                (psycopg2.extensions.AsIs(app_user),),
            )

            cur.execute("SELECT count(*) FROM public.estudiante;")
            total = cur.fetchone()[0]

        return {
            "statusCode": 200,
            "body": json.dumps({"ok": True, "rows_total": total}),
        }
    finally:
        conn.close()
