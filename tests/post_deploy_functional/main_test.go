// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package test

import (
	"os"
	"testing"

	"github.com/launchbynttdata/lcaf-component-terratest/lib"
	"github.com/launchbynttdata/lcaf-component-terratest/types"
	"github.com/launchbynttdata/tf-aws-module_reference-s3_private_distribution/tests/testimpl"
)

const (
	testConfigsExamplesFolderDefault = "../../examples/complete"
	infraTFVarFileNameDefault        = "test.tfvars"
	replicationAltRegionTFVarFile    = "test.replication-alt-region.tfvars"
	externalLoggingTFVarFile         = "test.external-logging-target.tfvars"
	loggingDisabledTFVarFile         = "test.logging-disabled.tfvars"
	replicationDisabledTFVarFile     = "test.replication-disabled.tfvars"
	lifecycleDisabledTFVarFile       = "test.lifecycle-disabled.tfvars"
	versioningDisabledTFVarFile      = "test.versioning-disabled.tfvars"
)

func buildCtx(tfvarsFile string) *types.TestContext {
	ctx := types.CreateTestContextBuilder().
		SetTestConfig(&testimpl.ThisTFModuleConfig{}).
		SetTestConfigFolderName(testConfigsExamplesFolderDefault).
		SetTestConfigFileName(tfvarsFile).
		SetTestSpecificFlags(map[string]types.TestFlags{
			"complete": {"IS_TERRAFORM_IDEMPOTENT_APPLY": true},
		}).
		Build()

	return ctx
}

func TestS3BucketCollectionFunctional(t *testing.T) {
	ctx := buildCtx(infraTFVarFileNameDefault)

	lib.RunSetupTestTeardown(t, *ctx, testimpl.TestComposableComplete)
}

func TestS3BucketCollectionFunctionalReplicationAltRegion(t *testing.T) {
	// Validates the replication-alt-region profile using the same baseline assertions.
	// Scenario-specific replication destination region checks are covered in the readonly path.
	if os.Getenv("RUN_ADDITIONAL_COMPLETE_SCENARIOS") != "true" {
		t.Skip("set RUN_ADDITIONAL_COMPLETE_SCENARIOS=true to run additional secure scenario profiles")
	}

	ctx := buildCtx(replicationAltRegionTFVarFile)
	lib.RunSetupTestTeardown(t, *ctx, testimpl.TestComposableComplete)
}

func TestS3BucketCollectionFunctionalExternalLoggingTarget(t *testing.T) {
	// Requires a pre-existing bucket named in test.external-logging-target.tfvars.
	// Set RUN_EXTERNAL_LOGGING_SCENARIO=true and provide the bucket name in the tfvars file.
	if os.Getenv("RUN_EXTERNAL_LOGGING_SCENARIO") != "true" {
		t.Skip("set RUN_EXTERNAL_LOGGING_SCENARIO=true to run external logging target scenario")
	}

	ctx := buildCtx(externalLoggingTFVarFile)
	lib.RunSetupTestTeardown(t, *ctx, testimpl.TestComposableComplete)
}

func TestS3BucketCollectionFunctionalExploratoryProfiles(t *testing.T) {
	// Exploratory non-gating lane for intentionally relaxed profiles.
	// Plan-level validation for these profiles is covered in tests/terraform/.
	// This test validates apply+destroy succeeds without asserting security posture.
	if os.Getenv("RUN_EXPLORATORY_COMPLETE_SCENARIOS") != "true" {
		t.Skip("set RUN_EXPLORATORY_COMPLETE_SCENARIOS=true to run exploratory scenario profiles")
	}

	profiles := []string{
		loggingDisabledTFVarFile,
		replicationDisabledTFVarFile,
		lifecycleDisabledTFVarFile,
		versioningDisabledTFVarFile,
	}

	for _, tfvarsFile := range profiles {
		t.Run(tfvarsFile, func(t *testing.T) {
			ctx := buildCtx(tfvarsFile)
			lib.RunSetupTestTeardown(t, *ctx, testimpl.TestComposableComplete)
		})
	}
}
