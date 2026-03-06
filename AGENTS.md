# AGENTS.md for eoapi-k8s

Executable reference for AI agents working in this repo. Follow these rules literally.

---

## 1. Before Writing Any Code

Answer these questions in order. Stop if you can't answer one.

1. **Which file(s) will change?** Name them explicitly.
2. **Which architectural boundary does this touch?** Choose one:
   - Helm template logic → `charts/eoapi/templates/_helpers/`
   - Service configuration → `charts/eoapi/templates/<service>/`
   - Default values / schema → `charts/eoapi/values.yaml` + `values.schema.json`
   - Profile overlays → `charts/eoapi/profiles/`
   - CLI tooling → `scripts/`
   - Integration tests → `tests/integration/`
   - Unit tests → `charts/eoapi/tests/`
3. **What is the minimum change that satisfies the request?** State it in one sentence.
4. **Which existing pattern does this follow?** Name it (e.g., "existing service helper in `_helpers/services.tpl`"). If no pattern exists, stop and ask before inventing one.

If any answer is "I don't know," stop. Ask a clarifying question. Do not guess.

---

## 2. Architectural Boundaries — Rules

### Helm Templates

- Logic lives in `_helpers/`. Service templates call helpers; they don't contain logic.
- `_helpers/` is organized by concern: `core.tpl`, `services.tpl`, `database.tpl`, `resources.tpl`, `validation.tpl`. Add to the right file.
- Never put business logic directly in a service template.
- Never blur the line between a profile overlay and a default value. Defaults go in `values.yaml`. Environment-specific overrides go in `profiles/`.

### Values & Schema

- `values.yaml` is the source of truth for all configuration.
- Every new value must have a corresponding entry in `values.schema.json`.
- Profiles layer on top of `values.yaml`. Later `-f` files win. Don't duplicate values across profiles.

### Database Configuration

- CloudNativePG cluster: `postgrescluster.enabled: true`
- External DB: `postgrescluster.enabled: false` + `postgresql.type: external-*` (both required together — setting one without the other is a known breakage pattern)

### ArgoCD vs Helm Hooks

- Helm hooks use `helm.sh/hook` annotations.
- ArgoCD hooks use `argocd.argoproj.io/hook` annotations.
- Never mix annotation types in the same manifest. Use `charts/eoapi/values/argocd.yaml` for ArgoCD deployments.

### Scripts / CLI

- `scripts/` implements `eoapi-cli`. See `scripts/README.md` before modifying.
- Don't add CLI commands without updating `scripts/README.md`.

---

## 3. Making Changes

**Touch only what the request requires.** For every file you modify, ask: "Did the request mention this file, or does this change directly cause a required change here?" If neither, don't touch it.

- Do not refactor adjacent code.
- Do not remove pre-existing dead code unless asked.
- Do not add error handling for scenarios the request didn't raise.
- Do match the style (indentation, naming, comment style) of surrounding code exactly.
- Do remove imports, variables, or functions that *your* changes made unused.
- Pareto principle: Focus on the 20% of work that delivers 80% of the value.

---

## 4. Required Value on Every Install/Upgrade

`gitSha` is required on every `helm install` or `helm upgrade`:

```bash
--set gitSha=$(git rev-parse HEAD | cut -c1-10)
```

If you are generating Helm commands for the user, always include this flag. Omitting it will cause the install to fail.

---

## 5. Goal-Driven Execution

Before starting any multi-step task, state a brief plan with explicit verification steps:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Transform vague tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Add HPA" → "Add template → update values + schema → run lint → run unit tests → regenerate snapshots"

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

## 6. Testing Rules

Match the test type to the boundary you changed.

| What changed | Test required | Command |
|---|---|---|
| `_helpers/*.tpl` or any template | Unit test + snapshot regeneration | `helm unittest charts/eoapi -u` |
| `values.yaml` or `values.schema.json` | Schema validation | `./eoapi-cli test schema` |
| Any Helm template | Lint | `./eoapi-cli test lint` |
| Any container configuration | Image root check | `./eoapi-cli test images` |
| `tests/integration/` or live-cluster behavior | Integration test — **do not modify without explicit human approval** | `./eoapi-cli test integration --debug` |
| `scripts/` | Run affected CLI commands manually; note in PR | — |

**Always run no-cluster tests first:**

```bash
./eoapi-cli test schema
./eoapi-cli test lint
./eoapi-cli test unit
./eoapi-cli test images
```

**Integration tests (require a cluster):**

```bash
./eoapi-cli cluster start && ./eoapi-cli deployment run && ./eoapi-cli test integration --debug  # fresh k3s
./eoapi-cli deployment run && ./eoapi-cli test integration --debug                               # existing k3s
./eoapi-cli test integration --pytest-args="-v -k test_stac"                                    # targeted
```

**Test tier ownership:**
- **Unit tests / snapshots** (`charts/eoapi/tests/`) — agents may write and update freely.
- **Integration tests** (`tests/integration/`) — these are acceptance tests encoding expected cluster behavior. Agents may read and run them. Do not modify without explicit human approval.

**Snapshots:** After any intentional template change, regenerate and commit:

```bash
helm unittest charts/eoapi -u
git add charts/eoapi/tests/__snapshot__/
```

Unexpected snapshot diffs mean the change had unintended side effects. Investigate before committing.

### When a Test Fails

1. **Lint failure:** Read the error message literally. Fix only the flagged line. Re-run lint before touching anything else.
2. **Unit test failure:** Check whether the test is wrong (expected output is stale) or the code is wrong. If stale due to an intentional change, update the test and explain why in the commit message.
3. **Snapshot diff you didn't expect:** Do not regenerate blindly. Identify which template change caused the diff. If you can't explain it, revert and ask.
4. **Integration test failure:** Check pod logs first (`kubectl logs`), then service connectivity, then values. Integration failures are almost always configuration or cluster-state issues, not code bugs.
5. **Schema validation failure:** The error output names the offending key. Add or fix its entry in `values.schema.json`. Do not modify `values.yaml` to work around a schema error.

---

## 7. Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>(<scope>): <what changed and why>

[optional body: constraints, tradeoffs, or non-obvious context]
```

Valid types: `feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `ci`

Scope = the architectural boundary: `helm`, `values`, `schema`, `profiles`, `scripts`, `tests`, `ci`

**Examples:**

```
feat(helm): add HPA template for raster service

fix(values): require postgrescluster.enabled=false for external DB configs
Prevents silent misconfiguration where both DB modes activate simultaneously.

chore(snapshots): regenerate after raster HPA template addition
```

The message must explain *why*, not just *what*. "Update values.yaml" is not acceptable.

---

## 8. Pre-Submission Checklist

Do not submit until every item is checked. Each must be concretely true, not self-assessed.

- [ ] I can name every file I changed and the reason for each change
- [ ] Every changed line traces directly to the request — nothing extra
- [ ] The correct test suite ran and passed (see Section 5 table)
- [ ] Snapshots were regenerated if any template changed, and the diff is fully explained
- [ ] `values.schema.json` updated if any new value was added
- [ ] Helm commands in docs or scripts include `--set gitSha=...`
- [ ] Commit message follows Conventional Commits and explains intent
- [ ] ArgoCD annotations are not mixed with Helm hook annotations
- [ ] External DB config sets both `postgrescluster.enabled: false` AND `postgresql.type: external-*`
- [ ] Security checked: no injection vectors, no credentials in templates, no unintended RBAC grants

---

## 9. Where to Read Before Touching Specific Areas

Read the linked doc *before* making changes in that area — not after.

| Area | Read first |
|---|---|
| Ingress (NGINX/Traefik) | `docs/unified-ingress.md` |
| ArgoCD sync waves / hooks | `docs/argocd.md` |
| Autoscaling / HPA | `docs/autoscaling.md` |
| Database setup | `docs/configuration.md` |
| Cloud-specific (EKS/GKE/Azure) | `docs/aws-eks.md`, `docs/gcp-gke.md`, `docs/azure.md` |
| CLI commands | `scripts/README.md` |
| Profiles (when to use which) | `charts/eoapi/profiles/README.md` |
| OIDC auth proxy | `docs/stac-auth-proxy.md` |
| Release process | `docs/release.md` |
| Observability stack | `docs/observability.md` |
| Contribution guidelines + AI use policy | `CONTRIBUTING.md` |

If your change touches one of these areas and you haven't read the doc, stop and read it first.
