"""
S3 Private Access Validation Probe

Validates the 200/403/403 access pattern against an S3 interface endpoint
without using any IAM credentials for S3. All requests are raw HTTPS GETs
via urllib, relying purely on the VPC network path (aws:SourceVpce condition).

Environment variables (injected by Terraform):
  VPCE_BUCKET_HOST   - e.g. bucket.vpce-xxx.s3.us-east-2.vpce.amazonaws.com
  ARTIFACT_BUCKET    - name of the allowed artifact bucket
  DISALLOWED_BUCKET  - name of the bucket that should be blocked by endpoint policy

Return codes from _get_status:
  HTTP status code  - for both successful responses and HTTP-level errors (e.g. 403)
  -1                - for any network-level or unexpected error (URLError, timeout, etc.)
"""

import json
import os
import urllib.request
import urllib.error


def lambda_handler(event, context):
    host = os.environ["VPCE_BUCKET_HOST"]
    artifact = os.environ["ARTIFACT_BUCKET"]
    disallowed = os.environ["DISALLOWED_BUCKET"]

    probes = [
        {
            "name": "valid_existing_object",
            "expected": 200,
            "url": f"https://{host}/{artifact}/client/latest/agent-fast.appinstaller",
        },
        {
            # S3 interface endpoint returns 403 for missing objects, not 404.
            "name": "invalid_missing_object",
            "expected": 403,
            "url": f"https://{host}/{artifact}/client/latest/does-not-exist.appinstaller",
        },
        {
            # Endpoint policy should block access to buckets not in the allowlist.
            "name": "disallowed_bucket_object",
            "expected": 403,
            "url": f"https://{host}/{disallowed}/client/latest/disallowed.txt",
        },
    ]

    results = []
    all_passed = True

    for probe in probes:
        actual = _get_status(probe["url"])
        passed = actual == probe["expected"]
        if not passed:
            all_passed = False
        results.append(
            {
                "name": probe["name"],
                "expected": probe["expected"],
                "actual": actual,
                "passed": passed,
            }
        )

    return {
        "statusCode": 200 if all_passed else 400,
        "all_passed": all_passed,
        "results": results,
    }


def _get_status(url: str) -> int:
    """Return the HTTP status code for a GET request, never raising exceptions."""
    req = urllib.request.Request(url, method="GET")
    # Explicitly do NOT set any Authorization or x-amz-* headers.
    # The request must succeed or fail purely on network path / bucket policy.
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status
    except urllib.error.HTTPError as exc:
        return exc.code
    except Exception:  # noqa: BLE001 - broad catch intentional: network probes must never raise
        return -1
