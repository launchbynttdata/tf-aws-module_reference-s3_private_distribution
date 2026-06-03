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
	"testing"

	"github.com/launchbynttdata/lcaf-component-terratest/lib"
	"github.com/launchbynttdata/lcaf-component-terratest/types"
	"github.com/launchbynttdata/tf-aws-module_reference-s3_private_distribution/tests/testimpl"
)

const (
	testConfigsExamplesFolderDefault = "../../examples/complete"
	infraTFVarFileNameDefault        = "test.tfvars"
)

// buildCtx creates a TestContext for the given tfvars profile.
//
// IS_TERRAFORM_IDEMPOTENT_APPLY causes Terratest to run `terraform apply` twice
// and fail if the second apply produces any planned changes. This validates that
// the module's resource definitions produce stable, deterministic state.
//
// Policy note: management bypass uses explicit role/user ARN patterns
// (including STS wildcard equivalents) so SSO session name drift does not
// create second-apply diffs in policy JSON.
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
