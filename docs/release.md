### Release Workflow

1. PRs that include changes in the `helm-chart/` directory with a base of `main` should also choose a PR 
title that decides if the chart's version bumps will be major, minor or patch according to semantic versioning. 
All they need to do is prefix `major: `, `minor: ` or `patch: ` to the PR title


2. All PRs opened, synchronized or reopened against `main` will kick off a "pre-release" workflow that does the following:

   1. detect if there are changes in the `helm-chart/` directory (if no changes are detected the "pre-release.yaml" workflow exits gracefully)
   
   2. sniff the PR title to determine major, minor or patch bumps
   
   3. increment the helm chart's `version` and `appVersion` accordingly
 
   4. add a commit to the open PR with the `Chart.yaml` bumps and a commit titled: `'release version to v<version-increment>`


3. The releaser should review this PR and make sure everything (include the `Chart.yaml` bumps seem correct). Then merge the PR


3. Then the releaser should go to the Github release UI/UX and kick off a new release by doing the following:

   1. click "Draft New Release"
   
   2. create a new tag for the branch `main` with the chart version listed in the previous PR's commit message
   
   3. click the "Generate release notes"
   
   4. review the release notes and clean up
   
   5. click the "Publish release"


5. This last step then kicks off another GH Actions workflow called "release.yaml" which publishes the helm chart to the
`gh-pages`  branch


6. Verify the release is all good by running `helm repo update && helm search repo eoapi --versions`