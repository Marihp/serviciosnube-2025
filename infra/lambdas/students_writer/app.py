import os, json, base64, re, cgi
import boto3, psycopg2
from urllib.parse import parse_qs
from datetime import date

# ---------- SSM ----------
ssm = boto3.client("ssm")
SSM_BASE = os.getenv("SSM_BASE", "/servicios-nube/dev")


def _get_param(name: str, decrypt: bool = True) -> str:
    resp = ssm.get_parameter(Name=name, WithDecryption=decrypt)
    return resp["Parameter"]["Value"]


# ---------- Helpers de parsing ----------
def _parse_multipart_bytes(raw: bytes, ct: str) -> dict:
    _ctype, params = cgi.parse_header(ct)
    boundary = params.get("boundary")
    if not boundary:
        return {}
    b = ("--" + boundary).encode()
    data = {}
    for part in raw.split(b):
        part = part.strip()
        if not part or part == b"--" or b"\r\n\r\n" not in part:
            continue
        headers_blob, body = part.split(b"\r\n\r\n", 1)
        cd_line = None
        for line in headers_blob.split(b"\r\n"):
            if line.lower().startswith(b"content-disposition"):
                cd_line = line.decode("utf-8", "ignore")
                break
        if not cd_line:
            continue
        m = re.search(r'name="([^"]+)"', cd_line)
        if not m:
            continue
        name = m.group(1)
        body = body.rstrip(b"\r\n")
        if body.endswith(b"--"):
            body = body[:-2]
        data[name] = body.decode("utf-8", "ignore")
    return data


def _parse_event_body(event: dict) -> dict:
    headers = event.get("headers") or {}
    ct = (
        headers.get("content-type")
        or headers.get("Content-Type")
        or "application/json"
    )
    body = event.get("body") or ""
    raw_bytes = (
        base64.b64decode(body)
        if event.get("isBase64Encoded")
        else body.encode("utf-8", "ignore")
    )

    # 1) JSON (incluye caso de JSON doblemente serializado)
    text = raw_bytes.decode("utf-8", "ignore")
    try:
        parsed = json.loads(text)
        if isinstance(parsed, str):
            try:
                parsed2 = json.loads(parsed)
                if isinstance(parsed2, dict):
                    return parsed2
            except Exception:
                pass
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass

    # 2) x-www-form-urlencoded
    if "application/x-www-form-urlencoded" in ct or (
        "=" in text and "&" in text
    ):
        qs = parse_qs(text, keep_blank_values=True, strict_parsing=False)
        return {
            k: (v[0] if isinstance(v, list) and v else (v or ""))
            for k, v in qs.items()
        }

    # 3) multipart/form-data
    if "multipart/form-data" in ct:
        try:
            return _parse_multipart_bytes(raw_bytes, ct)
        except Exception:
            pass

    # 4) fallback simple key=value por línea
    candidate = {}
    for line in text.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            candidate[k.strip()] = v.strip()
    return candidate


def _empty_to_none(v):
    if v is None:
        return None
    if isinstance(v, str) and v.strip() == "":
        return None
    return v


def _parse_fecha(value: str | None):
    """Acepta ISO 'YYYY-MM-DD'. Si viene en otros formatos ambiguos, devuelve None (no rompe)."""
    if not value:
        return None
    s = str(value).strip()
    # ISO estricto
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
        try:
            y, m, d = map(int, s.split("-"))
            date(y, m, d)  # valida
            return s  # Postgres acepta 'YYYY-MM-DD' como texto
        except Exception:
            return None
    # 2025/01/31 -> normaliza
    if re.fullmatch(r"\d{4}/\d{1,2}/\d{1,2}", s):
        y, m, d = s.split("/")
        try:
            y, m, d = int(y), int(m), int(d)
            date(y, m, d)
            return f"{y:04d}-{m:02d}-{d:02d}"
        except Exception:
            return None
    # Otros formatos (dd/mm/yyyy o mm/dd/yyyy) -> evitar ambigüedad
    return None


def _one_student(d: dict):
    nombre = d.get("nombre") or d.get("name") or ""
    apellido = d.get("apellido") or d.get("lastname") or ""
    correo = d.get("correo_electronico") or d.get("correo") or d.get("email")
    direccion = d.get("direccion") or d.get("address") or None
    carrera = d.get("carrera") or d.get("major") or None
    # fecha: fecha_nacimiento | fechaNacimiento | dob
    fecha_raw = (
        d.get("fecha_nacimiento")
        or d.get("fechaNacimiento")
        or d.get("dob")
        or None
    )
    fecha = _parse_fecha(fecha_raw)
    return {
        "nombre": _empty_to_none(nombre),
        "apellido": _empty_to_none(apellido),
        "correo": _empty_to_none(correo),
        "direccion": _empty_to_none(direccion),
        "carrera": _empty_to_none(carrera),
        "fecha_nacimiento": fecha,
    }


def _normalize_payload(obj: dict):
    if isinstance(obj.get("students"), list):
        return [
            _one_student(s if isinstance(s, dict) else {})
            for s in obj["students"]
        ]
    if any(
        k in obj
        for k in ("nombre", "name", "correo", "correo_electronico", "email")
    ):
        return [_one_student(obj)]
    return []


# ---------- DB ----------
def _split_host_port(host_str: str, port_from_param: int) -> tuple[str, int]:
    if not host_str:
        raise ValueError("DB host vacío en SSM")
    host_s = re.sub(r"^https?://", "", host_str.strip(), flags=re.IGNORECASE)
    host_s = host_s.split("/", 1)[0]
    h, p = host_s, port_from_param
    if ":" in host_s:
        parts = host_s.rsplit(":", 1)
        h = parts[0]
        try:
            p = int(parts[1])
        except Exception:
            pass
    if not re.match(r"^[A-Za-z0-9\.\-]+$", h):
        raise ValueError(f"DB host inválido en SSM: {host_str}")
    return h, p


def _get_db_conn_params():
    host_raw = _get_param(f"{SSM_BASE}/db/host", decrypt=False)
    port_s = _get_param(f"{SSM_BASE}/db/port", decrypt=False)
    dbname = _get_param(f"{SSM_BASE}/db/name", decrypt=False)
    user = _get_param(f"{SSM_BASE}/db/user", decrypt=False)
    pwd = _get_param(f"{SSM_BASE}/db/master_password", decrypt=True)

    try:
        port = int(port_s)
    except Exception:
        port = 5432

    host, port_eff = _split_host_port(host_raw, port)
    return dict(
        host=host,
        port=port_eff,
        dbname=dbname,
        user=user,
        password=pwd,
        connect_timeout=5,
    )


# ---------- Handler ----------
def handler(event, ctx):
    try:
        body_obj = _parse_event_body(event)
    except Exception as e:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "JSON inválido", "detail": str(e)}),
        }

    rows = _normalize_payload(body_obj)
    if not rows or any(not r.get("correo") for r in rows):
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "payload inválido", "raw": body_obj}),
        }

    try:
        params = _get_db_conn_params()
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": f"SSM faltante: {str(e)}"}),
        }

    conn = psycopg2.connect(**params)
    try:
        inserted = 0
        with conn, conn.cursor() as cur:
            for r in rows:
                # Insert + upsert (NO pisa con NULLs ni vacíos)
                cur.execute(
                    """
                    INSERT INTO public.estudiante
                        (nombre, apellido, fecha_nacimiento, direccion, correo_electronico, carrera)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON CONFLICT (correo_electronico) DO UPDATE SET
                        nombre           = COALESCE(EXCLUDED.nombre, public.estudiante.nombre),
                        apellido         = COALESCE(EXCLUDED.apellido, public.estudiante.apellido),
                        fecha_nacimiento = COALESCE(EXCLUDED.fecha_nacimiento, public.estudiante.fecha_nacimiento),
                        direccion        = COALESCE(EXCLUDED.direccion, public.estudiante.direccion),
                        carrera          = COALESCE(EXCLUDED.carrera, public.estudiante.carrera)
                    """,
                    (
                        r.get("nombre"),
                        r.get("apellido"),
                        r.get("fecha_nacimiento"),
                        r.get("direccion"),
                        r["correo"],
                        r.get("carrera"),
                    ),
                )
                # rowcount en upsert no es fiable; respondemos con la cantidad recibida
                inserted += 1

        return {
            "statusCode": 201,
            "body": json.dumps({"ok": True, "inserted": inserted}),
        }
    finally:
        conn.close()
