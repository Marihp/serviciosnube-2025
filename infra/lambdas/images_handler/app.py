import json, os, boto3, logging, urllib.parse

log = logging.getLogger()
log.setLevel(logging.INFO)

s3 = boto3.client("s3")
BUCKET = os.environ.get("S3_BUCKET", "servicios-nube-dev-images")
PREFIX = os.environ.get("S3_PREFIX", "/images").lstrip(
    "/"
)  # "" para raíz, o "images"
if PREFIX and not PREFIX.endswith("/"):
    PREFIX += "/"


def _list_all_keys(bucket: str, prefix: str):
    keys = []
    kwargs = {"Bucket": bucket}
    if prefix is not None:
        kwargs["Prefix"] = prefix  # "" lista todo; None no aplica filtro
    while True:
        resp = s3.list_objects_v2(**kwargs)
        for obj in resp.get("Contents", []) or []:
            k = obj.get("Key")
            if k and not k.endswith("/"):
                keys.append(k)
        if resp.get("IsTruncated"):
            kwargs["ContinuationToken"] = resp.get("NextContinuationToken")
        else:
            break
    return keys


def handler(event, ctx):
    try:
        log.info({"bucket": BUCKET, "prefix": PREFIX})
        keys = _list_all_keys(BUCKET, PREFIX)
        urls = [
            s3.generate_presigned_url(
                "get_object",
                Params={"Bucket": BUCKET, "Key": k},
                ExpiresIn=300,
            )
            for k in keys
        ]
        body = {"count": len(urls), "images": urls}
        status = 200
    except Exception as e:
        log.exception("Error listing/generating URLs")
        body = {"error": str(e)}
        status = 500

    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "*",
            "Access-Control-Allow-Methods": "GET,OPTIONS",
        },
        "body": json.dumps(body),
    }
