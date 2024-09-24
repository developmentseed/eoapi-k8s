### Release Workflow

1. PRs that include changes in the `helm-chart/<eoapi> || <eoapi-support> || <postgrescluster>` charts are manually required to consider 
whether their changes are major, minor or patch (in terms of semantic versioning) and bump the appropriate 
chart `version: ` (which follows semver) and `appVersion: ` (which does not follow semver) for each affected chart

3. The releaser then merges the above PR

4. Then the releaser should go to the Github release UI/UX and kick off a new release by doing the following:

   1. click "Draft New Release"
   
   2. create a new tag increment based on the last one that matches the pattern `v<major>.<minor>.<patch>`. This does not have to match any of the chart versions you changed in the above PR. This repository is one-to-many with charts. So in terms of GH release we are saying, "we've release one of the three charts above" and the commit message will reflect that
   
   3. click the "Generate release notes"
   
   4. review the release notes and clean up and makes sure talk about which chart you released
   
   5. click the "Publish release"


5. This last step then kicks off another GH Actions workflow called "release.yaml" which publishes any helm charts
that had version bumps since the last time 

6. Verify the release is all good by running `helm repo update && helm search repo eoapi --versions`
