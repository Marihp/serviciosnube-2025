import os, json, boto3, psycopg2

sec = boto3.client("secretsmanager")
ARN = os.environ["DB_SECRET_ARN"]

def handler(event, ctx):
    body = json.loads(event.get("body") or "{}")
    required = ["n1", "e1", "n2", "e2"]
    if not all(k in body for k in required):
        return {"statusCode": 400, "body": json.dumps({"error": "payload inválido"})}

    creds = json.loads(sec.get_secret_value(SecretId=ARN)["SecretString"])
    conn = psycopg2.connect(
        host=creds["host"], port=creds["port"],
        dbname=creds["dbname"], user=creds["username"], password=creds["password"],
        connect_timeout=5,
    )
    try:
        with conn, conn.cursor() as cur:
            cur.execute("insert into estudiantes(nombre,email) values(%s,%s)", (body["n1"], body["e1"]))
            cur.execute("insert into estudiantes(nombre,email) values(%s,%s)", (body["n2"], body["e2"]))
        return {"statusCode": 201, "body": json.dumps({"ok": True})}
    finally:
        conn.close()
