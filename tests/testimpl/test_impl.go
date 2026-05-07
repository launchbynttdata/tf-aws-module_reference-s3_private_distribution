package testimpl

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/lambda"
	lambdatypes "github.com/aws/aws-sdk-go-v2/service/lambda/types"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/launchbynttdata/lcaf-component-terratest/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type validationContext struct {
	region           string
	functionName     string
	lambdaClient     *lambda.Client
}

type validationResult struct {
	Name     string `json:"name"`
	Expected int    `json:"expected"`
	Actual   int    `json:"actual"`
	Passed   bool   `json:"passed"`
}

type lambdaResponse struct {
	StatusCode int                 `json:"statusCode"`
	AllPassed  bool                `json:"all_passed"`
	Results    []validationResult  `json:"results"`
}


// TestComposableComplete invokes the Lambda validation function to validate
// private S3 access via the interface endpoint (network path only, no IAM).
func TestComposableComplete(t *testing.T, ctx types.TestContext) {
	validation := verifyInfrastructureReadOnly(t, ctx)
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
	functionName := terraform.Output(t, tfOptions, "lambda_function_name")

	require.NotEmpty(t, region, "aws_region output must not be empty")
	require.NotEmpty(t, endpointID, "s3_interface_vpce_id output must not be empty")
	require.NotEmpty(t, bucketName, "s3_bucket_name output must not be empty")
	require.NotEmpty(t, functionName, "lambda_function_name output must not be empty")

	awsCfg, err := config.LoadDefaultConfig(context.Background(), config.WithRegion(region))
	require.NoError(t, err, "failed to load AWS SDK config")

	lambdaClient := lambda.NewFromConfig(awsCfg)

	// Verify the Lambda function exists and is configured.
	getFuncOut, err := lambdaClient.GetFunction(context.Background(), &lambda.GetFunctionInput{
		FunctionName: aws.String(functionName),
	})
	require.NoError(t, err, "failed to get Lambda function %s", functionName)
	require.NotNil(t, getFuncOut.Configuration, "Lambda function configuration missing")
	assert.Equal(t, functionName, aws.ToString(getFuncOut.Configuration.FunctionName), "Lambda function name should match Terraform output")
	assert.Equal(t, lambdatypes.RuntimePython312, getFuncOut.Configuration.Runtime, "Lambda should be running Python 3.12")

	// TODO: implement — verify logging target wiring
	// When enable_logging = true, assert that the artifact bucket has server access logging
	// enabled and the target bucket name matches the logging_bucket_name Terraform output.
	// Use s3Client.GetBucketLogging(bucketName) and compare to
	// terraform.Output(t, tfOptions, "logging_bucket_name").

	// TODO: implement — verify replication configuration presence
	// When enable_replication = true, assert that the artifact bucket has a replication
	// configuration and the destination bucket ARN matches the replication_bucket_arn output.
	// Use s3Client.GetBucketReplication(bucketName) and compare to
	// terraform.Output(t, tfOptions, "replication_bucket_arn").

	return validationContext{
		region:       region,
		functionName: functionName,
		lambdaClient: lambdaClient,
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
