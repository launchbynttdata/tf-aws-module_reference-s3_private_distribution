package testimpl

import (
	"context"
	"encoding/json"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	ssmtypes "github.com/aws/aws-sdk-go-v2/service/ssm/types"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/launchbynttdata/lcaf-component-terratest/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type validationContext struct {
	region       string
	instanceID   string
	documentName string
	ssmClient    *ssm.Client
}

type validationResult struct {
	Name     string `json:"name"`
	Expected int    `json:"expected"`
	Actual   int    `json:"actual"`
	Passed   bool   `json:"passed"`
}

// TestComposableComplete runs provider API verification and then executes
// the SSM validation document as the functional/write probe.
func TestComposableComplete(t *testing.T, ctx types.TestContext) {
	validation := verifyInfrastructureReadOnly(t, ctx)
	runPrivateAccessValidationDocument(t, validation)
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
	instanceID := terraform.Output(t, tfOptions, "windows_instance_id")
	documentName := terraform.Output(t, tfOptions, "ssm_validation_document_name")

	require.NotEmpty(t, region, "aws_region output must not be empty")
	require.NotEmpty(t, endpointID, "s3_interface_vpce_id output must not be empty")
	require.NotEmpty(t, bucketName, "s3_bucket_name output must not be empty")
	require.NotEmpty(t, instanceID, "windows_instance_id output must not be empty")
	require.NotEmpty(t, documentName, "ssm_validation_document_name output must not be empty")

	awsCfg, err := config.LoadDefaultConfig(context.Background(), config.WithRegion(region))
	require.NoError(t, err, "failed to load AWS SDK config")

	ec2Client := ec2.NewFromConfig(awsCfg)
	ssmClient := ssm.NewFromConfig(awsCfg)

	endpointOut, err := ec2Client.DescribeVpcEndpoints(context.Background(), &ec2.DescribeVpcEndpointsInput{
		VpcEndpointIds: []string{endpointID},
	})
	require.NoError(t, err, "failed to describe VPC endpoint %s", endpointID)
	require.Len(t, endpointOut.VpcEndpoints, 1, "expected exactly one VPC endpoint with ID %s", endpointID)
	endpoint := endpointOut.VpcEndpoints[0]

	assert.Equal(t, endpointID, aws.ToString(endpoint.VpcEndpointId), "endpoint ID should match Terraform output")
	assert.True(t, strings.EqualFold(string(endpoint.State), "available"), "endpoint should be available")

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

	instanceOut, err := ec2Client.DescribeInstances(context.Background(), &ec2.DescribeInstancesInput{InstanceIds: []string{instanceID}})
	require.NoError(t, err, "failed to describe instance %s", instanceID)
	require.Len(t, instanceOut.Reservations, 1, "expected one reservation for instance %s", instanceID)
	require.Len(t, instanceOut.Reservations[0].Instances, 1, "expected one instance for %s", instanceID)
	instance := instanceOut.Reservations[0].Instances[0]
	assert.Equal(t, instanceID, aws.ToString(instance.InstanceId), "instance ID should match Terraform output")
	assert.NotEqual(t, ec2types.InstanceStateNameTerminated, instance.State.Name, "instance should not be terminated")

	documentOut, err := ssmClient.DescribeDocument(context.Background(), &ssm.DescribeDocumentInput{Name: aws.String(documentName)})
	require.NoError(t, err, "failed to describe SSM document %s", documentName)
	require.NotNil(t, documentOut.Document, "expected SSM document metadata for %s", documentName)
	assert.Equal(t, documentName, aws.ToString(documentOut.Document.Name), "SSM document name should match Terraform output")
	assert.Equal(t, ssmtypes.DocumentTypeCommand, documentOut.Document.DocumentType, "SSM document should be Command type")
	assert.Equal(t, ssmtypes.DocumentStatusActive, documentOut.Document.Status, "SSM document should be Active")

	return validationContext{
		region:       region,
		instanceID:   instanceID,
		documentName: documentName,
		ssmClient:    ssmClient,
	}
}

func runPrivateAccessValidationDocument(t *testing.T, validation validationContext) {
	t.Helper()

	waitForSSMOnline(t, validation)

	// Windows EC2 instances can report SSM PingStatus=Online while the PowerShell
	// execution environment is still initializing. Wait an additional 2 minutes
	// after the agent comes online before sending the command.
	t.Log("SSM online; waiting 2 minutes for PowerShell execution environment to initialize")
	time.Sleep(2 * time.Minute)

	const maxAttempts = 3
	var lastInvocation *ssm.GetCommandInvocationOutput

	for attempt := 1; attempt <= maxAttempts; attempt++ {
		if attempt > 1 {
			t.Logf("SSM command returned empty output (attempt %d/%d); waiting 2 minutes before retry", attempt, maxAttempts)
			time.Sleep(2 * time.Minute)
		}

		sendOutput, err := validation.ssmClient.SendCommand(context.Background(), &ssm.SendCommandInput{
			DocumentName: aws.String(validation.documentName),
			InstanceIds:  []string{validation.instanceID},
		})
		require.NoError(t, err, "failed to send SSM validation document")
		require.NotNil(t, sendOutput.Command, "expected command metadata in send-command response")
		commandID := aws.ToString(sendOutput.Command.CommandId)
		require.NotEmpty(t, commandID, "send-command response returned empty command id")
		t.Logf("SSM send-command attempt %d/%d: commandID=%s", attempt, maxAttempts, commandID)

		invocation := waitForInvocationResult(t, validation, commandID)
		lastInvocation = invocation

		combined := strings.TrimSpace(strings.Join([]string{
			aws.ToString(invocation.StandardOutputContent),
			aws.ToString(invocation.StandardErrorContent),
		}, "\n"))

		if strings.Contains(combined, "MSIX_S3_PRIVATE_VALIDATION_RESULTS_BEGIN") {
			// Output markers found — proceed to assert.
			require.Equalf(
				t,
				ssmtypes.CommandInvocationStatusSuccess,
				invocation.Status,
				"validation command must succeed (statusDetails=%s, responseCode=%d, stderr=%q)",
				aws.ToString(invocation.StatusDetails),
				invocation.ResponseCode,
				aws.ToString(invocation.StandardErrorContent),
			)
			results := extractValidationResults(t, combined)
			assertExpectedValidationStatuses(t, results)
			return
		}

		t.Logf("SSM attempt %d/%d: command %s returned status=%s but no output markers (stdout=%q, stderr=%q)",
			attempt, maxAttempts, commandID, invocation.Status,
			aws.ToString(invocation.StandardOutputContent),
			aws.ToString(invocation.StandardErrorContent),
		)
	}

	require.FailNowf(t, "SSM validation produced no output",
		"no output markers found after %d attempts; last status=%s, statusDetails=%s, stdout=%q, stderr=%q",
		maxAttempts,
		lastInvocation.Status,
		aws.ToString(lastInvocation.StatusDetails),
		aws.ToString(lastInvocation.StandardOutputContent),
		aws.ToString(lastInvocation.StandardErrorContent),
	)
}

func waitForSSMOnline(t *testing.T, validation validationContext) {
	t.Helper()

	deadline := time.Now().Add(10 * time.Minute)
	for {
		out, err := validation.ssmClient.DescribeInstanceInformation(context.Background(), &ssm.DescribeInstanceInformationInput{
			Filters: []ssmtypes.InstanceInformationStringFilter{
				{
					Key:    aws.String("InstanceIds"),
					Values: []string{validation.instanceID},
				},
			},
		})
		require.NoError(t, err, "failed to describe SSM instance information for %s", validation.instanceID)

		if len(out.InstanceInformationList) > 0 {
			info := out.InstanceInformationList[0]
			if info.PingStatus == ssmtypes.PingStatusOnline {
				return
			}
		}

		if time.Now().After(deadline) {
			require.FailNowf(t, "timed out waiting for SSM online state", "instance %s did not report PingStatus=Online", validation.instanceID)
		}

		time.Sleep(10 * time.Second)
	}
}

func waitForInvocationResult(t *testing.T, validation validationContext, commandID string) *ssm.GetCommandInvocationOutput {
	t.Helper()

	deadline := time.Now().Add(10 * time.Minute)
	for {
		output, err := validation.ssmClient.GetCommandInvocation(context.Background(), &ssm.GetCommandInvocationInput{
			CommandId:  aws.String(commandID),
			InstanceId: aws.String(validation.instanceID),
		})
		if err != nil {
			// SSM can briefly return InvocationDoesNotExist immediately after send-command.
			if strings.Contains(err.Error(), "InvocationDoesNotExist") {
				if time.Now().After(deadline) {
					require.FailNowf(t, "timed out waiting for SSM invocation registration", "command %s never became invocable", commandID)
				}
				time.Sleep(5 * time.Second)
				continue
			}

			require.NoError(t, err, "failed to get SSM command invocation for %s", commandID)
		}

		switch output.Status {
		case ssmtypes.CommandInvocationStatusSuccess,
			ssmtypes.CommandInvocationStatusFailed,
			ssmtypes.CommandInvocationStatusTimedOut,
			ssmtypes.CommandInvocationStatusCancelled:
			return output
		}

		if time.Now().After(deadline) {
			require.FailNowf(t, "timed out waiting for SSM command", "command %s did not reach terminal status before timeout", commandID)
		}

		time.Sleep(10 * time.Second)
	}
}

func extractValidationResults(t *testing.T, stdout string) []validationResult {
	t.Helper()

	matcher := regexp.MustCompile(`(?s)MSIX_S3_PRIVATE_VALIDATION_RESULTS_BEGIN\s*(.*?)\s*MSIX_S3_PRIVATE_VALIDATION_RESULTS_END`)
	matches := matcher.FindStringSubmatch(stdout)
	require.Len(t, matches, 2, "validation output markers were not found in SSM stdout")

	payload := strings.TrimSpace(matches[1])
	require.NotEmpty(t, payload, "validation payload between markers is empty")

	var arrayResults []validationResult
	if err := json.Unmarshal([]byte(payload), &arrayResults); err == nil {
		return arrayResults
	}

	var singleResult validationResult
	err := json.Unmarshal([]byte(payload), &singleResult)
	require.NoError(t, err, "failed to parse validation result payload: %s", payload)
	return []validationResult{singleResult}
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
