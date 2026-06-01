package testimpl

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/lambda"
	lambdatypes "github.com/aws/aws-sdk-go-v2/service/lambda/types"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	s3types "github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/launchbynttdata/lcaf-component-terratest/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type validationContext struct {
	region               string
	functionName         string
	bucketName           string
	disallowedBucketName string
	lambdaClient         *lambda.Client
	awsCfg               aws.Config
}

type validationResult struct {
	Name     string `json:"name"`
	Expected int    `json:"expected"`
	Actual   int    `json:"actual"`
	Passed   bool   `json:"passed"`
}

type lambdaResponse struct {
	StatusCode int                `json:"statusCode"`
	AllPassed  bool               `json:"all_passed"`
	Results    []validationResult `json:"results"`
}

const expectedPrimaryRegion = "us-east-2"

// TestComposableComplete invokes the Lambda validation function to validate
// private S3 access via the interface endpoint (network path only, no IAM).
// It also registers a t.Cleanup that runs after terraform.Destroy to confirm
// the key resources are actually gone from AWS.
func TestComposableComplete(t *testing.T, ctx types.TestContext) {
	validation := verifyInfrastructureReadOnly(t, ctx)

	// t.Cleanup fires after internalRunSetupTestTeardown (and its deferred
	// terraform.Destroy) returns — i.e., post-destroy.  Capture the values
	// we need now so the closure doesn't depend on live Terraform state.
	t.Cleanup(func() {
		verifyResourcesDestroyed(t, validation)
	})

	invokeLambdaValidation(t, validation)
}

// TestComposableCompleteReadonly verifies deployed resources without running
// commands that mutate runtime behavior.
func TestComposableCompleteReadonly(t *testing.T, ctx types.TestContext) {
	verifyInfrastructureReadOnly(t, ctx)
}

func verifyInfrastructureReadOnly(t *testing.T, ctx types.TestContext) validationContext {
	t.Helper()

	tfOptions := ctx.TerratestTerraformOptions()
	region := terraform.Output(t, tfOptions, "aws_region")
	endpointID := terraform.Output(t, tfOptions, "s3_interface_vpce_id")
	bucketName := terraform.Output(t, tfOptions, "s3_bucket_name")
	disallowedBucketName := terraform.Output(t, tfOptions, "disallowed_bucket_name")
	functionName := terraform.Output(t, tfOptions, "lambda_function_name")
	loggingBucketName := terraform.Output(t, tfOptions, "logging_bucket_name")
	replicationBucketArn := terraform.Output(t, tfOptions, "replication_bucket_arn")

	assert.Equal(t, expectedPrimaryRegion, region, "aws_region should match the test profile region")
	assert.True(t, strings.HasPrefix(endpointID, "vpce-"), "s3_interface_vpce_id should look like an AWS VPC endpoint id")
	assert.True(t, strings.HasPrefix(bucketName, "msix-s3-bucket-complete-") && strings.HasSuffix(bucketName, "-artifacts"), "s3_bucket_name should use the complete example naming pattern")
	assert.True(t, strings.HasPrefix(disallowedBucketName, "msix-s3-bucket-complete-disallowed-"), "disallowed_bucket_name should use the complete example naming pattern")
	assert.True(t, strings.HasPrefix(functionName, "msix-s3-bucket-complete-s3-probe-"), "lambda_function_name should use the complete example naming pattern")

	awsCfg, err := config.LoadDefaultConfig(context.Background(), config.WithRegion(region))
	require.NoError(t, err, "failed to load AWS SDK config")

	lambdaClient := lambda.NewFromConfig(awsCfg)
	s3Client := s3.NewFromConfig(awsCfg)

	// Verify the Lambda function exists and is configured.
	getFuncOut, err := lambdaClient.GetFunction(context.Background(), &lambda.GetFunctionInput{
		FunctionName: aws.String(functionName),
	})
	require.NoError(t, err, "failed to get Lambda function %s", functionName)
	require.NotNil(t, getFuncOut.Configuration, "Lambda function configuration missing")
	assert.Equal(t, functionName, aws.ToString(getFuncOut.Configuration.FunctionName), "Lambda function name should match Terraform output")
	assert.Equal(t, lambdatypes.RuntimePython312, getFuncOut.Configuration.Runtime, "Lambda should be running Python 3.12")

	// Verify the artifacts bucket policy does not use broad same-account bypass logic.
	bucketPolicyOut, err := s3Client.GetBucketPolicy(context.Background(), &s3.GetBucketPolicyInput{
		Bucket: aws.String(bucketName),
	})
	require.NoError(t, err, "failed to get bucket policy for %s", bucketName)
	policyJSON := aws.ToString(bucketPolicyOut.Policy)
	require.Contains(t, policyJSON, "DenyAccessOutsideVPCEndpoint", "bucket policy should include VPCE deny statement")
	require.NotContains(t, policyJSON, "aws:PrincipalAccount", "bucket policy must not include broad same-account bypass conditions")

	verifyBucketLoggingConfiguration(t, s3Client, bucketName, loggingBucketName)
	verifyBucketReplicationConfiguration(t, s3Client, bucketName, replicationBucketArn)

	return validationContext{
		region:               region,
		functionName:         functionName,
		bucketName:           bucketName,
		disallowedBucketName: disallowedBucketName,
		lambdaClient:         lambdaClient,
		awsCfg:               awsCfg,
	}
}

func invokeLambdaValidation(t *testing.T, validation validationContext) {
	t.Helper()

	// Invoke the Lambda function synchronously to perform the S3 private access validation.
	invokeOut, err := validation.lambdaClient.Invoke(context.Background(), &lambda.InvokeInput{
		FunctionName:   aws.String(validation.functionName),
		InvocationType: lambdatypes.InvocationTypeRequestResponse,
		LogType:        lambdatypes.LogTypeTail,
	})
	require.NoError(t, err, "failed to invoke Lambda function %s", validation.functionName)

	// Parse the Lambda response JSON.
	var response lambdaResponse
	err = json.Unmarshal(invokeOut.Payload, &response)
	require.NoError(t, err, "failed to parse Lambda response payload: %s", string(invokeOut.Payload))

	// If FunctionError is set, Lambda execution failed.
	if invokeOut.FunctionError != nil && *invokeOut.FunctionError != "" {
		require.FailNowf(t, "Lambda validation failed", "Lambda returned FunctionError: %s, Payload: %s", *invokeOut.FunctionError, string(invokeOut.Payload))
	}

	// Verify the validation results.
	assert.True(t, response.AllPassed, "all validation checks should pass")
	require.Len(t, response.Results, 3, "expected 3 validation results")

	assertExpectedValidationStatuses(t, response.Results)
}

func assertExpectedValidationStatuses(t *testing.T, results []validationResult) {
	t.Helper()

	expected := map[string]int{
		"valid_existing_object": 200,
		// Over the S3 interface endpoint path used by this example, a missing key
		// presents as 403 rather than the public-S3-style 404.
		"invalid_missing_object":   403,
		"disallowed_bucket_object": 403,
	}

	seen := map[string]bool{}
	for _, row := range results {
		wanted, ok := expected[row.Name]
		if !ok {
			continue
		}
		seen[row.Name] = true
		assert.Equalf(t, wanted, row.Actual, "%s should return expected status code", row.Name)
	}

	for name := range expected {
		require.Truef(t, seen[name], "validation result missing expected check %s", name)
	}
}

func verifyBucketLoggingConfiguration(t *testing.T, s3Client *s3.Client, bucketName string, expectedTargetBucket string) {
	t.Helper()

	loggingOut, err := s3Client.GetBucketLogging(context.Background(), &s3.GetBucketLoggingInput{
		Bucket: aws.String(bucketName),
	})
	require.NoError(t, err, "failed to get bucket logging for %s", bucketName)

	if expectedTargetBucket == "" {
		require.Nil(t, loggingOut.LoggingEnabled, "bucket logging should be disabled when no logging target bucket is configured")
		return
	}

	require.NotNil(t, loggingOut.LoggingEnabled, "bucket logging should be enabled when a logging target bucket is configured")
	assert.Equal(t, expectedTargetBucket, aws.ToString(loggingOut.LoggingEnabled.TargetBucket), "logging target bucket should match Terraform output")
	assert.True(t, strings.HasSuffix(aws.ToString(loggingOut.LoggingEnabled.TargetPrefix), "logs/"), "logging prefix should end with logs/")
}

func verifyBucketReplicationConfiguration(t *testing.T, s3Client *s3.Client, bucketName string, expectedDestinationArn string) {
	t.Helper()

	replicationOut, err := s3Client.GetBucketReplication(context.Background(), &s3.GetBucketReplicationInput{
		Bucket: aws.String(bucketName),
	})

	if expectedDestinationArn == "" {
		require.Error(t, err, "bucket replication should be absent when replication is disabled")
		return
	}

	require.NoError(t, err, "failed to get bucket replication for %s", bucketName)
	require.NotNil(t, replicationOut.ReplicationConfiguration, "bucket replication should be configured when replication is enabled")
	require.NotEmpty(t, replicationOut.ReplicationConfiguration.Rules, "replication configuration should contain at least one rule")
	require.NotNil(t, replicationOut.ReplicationConfiguration.Rules[0].Destination, "replication rule should contain a destination")
	assert.Equal(t, expectedDestinationArn, aws.ToString(replicationOut.ReplicationConfiguration.Rules[0].Destination.Bucket), "replication destination ARN should match Terraform output")
}

// verifyResourcesDestroyed is called via t.Cleanup after terraform.Destroy.
// It confirms that the key AWS resources are actually absent, not just that
// the destroy command exited zero.
func verifyResourcesDestroyed(t *testing.T, v validationContext) {
	t.Helper()

	s3Client := s3.NewFromConfig(v.awsCfg)

	// Artifacts bucket must be gone.
	_, err := s3Client.HeadBucket(context.Background(), &s3.HeadBucketInput{
		Bucket: aws.String(v.bucketName),
	})
	var notFound *s3types.NotFound
	require.Errorf(t, err, "artifacts bucket %s should not exist after destroy", v.bucketName)
	assert.Truef(t, errors.As(err, &notFound),
		"artifacts bucket %s: expected NotFound, got %v", v.bucketName, err)

	// Disallowed bucket must be gone.
	_, err = s3Client.HeadBucket(context.Background(), &s3.HeadBucketInput{
		Bucket: aws.String(v.disallowedBucketName),
	})
	var notFound2 *s3types.NotFound
	require.Errorf(t, err, "disallowed bucket %s should not exist after destroy", v.disallowedBucketName)
	assert.Truef(t, errors.As(err, &notFound2),
		"disallowed bucket %s: expected NotFound, got %v", v.disallowedBucketName, err)

	// Lambda function must be gone.
	_, err = v.lambdaClient.GetFunction(context.Background(), &lambda.GetFunctionInput{
		FunctionName: aws.String(v.functionName),
	})
	var resNotFound *lambdatypes.ResourceNotFoundException
	require.Errorf(t, err, "Lambda function %s should not exist after destroy", v.functionName)
	assert.Truef(t, errors.As(err, &resNotFound),
		"Lambda function %s: expected ResourceNotFoundException, got %v", v.functionName, err)
}
