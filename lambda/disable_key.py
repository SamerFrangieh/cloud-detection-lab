import gzip
import json
import os
import urllib.request

import boto3

s3 = boto3.client("s3")
iam = boto3.client("iam")
WEBHOOK = os.environ.get("SLACK_WEBHOOK_URL", "")
ALLOWLIST = {u.strip() for u in os.environ.get("ALLOWLIST", "").split(",") if u.strip()}


def notify(text):
    print(text)
    if not WEBHOOK:
        return
    body = json.dumps({"text": text}).encode()
    req = urllib.request.Request(WEBHOOK, data=body, headers={"Content-Type": "application/json"})
    urllib.request.urlopen(req, timeout=5)


def handle_record(r):
    caller = r["userIdentity"].get("arn", "unknown").split("/")[-1]
    target = (r.get("requestParameters") or {}).get("userName", caller)
    key_id = ((r.get("responseElements") or {}).get("accessKey") or {}).get("accessKeyId")

    if not key_id:
        return "no key"
    if target == caller or target in ALLOWLIST:
        print(f"Allowed: {caller} created key {key_id} for {target}")
        return "allowed"

    iam.update_access_key(UserName=target, AccessKeyId=key_id, Status="Inactive")
    notify(
        f":rotating_light: *Access key disabled automatically*\n"
        f"Key `{key_id}` on IAM user `{target}` was created by `{caller}` "
        f"from {r.get('sourceIPAddress')} at {r.get('eventTime')}.\n"
        f"Possible persistence (MITRE T1098.001). Investigate {caller}."
    )
    return "disabled"


def handler(event, context):
    bucket = event["detail"]["bucket"]["name"]
    key = event["detail"]["object"]["key"]
    if "/CloudTrail/" not in key or not key.endswith(".json.gz"):
        return {"status": "skipped", "key": key}

    raw = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    records = json.loads(gzip.decompress(raw))["Records"]

    results = [
        handle_record(r) for r in records
        if r.get("eventSource") == "iam.amazonaws.com" and r.get("eventName") == "CreateAccessKey"
    ]
    print(f"{key}: {len(records)} records, actions: {results}")
    return {"status": "done", "actions": results}