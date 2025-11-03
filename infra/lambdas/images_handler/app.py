import json, boto3, os

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET"]


def handler(event, ctx):
    resp = s3.list_objects_v2(Bucket=BUCKET, Prefix="images/")
    keys = [
        o["Key"]
        for o in resp.get("Contents", [])
        if o.get("Key") and not o["Key"].endswith("/")
    ]
    urls = [
        s3.generate_presigned_url(
            "get_object", Params={"Bucket": BUCKET, "Key": k}, ExpiresIn=300
        )
        for k in keys
    ]
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"images": urls}),
    }
